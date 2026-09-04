import Foundation
import Virtualization

/// Minimal argument parsing: `--key value` options, `--flag` booleans and a
/// trailing `--`-separated remainder (for exec).
public struct ArgumentBag {
    public var options: [String: String] = [:]
    public var flags: Set<String> = []
    public var remainder: [String] = []

    public init(_ args: [String], flagNames: Set<String>) {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--" {
                remainder = Array(args[(i + 1)...])
                break
            }
            if arg.hasPrefix("--") {
                let key = String(arg.dropFirst(2))
                if flagNames.contains(key) {
                    flags.insert(key)
                } else if i + 1 < args.count {
                    options[key] = args[i + 1]
                    i += 1
                }
            }
            i += 1
        }
    }

    public func require(_ key: String) throws -> String {
        guard let value = options[key], !value.isEmpty else {
            throw VmctlError("Missing required option --\(key)")
        }
        return value
    }

    public func int(_ key: String, default def: Int) -> Int {
        Int(options[key] ?? "") ?? def
    }
}

/// JSON output helpers — everything vmctl prints on success is JSON so the
/// app side never scrapes human text.
func printJson(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
}

public enum VmctlCLI {
    static let sshOptions = [
        "-o", "BatchMode=yes",
        // Only the store key: without this the user's ssh-agent keys are
        // offered first and a guest with default MaxAuthTries (Alpine: 6)
        // disconnects before the right key gets a turn.
        "-o", "IdentitiesOnly=yes",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=10",
        "-o", "LogLevel=ERROR",
    ]

