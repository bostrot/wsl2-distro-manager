import Foundation
import Virtualization

/// Builds VZVirtualMachineConfiguration objects from a stored VMConfig,
/// following Apple's "Creating and Running a Linux Virtual Machine" and
/// "Virtualize macOS on a Mac" sample layouts.
public enum VMFactory {
    // MARK: Linux

    public static func linuxConfiguration(
        _ config: VMConfig,
        store: VMStore,
        consoleInput: FileHandle? = nil,
        consoleOutput: FileHandle? = nil
    ) throws -> VZVirtualMachineConfiguration {
        let vzConfig = VZVirtualMachineConfiguration()
        vzConfig.cpuCount = clampCpus(config.cpus)
        vzConfig.memorySize = clampMemory(config.memoryBytes)
        vzConfig.platform = VZGenericPlatformConfiguration()

        // EFI boot with a persistent variable store, so the guest's boot
        // entries survive restarts.
        let efiStoreURL = store.efiStorePath(config.name)
        let bootLoader = VZEFIBootLoader()
        if FileManager.default.fileExists(atPath: efiStoreURL.path) {
            bootLoader.variableStore = VZEFIVariableStore(url: efiStoreURL)
        } else {
            bootLoader.variableStore = try VZEFIVariableStore(
                creatingVariableStoreAt: efiStoreURL, options: [])
        }
        vzConfig.bootLoader = bootLoader

        // Main disk.
        var storage: [VZStorageDeviceConfiguration] = [
            VZVirtioBlockDeviceConfiguration(
                attachment: try VZDiskImageStorageDeviceAttachment(
                    url: store.diskPath(config.name), readOnly: false))
        ]
        // Installer ISO, while configured.
        if let isoPath = config.isoPath, !isoPath.isEmpty {
            storage.append(VZUSBMassStorageDeviceConfiguration(
                attachment: try VZDiskImageStorageDeviceAttachment(
                    url: URL(fileURLWithPath: isoPath), readOnly: true)))
        }
        // Cloud-init seed, if the VM has one. Attached as virtio-blk, not
        // USB: minimal cloud kernels (Alpine's linux-virt) ship no USB
        // drivers at all, and a seed the guest cannot see means no user and
        // no SSH key. Every cloud kernel speaks virtio.
        let seedURL = store.seedIsoPath(config.name)
        if FileManager.default.fileExists(atPath: seedURL.path) {
            storage.append(VZVirtioBlockDeviceConfiguration(
                attachment: try VZDiskImageStorageDeviceAttachment(
                    url: seedURL, readOnly: true)))
        }
        vzConfig.storageDevices = storage

        vzConfig.networkDevices = [try networkDevice(config)]
        vzConfig.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        vzConfig.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

        // Serial console. With relay handles (the daemon's ConsoleRelay) the
        // port is interactive and attachable via `vmctl console`; without
        // them (the installer path) it degrades to an output-only log — the
        // only window into a headless boot that goes wrong either way.
        try? FileManager.default.createDirectory(
            at: store.runDir(config.name), withIntermediateDirectories: true)
        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        if let consoleInput, let consoleOutput {
            serial.attachment = VZFileHandleSerialPortAttachment(
                fileHandleForReading: consoleInput,
                fileHandleForWriting: consoleOutput)
            vzConfig.serialPorts = [serial]
        } else {
            let serialLog = store.serialLogPath(config.name)
            FileManager.default.createFile(atPath: serialLog.path, contents: nil)
            if let fh = FileHandle(forWritingAtPath: serialLog.path) {
                serial.attachment = VZFileHandleSerialPortAttachment(
                    fileHandleForReading: nil, fileHandleForWriting: fh)
                vzConfig.serialPorts = [serial]
            }
        }

        // Always present, even when no window opens at start: the display
        // can be summoned later (`vmctl show`), and a device cannot be added
        // to a running VM.
        let graphics = VZVirtioGraphicsDeviceConfiguration()
        graphics.scanouts = [
            VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 800)
        ]
        vzConfig.graphicsDevices = [graphics]
        vzConfig.keyboards = [VZUSBKeyboardConfiguration()]
        vzConfig.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        try vzConfig.validate()
        return vzConfig
    }

    // MARK: macOS guest (Apple Silicon only)

    #if arch(arm64)
    public static func macosConfiguration(
        _ config: VMConfig,
        store: VMStore
    ) throws -> VZVirtualMachineConfiguration {
        let vzConfig = VZVirtualMachineConfiguration()
        vzConfig.cpuCount = clampCpus(config.cpus)
        vzConfig.memorySize = clampMemory(config.memoryBytes)

        let platform = VZMacPlatformConfiguration()
        let hardwareModelData = try Data(contentsOf: store.hardwareModelPath(config.name))
        guard let hardwareModel = VZMacHardwareModel(dataRepresentation: hardwareModelData) else {
            throw VmctlError("Stored hardware model for \(config.name) is unreadable.")
        }
        platform.hardwareModel = hardwareModel
        let identifierData = try Data(contentsOf: store.machineIdentifierPath(config.name))
        guard let identifier = VZMacMachineIdentifier(dataRepresentation: identifierData) else {
            throw VmctlError("Stored machine identifier for \(config.name) is unreadable.")
        }
        platform.machineIdentifier = identifier
        platform.auxiliaryStorage = VZMacAuxiliaryStorage(url: store.auxStoragePath(config.name))
        vzConfig.platform = platform
        vzConfig.bootLoader = VZMacOSBootLoader()

        vzConfig.storageDevices = [
            VZVirtioBlockDeviceConfiguration(
                attachment: try VZDiskImageStorageDeviceAttachment(
                    url: store.diskPath(config.name), readOnly: false))
        ]
        vzConfig.networkDevices = [try networkDevice(config)]
        vzConfig.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
        vzConfig.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        let graphics = VZMacGraphicsDeviceConfiguration()
        graphics.displays = [
            VZMacGraphicsDisplayConfiguration(
                widthInPixels: 1920, heightInPixels: 1200, pixelsPerInch: 80)
        ]
        vzConfig.graphicsDevices = [graphics]
        vzConfig.keyboards = [VZUSBKeyboardConfiguration()]
        vzConfig.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

        try vzConfig.validate()
        return vzConfig
    }
    #endif

    public static func configuration(
        _ config: VMConfig,
        store: VMStore,
        consoleInput: FileHandle? = nil,
        consoleOutput: FileHandle? = nil
    ) throws -> VZVirtualMachineConfiguration {
        switch config.os {
        case .linux:
            return try linuxConfiguration(config, store: store,
                                          consoleInput: consoleInput,
                                          consoleOutput: consoleOutput)
        case .macos:
            #if arch(arm64)
            return try macosConfiguration(config, store: store)
            #else
            throw VmctlError("macOS guests require an Apple Silicon host.")
            #endif
        }
    }

    // MARK: shared bits

    static func networkDevice(_ config: VMConfig) throws -> VZVirtioNetworkDeviceConfiguration {
        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        guard let mac = VZMACAddress(string: config.macAddress) else {
            throw VmctlError("Invalid MAC address in config: \(config.macAddress)")
        }
        network.macAddress = mac
        return network
    }

    static func clampCpus(_ requested: Int) -> Int {
        let minimum = VZVirtualMachineConfiguration.minimumAllowedCPUCount
        let maximum = VZVirtualMachineConfiguration.maximumAllowedCPUCount
        return min(max(requested, minimum), maximum)
    }

    static func clampMemory(_ requested: UInt64) -> UInt64 {
        let minimum = VZVirtualMachineConfiguration.minimumAllowedMemorySize
        let maximum = VZVirtualMachineConfiguration.maximumAllowedMemorySize
        return min(max(requested, minimum), maximum)
    }

    public static func randomMacAddress() -> String {
        VZMACAddress.randomLocallyAdministered().string
    }
}
