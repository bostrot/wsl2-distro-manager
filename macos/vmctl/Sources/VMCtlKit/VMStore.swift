import Foundation

public struct VmctlError: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// Layout and bookkeeping of the on-disk VM store: one directory per VM
/// holding config, disk image, EFI variable store, runtime state and (for
/// macOS guests) platform hardware blobs. A store-wide SSH keypair is seeded
/// into every Linux guest via cloud-init so `exec`/`shell` (and templates
/// made from one VM and imported as another) keep working.
public struct VMStore {
    public let root: URL
    private let fm = FileManager.default

    public init(root: URL) {
        self.root = root
    }

    public func ensureExists() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: per-VM paths

    public func vmDir(_ name: String) -> URL { root.appendingPathComponent(name) }
    public func configPath(_ name: String) -> URL { vmDir(name).appendingPathComponent("config.json") }
    public func diskPath(_ name: String) -> URL { vmDir(name).appendingPathComponent("disk.img") }
    public func efiStorePath(_ name: String) -> URL { vmDir(name).appendingPathComponent("efistore") }
    public func seedIsoPath(_ name: String) -> URL { vmDir(name).appendingPathComponent("seed.iso") }
    public func auxStoragePath(_ name: String) -> URL { vmDir(name).appendingPathComponent("aux.img") }
    public func hardwareModelPath(_ name: String) -> URL { vmDir(name).appendingPathComponent("hardware_model.bin") }
    public func machineIdentifierPath(_ name: String) -> URL { vmDir(name).appendingPathComponent("machine_identifier.bin") }
    public func runDir(_ name: String) -> URL { vmDir(name).appendingPathComponent("run") }
    public func pidPath(_ name: String) -> URL { runDir(name).appendingPathComponent("pid") }
    public func daemonLogPath(_ name: String) -> URL { runDir(name).appendingPathComponent("daemon.log") }
    public func serialLogPath(_ name: String) -> URL { runDir(name).appendingPathComponent("serial.log") }
    public func consoleSocketPath(_ name: String) -> URL { runDir(name).appendingPathComponent("console.sock") }

    // MARK: store-wide SSH key

    public func sshKeyPath() -> URL { root.appendingPathComponent("id_ed25519") }
    public func sshPublicKeyPath() -> URL { root.appendingPathComponent("id_ed25519.pub") }
    /// The askpass helper `authorize` hands to ssh; holds no secret itself.
    public func askpassPath() -> URL { root.appendingPathComponent("askpass.sh") }

    /// Generate the store keypair on first use (via ssh-keygen, which every
    /// macOS ships).
    public func ensureSshKey() throws {
        if fm.fileExists(atPath: sshKeyPath().path) { return }
        try ensureExists()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-q", "-t", "ed25519", "-N", "", "-C", "wslmanager-vmctl", "-f", sshKeyPath().path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw VmctlError("ssh-keygen failed with exit code \(process.terminationStatus)")
        }
    }

    public func sshPublicKey() throws -> String {
        try ensureSshKey()
        let key = try String(contentsOf: sshPublicKeyPath(), encoding: .utf8)
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: config

    public func exists(_ name: String) -> Bool {
        fm.fileExists(atPath: configPath(name).path)
    }

    public func loadConfig(_ name: String) throws -> VMConfig {
        guard exists(name) else { throw VmctlError("No VM named \"\(name)\".") }
        let data = try Data(contentsOf: configPath(name))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VMConfig.self, from: data)
    }

    public func saveConfig(_ config: VMConfig) throws {
        try fm.createDirectory(at: vmDir(config.name), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: configPath(config.name), options: .atomic)
    }

    public func allNames() throws -> [String] {
        guard fm.fileExists(atPath: root.path) else { return [] }
        let entries = try fm.contentsOfDirectory(atPath: root.path)
        return entries.filter { exists($0) }.sorted()
    }

    // MARK: runtime state

    /// PID of the VM's daemon process while it is alive, else nil. A stale
    /// pid file (crashed daemon, reboot) reads as stopped and is cleaned up.
    public func runningPid(_ name: String) -> Int32? {
        guard let text = try? String(contentsOf: pidPath(name), encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        // Signal 0 probes the process without touching it.
        if kill(pid, 0) == 0 {
            return pid
        }
        try? fm.removeItem(at: pidPath(name))
        return nil
    }

    public func isRunning(_ name: String) -> Bool { runningPid(name) != nil }

    public func writePid(_ name: String) throws {
        try fm.createDirectory(at: runDir(name), withIntermediateDirectories: true)
        try String(ProcessInfo.processInfo.processIdentifier)
            .write(to: pidPath(name), atomically: true, encoding: .utf8)
    }

    public func clearPid(_ name: String) {
        try? fm.removeItem(at: pidPath(name))
    }

    // MARK: disk

    /// Create (or grow) a raw disk image. Uses truncate-style allocation so
    /// the file is sparse until the guest writes.
    public func createDiskImage(at url: URL, sizeBytes: UInt64) throws {
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil) else {
                throw VmctlError("Could not create disk image at \(url.path)")
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let current = try handle.seekToEnd()
        if current < sizeBytes {
            try handle.truncate(atOffset: sizeBytes)
        }
    }

    public func fileSize(_ url: URL) -> UInt64 {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    // MARK: listing

    public struct VMListEntry: Codable {
        public var name: String
        public var os: String
        public var state: String
        public var cpus: Int
        public var memoryBytes: UInt64
        public var diskPath: String
        public var diskSizeBytes: UInt64
        public var user: String
        public var ip: String?
    }

    public func listEntries(ipResolver: (VMConfig) -> String? = { _ in nil }) throws -> [VMListEntry] {
        try allNames().map { name in
            let config = try loadConfig(name)
            let running = isRunning(name)
            return VMListEntry(
                name: name,
                os: config.os.rawValue,
                state: running ? "running" : "stopped",
                cpus: config.cpus,
                memoryBytes: config.memoryBytes,
                diskPath: diskPath(name).path,
                diskSizeBytes: fileSize(diskPath(name)),
                user: config.user,
                ip: running ? ipResolver(config) : nil
            )
        }
    }
}
