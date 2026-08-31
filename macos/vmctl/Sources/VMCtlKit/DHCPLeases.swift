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

    /// IP for [mac], or nil while the guest has no lease yet.
    public static func ipForMac(_ mac: String) -> String? {
        guard let text = try? String(contentsOfFile: leasesPath, encoding: .utf8) else {
            return nil
        }
        return parse(text)[normalizeMac(mac)]
    }
}
