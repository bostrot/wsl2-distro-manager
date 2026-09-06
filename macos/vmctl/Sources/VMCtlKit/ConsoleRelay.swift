import Foundation

/// `sockaddr_un.sun_path` holds ~104 bytes on macOS, and a VM store under
/// "~/Library/Application Support/…" can exceed that. Bind/connect through
/// the socket's parent directory with a relative name when the absolute
/// path does not fit. The chdir is momentary and happens before any relay
/// thread exists (bind) or in a single-purpose CLI process (connect).
enum UnixSocketAddress {
    static func withSockaddr<T>(
        _ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T
    ) throws -> T {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else {
            throw VmctlError("Socket path still too long: \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, size) }
        }
    }

    /// Runs [operation] with a path that fits in sun_path, chdir-ing into
    /// the parent directory when the absolute path is too long.
    static func withUsablePath<T>(
        _ path: String, _ operation: (String) throws -> T
    ) throws -> T {
        let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        if path.utf8.count < capacity {
            return try operation(path)
        }
        let dir = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let previous = FileManager.default.currentDirectoryPath
        guard FileManager.default.changeCurrentDirectoryPath(dir) else {
            throw VmctlError("Socket path too long and its directory is unreachable: \(path)")
        }
        defer { _ = FileManager.default.changeCurrentDirectoryPath(previous) }
        return try operation(name)
    }

    static func bind(_ fd: Int32, to path: String) throws {
        let result = try withUsablePath(path) { usable in
            try withSockaddr(usable) { Darwin.bind(fd, $0, $1) }
        }
        guard result == 0 else {
            throw VmctlError("Could not bind \(path): \(String(cString: strerror(errno)))")
        }
    }

    static func connect(_ fd: Int32, to path: String) throws {
        let result = try withUsablePath(path) { usable in
            try withSockaddr(usable) { Darwin.connect(fd, $0, $1) }
        }
        guard result == 0 else {
            throw VmctlError(
                "Could not connect to \(path): \(String(cString: strerror(errno)))")
        }
    }
}

/// Exposes a running VM's serial port on a Unix socket, so a terminal can
/// attach to the console without the VM ever needing a display window.
///
/// The VM's serial device reads and writes one end of a socketpair; this
/// relay pumps the other end. Guest output is teed to `serial.log` (the
/// early-exit diagnostics read its tail) and forwarded to the connected
/// client; client bytes go to the guest. One client at a time — a new
/// connection replaces the previous one, `virsh console` style.
public final class ConsoleRelay {
    /// FD handed to Virtualization.framework for both directions.
    public let vmSideFd: Int32
    private let relayFd: Int32
    private let listenFd: Int32
    private let logHandle: FileHandle
    public let socketPath: String

    private let clientLock = NSLock()
    private var clientFd: Int32 = -1
    private var running = true

    public init(socketPath: String, logPath: String) throws {
        self.socketPath = socketPath

        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0 else {
            throw VmctlError("socketpair failed: \(String(cString: strerror(errno)))")
        }
        vmSideFd = fds[0]
        relayFd = fds[1]

        FileManager.default.createFile(atPath: logPath, contents: nil)
        guard let log = FileHandle(forWritingAtPath: logPath) else {
            throw VmctlError("Could not open \(logPath) for the serial log")
        }
        logHandle = log

        // A socket file from a previous (crashed) daemon would block bind.
        unlink(socketPath)
        listenFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFd >= 0 else {
            throw VmctlError("socket failed: \(String(cString: strerror(errno)))")
        }
        try UnixSocketAddress.bind(listenFd, to: socketPath)
        guard listen(listenFd, 2) == 0 else {
            throw VmctlError("Could not listen on \(socketPath): \(String(cString: strerror(errno)))")
        }
    }

    public func start() {
        // Guest → log + client.
        Thread.detachNewThread { [self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while running {
                let count = read(relayFd, &buffer, buffer.count)
                if count <= 0 { break }
                let data = Data(buffer[0..<count])
                try? logHandle.write(contentsOf: data)
                clientLock.lock()
                let fd = clientFd
                clientLock.unlock()
                if fd >= 0 {
                    _ = data.withUnsafeBytes { write(fd, $0.baseAddress, count) }
                }
            }
        }

        // Clients: accept immediately, hand each connection its own reader
        // thread, and retire the previous client via shutdown() — its reader
        // sees EOF and closes the fd itself, so every fd has exactly one
        // owner and a stuck client can never block the accept loop.
        Thread.detachNewThread { [self] in
            while running {
                let fd = accept(listenFd, nil, nil)
                if fd < 0 { break }
                clientLock.lock()
                let previous = clientFd
                clientFd = fd
                clientLock.unlock()
                if previous >= 0 {
                    Darwin.shutdown(previous, SHUT_RDWR)
                }
                Thread.detachNewThread { [self] in
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while running {
                        let count = read(fd, &buffer, buffer.count)
                        if count <= 0 { break }
                        _ = write(relayFd, &buffer, count)
                    }
                    clientLock.lock()
                    if clientFd == fd {
                        clientFd = -1
                    }
                    clientLock.unlock()
                    close(fd)
                }
            }
        }
    }

    public func shutdown() {
        running = false
        clientLock.lock()
        let fd = clientFd
        clientLock.unlock()
        if fd >= 0 {
            // The reader owns the close; this only unblocks it.
            Darwin.shutdown(fd, SHUT_RDWR)
        }
        close(listenFd)
        close(relayFd)
        unlink(socketPath)
    }
}
