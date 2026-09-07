import Foundation

/// Builds a NoCloud cloud-init seed ISO so a fresh Linux guest (cloud image
/// or installer supporting cloud-init) comes up with a known user, the
/// store's SSH key for both that user and root, and passwordless sudo —
/// which is what makes `vmctl exec`/`shell` possible without any manual
/// guest setup.
public enum CloudInit {
    public static func userData(user: String, publicKey: String, hostname: String) -> String {
        // /bin/sh, not bash: Alpine has no bash and a user with a missing
        // shell cannot exec anything over SSH. The chpasswd block writes `*`
        // hashes: `lock_passwd` leaves `!` in /etc/shadow, and Alpine's sshd
        // refuses "locked" accounts even for public-key auth — `*` means
        // "no password" without counting as locked.
        """
        #cloud-config
        hostname: \(hostname)
        users:
          - name: \(user)
            groups: [sudo, wheel]
            sudo: ALL=(ALL) NOPASSWD:ALL
            shell: /bin/sh
            lock_passwd: true
            ssh_authorized_keys:
              - \(publicKey)
        disable_root: false
        ssh_authorized_keys:
          - \(publicKey)
        ssh_pwauth: false
        chpasswd:
          expire: false
          users:
            - name: root
              password: "*"
              type: hash
            - name: \(user)
              password: "*"
              type: hash
        package_update: false
        bootcmd:
          - |
        \(indented(consoleGettyFixScript, by: 4))

        """
    }

    /// Busybox init restarts a getty for every `respawn` line in
    /// /etc/inittab whether or not the tty behind it exists. Alpine's cloud
    /// images are built for QEMU's `virt` machine and ship a getty on the
    /// PL011 UART, ttyAMA0; Virtualization.framework has no such UART, so
    /// that getty dies the instant it starts and init respawns it forever,
    /// burying the login prompt on the graphical console under an endless
    /// "can't open /dev/ttyAMA0: No such file or directory".
    ///
    /// Comment those entries out, and put a getty on the virtio console the
    /// VZ serial port does expose so `vmctl console` reaches a login prompt
    /// too. `kill -HUP 1` makes busybox init re-read the file, which stops
    /// the flood without a reboot.
    ///
    /// Nothing is appended to an inittab that has no live getty line: a
    /// systemd guest can still carry a vestigial /etc/inittab, and a busybox
    /// entry in it would be dead weight nobody reads.
    ///
    /// Wrapped in a function rather than written straight down, because
    /// cloud-init splices every `bootcmd` entry into one generated script:
    /// a bare `exit` here would swallow whatever entry came next.
    ///
    /// The three environment overrides are what let the tests run this
    /// against a fixture instead of the host's own /etc and init.
    public static let consoleGettyFixScript = """
    vmctl_fix_gettys() {
      inittab=${WSLMANAGER_INITTAB:-/etc/inittab}
      devdir=${WSLMANAGER_DEV:-/dev}
      initpid=${WSLMANAGER_INIT_PID-1}
      [ -f "$inittab" ] || return 0
      tmp="$inittab.vmctl.$$"
      : > "$tmp" || return 0
      changed=0
      gettys=0
      while IFS= read -r line || [ -n "$line" ]; do
        case $line in
          '#'*) ;;
          *:respawn:*getty*)
            gettys=1
            tty=${line%%:*}
            if [ -n "$tty" ] && [ ! -e "$devdir/$tty" ]; then
              line="#$line"
              changed=1
            fi
            ;;
        esac
        printf '%s\\n' "$line" >> "$tmp"
      done < "$inittab"
      if [ "$gettys" = 1 ] && [ -e "$devdir/hvc0" ] \\
        && ! grep -q '^hvc0:' "$inittab"; then
        printf '%s\\n' 'hvc0::respawn:/sbin/getty -L 0 hvc0 vt100' >> "$tmp"
        changed=1
      fi
      if [ "$changed" = 1 ]; then
        cat "$tmp" > "$inittab"
        [ -n "$initpid" ] && kill -HUP "$initpid" 2>/dev/null
      fi
      rm -f "$tmp"
      return 0
    }
    vmctl_fix_gettys
    """

    /// Pads every line so a multi-line script can sit inside a YAML block
    /// scalar. Empty lines stay empty: trailing blanks would be preserved
    /// verbatim in the block.
    static func indented(_ text: String, by spaces: Int) -> String {
        let pad = String(repeating: " ", count: spaces)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : pad + $0 }
            .joined(separator: "\n")
    }

    /// Without this, images that leave all networking to cloud-init (Debian
    /// genericcloud) boot with the NIC down: no DHCP lease, no SSH, and the
    /// VM looks dead.
    ///
    /// Explicit device names, not a `match` glob: cloud-init's ENI renderer
    /// (Alpine) resolves a glob at write time and can produce a config that
    /// names no real interface — replacing the image's working default with
    /// nothing. The VZ virtio NIC is `enp0s1` under systemd naming and
    /// `eth0` everywhere else; the entry for whichever name is absent is
    /// inert. `dhcp-identifier: mac` because macOS bootpd never answers the
    /// DUID client-id systemd-networkd sends by default.
    public static func networkConfig() -> String {
        """
        version: 2
        ethernets:
          eth0:
            dhcp4: true
            dhcp-identifier: mac
          enp0s1:
            dhcp4: true
            dhcp-identifier: mac

        """
    }

    public static func metaData(hostname: String, instanceId: String? = nil) -> String {
        """
        instance-id: \(instanceId ?? "iid-\(hostname)")
        local-hostname: \(hostname)
        """
    }

    /// Write the seed directory and pack it as an ISO9660 image named
    /// `cidata` via hdiutil.
    public static func writeSeedIso(
        to isoURL: URL,
        user: String,
        publicKey: String,
        hostname: String,
        instanceId: String? = nil
    ) throws {
        let fm = FileManager.default
        let seedDir = isoURL.deletingLastPathComponent().appendingPathComponent("seed.tmp")
        try? fm.removeItem(at: seedDir)
        try fm.createDirectory(at: seedDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: seedDir) }

        try userData(user: user, publicKey: publicKey, hostname: hostname)
            .write(to: seedDir.appendingPathComponent("user-data"), atomically: true, encoding: .utf8)
        try metaData(hostname: hostname, instanceId: instanceId)
            .write(to: seedDir.appendingPathComponent("meta-data"), atomically: true, encoding: .utf8)
        try networkConfig()
            .write(to: seedDir.appendingPathComponent("network-config"), atomically: true, encoding: .utf8)

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
