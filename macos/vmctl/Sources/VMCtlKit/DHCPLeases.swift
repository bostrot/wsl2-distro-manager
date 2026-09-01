import Foundation

/// Resolves a guest's IP from the host DHCP lease table.
///
/// VMs on VZNATNetworkDeviceAttachment get their address from macOS's
/// InternetSharing DHCP server, which records leases in
/// `/var/db/dhcpd_leases` as pseudo-plist `{ name=…\n ip_address=…\n
/// hw_address=1,aa:bb:… }` blocks. Matching by MAC address is the same
/// technique Lima and Tart use.
public enum DHCPLeases {
    public static let leasesPath = "/var/db/dhcpd_leases"

    /// Parse the lease file contents and return `hw_address` → `ip_address`.
    /// MAC octets are normalised (lowercase, zero-padded) because the file
    /// drops leading zeros while VZMACAddress prints them.
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentIp: String?
        var currentMac: String?

        func flush() {
            if let ip = currentIp, let mac = currentMac {
                result[mac] = ip
            }
            currentIp = nil
            currentMac = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "{" {
                flush()
            } else if line.hasPrefix("ip_address=") {
                currentIp = String(line.dropFirst("ip_address=".count))
            } else if line.hasPrefix("hw_address=") {
                // Format: hw_address=1,aa:bb:cc:d:ee:ff
                let value = String(line.dropFirst("hw_address=".count))
                let parts = value.split(separator: ",", maxSplits: 1)
                if parts.count == 2 {
                    currentMac = normalizeMac(String(parts[1]))
                }
            }
        }
        flush()
        return result
    }

    public static func normalizeMac(_ mac: String) -> String {
        mac.lowercased()
            .split(separator: ":")
            .map { $0.count == 1 ? "0\($0)" : String($0) }
            .joined(separator: ":")
    }

    /// All lease blocks as (normalized hw/identifier octets, ip) pairs.
    /// Unlike [parse] this keeps identifiers that are not plain MACs —
    /// clients following RFC 4361 (Alpine's dhcpcd, some systemd setups)
    /// send a DUID-based client-id, which macOS records in hw_address as a
    /// long octet string whose *last six octets are the interface MAC*.
    static func entries(_ text: String) -> [(hw: String, ip: String, name: String)] {
        var result: [(String, String, String)] = []
        var currentIp: String?
        var currentHw: String?
        var currentName: String?

        func flush() {
            if let ip = currentIp, let hw = currentHw {
                result.append((hw, ip, currentName ?? ""))
            }
            currentIp = nil
            currentHw = nil
            currentName = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "{" {
                flush()
            } else if line.hasPrefix("name=") {
                currentName = String(line.dropFirst("name=".count))
            } else if line.hasPrefix("ip_address=") {
                currentIp = String(line.dropFirst("ip_address=".count))
            } else if line.hasPrefix("hw_address=") {
                let value = String(line.dropFirst("hw_address=".count))
                let parts = value.split(separator: ",", maxSplits: 1)
                if parts.count == 2 {
                    currentHw = normalizeMac(String(parts[1]))
                }
            }
        }
        flush()
        return result
    }

    /// IP for a guest within [text], most reliable signal first:
    /// 1. a lease whose hw_address is exactly [mac];
    /// 2. one whose identifier ends in the MAC (RFC 4361, dhcpcd-style);
    /// 3. one whose name equals [hostname] — systemd-networkd sends a
    ///    machine-id-derived DUID that contains no MAC at all, so for those
    ///    guests the hostname (which the cloud-init seed pins to the VM
    ///    name) is the only recoverable key. Later blocks win: the file
    ///    appends, so the newest lease for a reused name is last.
    public static func ipFor(
        mac: String, hostname: String? = nil, in text: String
    ) -> String? {
        let target = normalizeMac(mac)
        var suffixMatch: String?
        var nameMatch: String?
        for (hw, ip, name) in entries(text) {
            if hw == target { return ip }
            if hw.hasSuffix(":" + target) { suffixMatch = ip }
            if let hostname, !hostname.isEmpty, name == hostname {
                nameMatch = ip
            }
        }
        return suffixMatch ?? nameMatch
    }

    /// Compatibility shim over [ipFor].
    public static func ipForMac(_ mac: String, in text: String) -> String? {
        ipFor(mac: mac, in: text)
    }

    /// IP for the guest, or nil while it has no lease yet.
    public static func ipFor(mac: String, hostname: String? = nil) -> String? {
        guard let text = try? String(contentsOfFile: leasesPath, encoding: .utf8) else {
            return nil
        }
        return ipFor(mac: mac, hostname: hostname, in: text)
    }

    /// IP for [mac], or nil while the guest has no lease yet.
    public static func ipForMac(_ mac: String) -> String? {
        ipFor(mac: mac)
    }
}