    public static func defaultStoreRoot() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/WSLManager/vms")
    }

    /// Entry point. Returns the process exit code.
    public static func run(_ arguments: [String]) -> Int32 {
        var args = arguments
        var storeRoot = defaultStoreRoot()
        if let storeIndex = args.firstIndex(of: "--store"), storeIndex + 1 < args.count {
            storeRoot = URL(fileURLWithPath: args[storeIndex + 1])
            args.removeSubrange(storeIndex...(storeIndex + 1))
        }
        guard let command = args.first else {
            FileHandle.standardError.write(Data(usage.utf8))
            return 2
        }
        let rest = Array(args.dropFirst())
        let store = VMStore(root: storeRoot)

        do {
            switch command {
            case "list":
                try list(store)
            case "create":
                try create(store, rest)
            case "start":
                try start(store, rest)
            case "__run":
                try runDaemon(store, rest)
            case "stop":
                try stop(store, rest)
            case "delete":
                try delete(store, rest)
            case "status":
                try status(store, rest)
            case "ip":
                try ip(store, rest)
            case "reseed":
                try reseed(store, rest)
            case "export":
                try exportVm(store, rest)
            case "import":
                try importVm(store, rest)
            case "exec":
                return try exec(store, rest)
            case "authorize":
                try authorize(store, rest)
            case "console":
                return try console(store, rest)
            case "show":
                try show(store, rest)
            case "shell":
                return try shell(store, rest)
            case "help", "--help", "-h":
                print(usage)
            default:
                throw VmctlError("Unknown command: \(command)\n\(usage)")
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            return 1
        }
    }

    static let usage = """
    vmctl — manage Linux/macOS VMs via Apple Virtualization.framework

    Usage: vmctl [--store DIR] COMMAND [options]
      list                                  List VMs as JSON
      create --name N --os linux [--iso PATH] [--image PATH]
             [--disk-size GB] [--cpus N] [--memory GB] [--user NAME]
      create --name N --os macos [--restore-image PATH.ipsw]
             [--disk-size GB] [--cpus N] [--memory GB]
      start --name N [--gui]                Start a VM (detached daemon)
      reseed --name N                       Rewrite the cloud-init seed
      stop --name N [--force]               Stop a VM
      status --name N                       One VM's state as JSON
      ip --name N                           Guest IP as JSON
      delete --name N                       Delete a stopped VM
      export --name N --output PATH         Copy the raw disk image out
      import --name N --input PATH          New VM from a raw disk image
      exec --name N [--user U] -- CMD...    Run a command in the guest (SSH)
      authorize --name N [--user U]         Install the store's SSH key in a
                                            guest via password login; reads
                                            the password from
                                            $VMCTL_GUEST_PASSWORD
      shell --name N [--user U]             Interactive guest shell (SSH)
      console --name N                      Attach to the serial console
      show --name N                         Open/front the VM's screen window

    """

    // MARK: commands

    static func list(_ store: VMStore) throws {
        let entries = try store.listEntries { DHCPLeases.ipFor(mac: $0.macAddress, hostname: $0.name) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(["vms": entries])
        print(String(data: data, encoding: .utf8) ?? "{\"vms\":[]}")
    }

    static func create(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        guard isValidVmName(name) else {
            throw VmctlError("Invalid VM name \"\(name)\": use letters, digits, . _ -")
        }
        guard !store.exists(name) else {
            throw VmctlError("A VM named \"\(name)\" already exists.")
        }
        let osName = bag.options["os"] ?? "linux"
        guard let os = GuestOS(rawValue: osName) else {
            throw VmctlError("Unknown --os \(osName); use linux or macos.")
        }
        let diskSizeGb = bag.int("disk-size", default: os == .macos ? 64 : 32)
        let cpus = bag.int("cpus", default: os == .macos ? 4 : 2)
        let memoryGb = bag.int("memory", default: os == .macos ? 8 : 4)
        let diskSizeBytes = UInt64(diskSizeGb) * 1024 * 1024 * 1024

        try store.ensureExists()
        var config = VMConfig(
            name: name,
            os: os,
            cpus: cpus,
            memoryBytes: UInt64(memoryGb) * 1024 * 1024 * 1024,
            diskSizeBytes: diskSizeBytes,
            user: bag.options["user"] ?? "user",
            macAddress: VMFactory.randomMacAddress(),
            isoPath: bag.options["iso"]
        )

        do {
            switch os {
            case .linux:
                try createLinux(store, config: config, imagePath: bag.options["image"],
                                diskSizeBytes: diskSizeBytes)
            case .macos:
                try createMacos(store, config: &config,
                                restoreImagePath: bag.options["restore-image"],
                                diskSizeBytes: diskSizeBytes)
            }
            try store.saveConfig(config)
        } catch {
            // Leave no half-created VM behind.
            try? FileManager.default.removeItem(at: store.vmDir(name))
            throw error
        }
        printJson(["created": name])
    }

    static func createLinux(
        _ store: VMStore, config: VMConfig, imagePath: String?, diskSizeBytes: UInt64
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: store.vmDir(config.name), withIntermediateDirectories: true)

        if let imagePath, !imagePath.isEmpty {
            guard fm.fileExists(atPath: imagePath) else {
                throw VmctlError("Disk image not found: \(imagePath)")
            }
            if Qcow2.isQcow2(imagePath) {
                // Most distros publish arm64 cloud images only as qcow2;
                // convert while seeding so they Just Work as --image.
                try Qcow2.convert(from: imagePath, to: store.diskPath(config.name).path)
            } else {
                try fm.copyItem(
                    at: URL(fileURLWithPath: imagePath), to: store.diskPath(config.name))
            }
        }
        // Creates the file when there was no image and grows it either way.
        try store.createDiskImage(at: store.diskPath(config.name), sizeBytes: diskSizeBytes)

        if let isoPath = config.isoPath, !isoPath.isEmpty, !fm.fileExists(atPath: isoPath) {
            throw VmctlError("Installer ISO not found: \(isoPath)")
        }

        let publicKey = try store.sshPublicKey()
        try CloudInit.writeSeedIso(
            to: store.seedIsoPath(config.name),
            user: config.user,
            publicKey: publicKey,
            hostname: config.name)
    }

    static func createMacos(
        _ store: VMStore, config: inout VMConfig, restoreImagePath: String?,
        diskSizeBytes: UInt64
    ) throws {
        #if arch(arm64)
        try MacInstaller.createAndInstall(
            store: store, config: &config,
            restoreImagePath: restoreImagePath, diskSizeBytes: diskSizeBytes)
        #else
        throw VmctlError("macOS guests require an Apple Silicon host.")
        #endif
    }

    static func start(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: ["gui"])
        let name = try bag.require("name")
        _ = try store.loadConfig(name)
        if let pid = store.runningPid(name) {
            // Already up: with --gui the intent is "see it", so front the
            // window instead of doing nothing.
            if bag.flags.contains("gui") {
                kill(pid, SIGUSR1)
            }
            printJson(["started": name, "alreadyRunning": true])
            return
        }

        // Spawn a detached copy of this binary to own the VM's lifetime.
        // Bundle.main resolves the absolute executable path even when vmctl
        // was invoked through PATH as a bare name.
        let selfPath = URL(
            fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]
        ).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: store.runDir(name), withIntermediateDirectories: true)
        let log = store.daemonLogPath(name)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: log)

        let process = Process()
        process.executableURL = selfPath
        var daemonArgs = ["--store", store.root.path, "__run", "--name", name]
        if bag.flags.contains("gui") { daemonArgs.append("--gui") }
        process.arguments = daemonArgs
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Give the daemon a moment to fail fast (bad config, missing
        // entitlement) so the caller hears about it now, not on next list.
        for _ in 0..<20 {
            if store.isRunning(name) {
                printJson(["started": name])
                return
            }
            if !process.isRunning {
                let logText = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                // A guest can power itself off within this window (nothing
                // bootable). That is a successful start followed by a stop —
                // callers detect it via status — not a failure to start.
                if logText.contains("VM \(name) started") {
                    printJson(["started": name])
                    return
                }
                throw VmctlError("VM failed to start: \(logText.suffix(2000))")
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        printJson(["started": name])
    }

    static func runDaemon(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: ["gui"])
        let name = try bag.require("name")
        let config = try store.loadConfig(name)
        let runner = VMRunner(store: store, config: config, gui: bag.flags.contains("gui"))
        try runner.run()
    }

    static func stop(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: ["force"])
        let name = try bag.require("name")
        _ = try store.loadConfig(name)
        guard let pid = store.runningPid(name) else {
            printJson(["stopped": name, "alreadyStopped": true])
            return
        }
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if store.runningPid(name) == nil {
                printJson(["stopped": name])
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        if bag.flags.contains("force") {
            kill(pid, SIGKILL)
            store.clearPid(name)
            printJson(["stopped": name, "forced": true])
            return
        }
        throw VmctlError("VM \(name) did not stop in time; retry with --force.")
    }

    static func delete(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        _ = try store.loadConfig(name)
        guard !store.isRunning(name) else {
            throw VmctlError("VM \(name) is running; stop it before deleting.")
        }
        try FileManager.default.removeItem(at: store.vmDir(name))
        printJson(["deleted": name])
    }

    static func status(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let config = try store.loadConfig(name)
        let running = store.isRunning(name)
        var out: [String: Any] = ["name": name, "state": running ? "running" : "stopped"]
        if running, let ip = DHCPLeases.ipFor(mac: config.macAddress, hostname: config.name) {
            out["ip"] = ip
        }
        printJson(out)
    }

    /// Rewrites a VM's cloud-init seed with the current template and a fresh
    /// instance id, so the guest reapplies it on the next boot.
    ///
    /// VMs created by older builds carry a seed with no network config at
    /// all: their DHCP client sends a DUID that macOS never answers, so they
    /// boot without an address and nothing can reach them. Recreating the VM
    /// would work but throws the disk away; this repairs it in place.
    static func reseed(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let config = try store.loadConfig(name)
        let publicKey = try store.sshPublicKey()
        try CloudInit.writeSeedIso(
            to: store.seedIsoPath(config.name),
            user: config.user,
            publicKey: publicKey,
            hostname: config.name,
            instanceId: "iid-\(config.name)-\(Int(Date().timeIntervalSince1970))")
        printJson(["reseeded": name])
    }

    static func ip(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let config = try store.loadConfig(name)
        printJson(["ip": DHCPLeases.ipFor(mac: config.macAddress, hostname: config.name) as Any])
    }

    static func exportVm(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let output = try bag.require("output")
        _ = try store.loadConfig(name)
        guard !store.isRunning(name) else {
            throw VmctlError("VM \(name) is running; stop it before exporting.")
        }
        let fm = FileManager.default
        try? fm.removeItem(atPath: output)
        try fm.copyItem(at: store.diskPath(name), to: URL(fileURLWithPath: output))
        printJson(["exported": name, "output": output])
    }

    static func importVm(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let input = try bag.require("input")
        guard isValidVmName(name) else {
            throw VmctlError("Invalid VM name \"\(name)\": use letters, digits, . _ -")
        }
        guard !store.exists(name) else {
            throw VmctlError("A VM named \"\(name)\" already exists.")
        }
        guard FileManager.default.fileExists(atPath: input) else {
            throw VmctlError("Disk image not found: \(input)")
        }
        try store.ensureExists()
        let config = VMConfig(
            name: name,
            os: .linux,
            cpus: bag.int("cpus", default: 2),
            memoryBytes: UInt64(bag.int("memory", default: 4)) * 1024 * 1024 * 1024,
            diskSizeBytes: 0,
            user: bag.options["user"] ?? "user",
            macAddress: VMFactory.randomMacAddress())
        do {
            try FileManager.default.createDirectory(
                at: store.vmDir(name), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(fileURLWithPath: input), to: store.diskPath(name))
            // A fresh seed re-provisions cloud-init guests under the new
            // name; guests without cloud-init just ignore the ISO.
            try CloudInit.writeSeedIso(
                to: store.seedIsoPath(name),
                user: config.user,
                publicKey: store.sshPublicKey(),
                hostname: name)
            try store.saveConfig(config)
        } catch {
            try? FileManager.default.removeItem(at: store.vmDir(name))
            throw error
        }
        printJson(["imported": name])
    }

    static func exec(_ store: VMStore, _ rest: [String]) throws -> Int32 {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let config = try store.loadConfig(name)
        guard store.isRunning(name) else {
            throw VmctlError("VM \(name) is not running.")
        }
        guard !bag.remainder.isEmpty else {
            throw VmctlError("No command given; pass it after --")
        }
        let user = bag.options["user"] ?? config.user
        guard let ip = waitForIp(config) else {
            throw VmctlError("VM \(name) has no IP address yet (no DHCP lease).")
        }
        let ssh = Process()
        ssh.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        ssh.arguments = sshOptions
            + ["-i", store.sshKeyPath().path, "\(user)@\(ip)", "--"]
            + bag.remainder
        try ssh.run()
        ssh.waitUntilExit()
        return ssh.terminationStatus
    }

    /// Installs the store's public key in a guest that never got it from
    /// cloud-init (installer-ISO installs, imported disks), so `exec` and
    /// `shell` work by key afterwards. Signs in once with the password from
    /// `$VMCTL_GUEST_PASSWORD` — an env var, not an argument, so it is never
    /// visible in `ps` — and reports which accounts (login user, root) took
    /// the key.
    static func authorize(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let config = try store.loadConfig(name)
        guard store.isRunning(name) else {
            throw VmctlError("VM \(name) is not running.")
        }
        let user = bag.options["user"] ?? config.user
        guard let password = ProcessInfo.processInfo.environment[GuestAccess.passwordEnvVar],
              !password.isEmpty else {
            throw VmctlError(
                "Set \(GuestAccess.passwordEnvVar) to the password of \(user) in the guest.")
        }
        guard let ip = waitForIp(config) else {
            throw VmctlError("VM \(name) has no IP address yet (no DHCP lease).")
        }
        let report = try GuestAccess.install(
            publicKey: store.sshPublicKey(),
            user: user,
            ip: ip,
            password: password,
            askpassPath: store.askpassPath())
        printJson(["authorized": name, "user": user, "root": report.rootInstalled])
    }

    static func shell(_ store: VMStore, _ rest: [String]) throws -> Int32 {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let config = try store.loadConfig(name)
        guard store.isRunning(name) else {
            throw VmctlError("VM \(name) is not running.")
        }
        let user = bag.options["user"] ?? config.user
        guard let ip = waitForIp(config) else {
            throw VmctlError("VM \(name) has no IP address yet (no DHCP lease).")
        }
        let ssh = Process()
        ssh.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        ssh.arguments = sshOptions + ["-i", store.sshKeyPath().path, "\(user)@\(ip)"]
        try ssh.run()
        ssh.waitUntilExit()
        return ssh.terminationStatus
    }

    /// Ask a running VM's daemon to present its display window.
    static func show(_ store: VMStore, _ rest: [String]) throws {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        _ = try store.loadConfig(name)
        guard let pid = store.runningPid(name) else {
            throw VmctlError("VM \(name) is not running.")
        }
        kill(pid, SIGUSR1)
        printJson(["shown": name])
    }

    /// Bridge this terminal to the VM's serial console socket, raw-mode, until
    /// the socket closes or the user detaches with Ctrl-].
    static func console(_ store: VMStore, _ rest: [String]) throws -> Int32 {
        let bag = ArgumentBag(rest, flagNames: [])
        let name = try bag.require("name")
        let config = try store.loadConfig(name)
        guard config.os == .linux else {
            throw VmctlError("Serial console is only available for Linux guests.")
        }
        guard store.isRunning(name) else {
            throw VmctlError("VM \(name) is not running.")
        }

        let path = store.consoleSocketPath(name).path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw VmctlError("socket failed: \(String(cString: strerror(errno)))")
        }
        do {
            try UnixSocketAddress.connect(fd, to: path)
        } catch {
            close(fd)
            throw VmctlError("Could not attach to the console of \(name): \(error)")
        }

        FileHandle.standardError.write(Data((
            "Connected to the serial console of \(name). Detach with Ctrl-].\n"
            + "If nothing appears, the guest may not put a console on hvc0 "
            + "(kernel arg console=hvc0, or a getty on /dev/hvc0).\n").utf8))

        // Raw mode, so keystrokes (including Ctrl-C) go to the guest.
        var savedTermios = termios()
        let stdinIsTty = isatty(STDIN_FILENO) == 1
        if stdinIsTty {
            tcgetattr(STDIN_FILENO, &savedTermios)
            var raw = savedTermios
            cfmakeraw(&raw)
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        }
        defer {
            if stdinIsTty {
                tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
                FileHandle.standardError.write(Data("\nDetached.\n".utf8))
            }
            close(fd)
        }

        // One poll loop pumping both directions, so a VM that exits ends the
        // session immediately instead of waiting for the next keypress.
        var buffer = [UInt8](repeating: 0, count: 4096)
        var watched = [
            pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0),
            pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
        ]
        while true {
            watched[0].revents = 0
            watched[1].revents = 0
            guard poll(&watched, 2, -1) >= 0 else { break }
            if watched[1].revents != 0 {
                let count = read(fd, &buffer, buffer.count)
                if count <= 0 { break }
                _ = buffer.withUnsafeBytes {
                    write(STDOUT_FILENO, $0.baseAddress, count)
                }
            }
            if watched[0].revents != 0 {
                let count = read(STDIN_FILENO, &buffer, buffer.count)
                if count <= 0 { break }
                if buffer[0..<count].contains(0x1D) { break } // Ctrl-]
                _ = write(fd, &buffer, count)
            }
        }
        return 0
    }

    /// The lease can lag a fresh boot; poll briefly instead of failing the
    /// first exec after start.
    static func waitForIp(_ config: VMConfig, timeout: TimeInterval = 20) -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let ip = DHCPLeases.ipFor(mac: config.macAddress, hostname: config.name) {
                return ip
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return nil
    }
}
