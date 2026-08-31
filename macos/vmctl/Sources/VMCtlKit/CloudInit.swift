import Foundation

/// Builds a NoCloud cloud-init seed ISO so a fresh Linux guest (cloud image
/// or installer supporting cloud-init) comes up with a known user, the
/// store's SSH key for both that user and root, and passwordless sudo —
/// which is what makes `vmctl exec`/`shell` possible without any manual
/// guest setup.
public enum CloudInit {
    public static func userData(user: String, publicKey: String, hostname: String) -> String {
        """
        #cloud-config
        hostname: \(hostname)
        users:
          - name: \(user)
            groups: [sudo, wheel]
            sudo: ALL=(ALL) NOPASSWD:ALL
            shell: /bin/bash
            lock_passwd: true
            ssh_authorized_keys:
              - \(publicKey)
        disable_root: false
        ssh_authorized_keys:
          - \(publicKey)
        ssh_pwauth: false
        package_update: false
        """
    }

    public static func metaData(hostname: String) -> String {
        """
        instance-id: iid-\(hostname)
        local-hostname: \(hostname)
        """
    }

    /// Write the seed directory and pack it as an ISO9660 image named
    /// `cidata` via hdiutil.
    public static func writeSeedIso(
        to isoURL: URL,
        user: String,
        publicKey: String,
        hostname: String
    ) throws {
        let fm = FileManager.default
        let seedDir = isoURL.deletingLastPathComponent().appendingPathComponent("seed.tmp")
        try? fm.removeItem(at: seedDir)
        try fm.createDirectory(at: seedDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: seedDir) }

        try userData(user: user, publicKey: publicKey, hostname: hostname)
            .write(to: seedDir.appendingPathComponent("user-data"), atomically: true, encoding: .utf8)
        try metaData(hostname: hostname)
            .write(to: seedDir.appendingPathComponent("meta-data"), atomically: true, encoding: .utf8)

        try? fm.removeItem(at: isoURL)
        // hdiutil appends .iso itself when missing, so hand it the final name.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "makehybrid", "-iso", "-joliet",
            "-default-volume-name", "cidata",
            "-o", isoURL.path,
            seedDir.path,
        ]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw VmctlError("hdiutil failed to build the cloud-init seed: \(message)")
        }
    }
}
