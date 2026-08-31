import Foundation

/// Guest operating system family.
public enum GuestOS: String, Codable {
    case linux
    case macos
}

/// Persistent per-VM configuration, stored as `config.json` in the VM's
/// directory. Everything needed to rebuild the VZVirtualMachineConfiguration
/// on each start lives here.
public struct VMConfig: Codable, Equatable {
    public var name: String
    public var os: GuestOS
    public var cpus: Int
    public var memoryBytes: UInt64
    public var diskSizeBytes: UInt64
    /// Default guest user seeded via cloud-init (linux only).
    public var user: String
    /// Stable MAC address so DHCP leases (and therefore the guest IP) survive
    /// restarts.
    public var macAddress: String
    /// Installer ISO attached until the user detaches it (linux only).
    public var isoPath: String?
    public var createdAt: Date

    public init(
        name: String,
        os: GuestOS,
        cpus: Int,
        memoryBytes: UInt64,
        diskSizeBytes: UInt64,
        user: String,
        macAddress: String,
        isoPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.name = name
        self.os = os
        self.cpus = cpus
        self.memoryBytes = memoryBytes
        self.diskSizeBytes = diskSizeBytes
        self.user = user
        self.macAddress = macAddress
        self.isoPath = isoPath
        self.createdAt = createdAt
    }
}

/// A valid VM name is also a safe directory name; refuse anything else
/// instead of escaping it.
public func isValidVmName(_ name: String) -> Bool {
    guard !name.isEmpty, name.count <= 64 else { return false }
    return name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
        && !name.hasPrefix(".")
}
