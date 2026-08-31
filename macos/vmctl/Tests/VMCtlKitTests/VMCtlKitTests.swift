import Foundation
import Testing
@testable import VMCtlKit

@Suite struct VMNameTests {
    @Test func validNames() {
        #expect(isValidVmName("ubuntu"))
        #expect(isValidVmName("my-vm_2.0"))
        #expect(!(isValidVmName("")))
        #expect(!(isValidVmName(".hidden")))
        #expect(!(isValidVmName("has space")))
        #expect(!(isValidVmName("../escape")))
        #expect(!(isValidVmName(String(repeating: "a", count: 65))))
    }
}

@Suite struct DHCPLeasesTests {
    @Test func parsesLeaseBlocks() {
        let sample = """
        {
        \tname=ubuntu
        \tip_address=192.168.64.5
        \thw_address=1,aa:bb:cc:d:ee:ff
        \tidentifier=1,aa:bb:cc:d:ee:ff
        \tlease=0x66aa
        }
        {
        \tname=other
        \tip_address=192.168.64.9
        \thw_address=1,11:22:33:44:55:66
        }
        """
        let leases = DHCPLeases.parse(sample)
        // Octets are zero-padded on the way in.
        #expect(leases["aa:bb:cc:0d:ee:ff"] == "192.168.64.5")
        #expect(leases["11:22:33:44:55:66"] == "192.168.64.9")
    }

    @Test func normalizeMacPadsAndLowercases() {
        #expect(DHCPLeases.normalizeMac("AA:B:1:22:3:F") == "aa:0b:01:22:03:0f")
    }

    @Test func lookupUsesNormalizedMac() {
        let sample = "{\nip_address=10.0.0.2\nhw_address=1,a:b:c:d:e:f\n}"
        let leases = DHCPLeases.parse(sample)
        #expect(leases[DHCPLeases.normalizeMac("0A:0B:0C:0D:0E:0F")] == "10.0.0.2")
    }
}

@Suite struct CloudInitTests {
    @Test func userDataContainsUserAndKey() {
        let text = CloudInit.userData(
            user: "eric", publicKey: "ssh-ed25519 AAAA test", hostname: "dev")
        #expect(text.hasPrefix("#cloud-config"))
        #expect(text.contains("name: eric"))
        #expect(text.contains("ssh-ed25519 AAAA test"))
        #expect(text.contains("hostname: dev"))
        #expect(text.contains("NOPASSWD:ALL"))
    }

    @Test func metaDataCarriesInstanceId() {
        let text = CloudInit.metaData(hostname: "dev")
        #expect(text.contains("instance-id: iid-dev"))
        #expect(text.contains("local-hostname: dev"))
    }
}

@Suite final class VMStoreTests {
    let tempRoot: URL
    let store: VMStore

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("vmctl-tests-\(UUID().uuidString)")
        store = VMStore(root: tempRoot)
        try store.ensureExists()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    @Test func configRoundTrip() throws {
        let config = VMConfig(
            name: "trip", os: .linux, cpus: 3,
            memoryBytes: 2_147_483_648, diskSizeBytes: 1_073_741_824,
            user: "dev", macAddress: "aa:bb:cc:dd:ee:ff")
        try store.saveConfig(config)
        let loaded = try store.loadConfig("trip")
        #expect(loaded.name == config.name)
        #expect(loaded.os == .linux)
        #expect(loaded.cpus == 3)
        #expect(loaded.memoryBytes == 2_147_483_648)
        #expect(loaded.user == "dev")
        #expect(loaded.macAddress == "aa:bb:cc:dd:ee:ff")
    }

    @Test func missingConfigThrows() {
        #expect(throws: (any Error).self) { try store.loadConfig("nope") }
    }

    @Test func allNamesListsOnlyRealVms() throws {
        try store.saveConfig(VMConfig(
            name: "b", os: .linux, cpus: 1, memoryBytes: 1, diskSizeBytes: 1,
            user: "u", macAddress: "aa:aa:aa:aa:aa:aa"))
        try store.saveConfig(VMConfig(
            name: "a", os: .linux, cpus: 1, memoryBytes: 1, diskSizeBytes: 1,
            user: "u", macAddress: "aa:aa:aa:aa:aa:ab"))
        // A stray directory without config.json is not a VM.
        try FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent("junk"),
            withIntermediateDirectories: true)
        #expect(try store.allNames() == ["a", "b"])
    }

    @Test func createDiskImageIsSparseAndGrows() throws {
        let disk = tempRoot.appendingPathComponent("disk.img")
        try store.createDiskImage(at: disk, sizeBytes: 4096 * 10)
        #expect(store.fileSize(disk) == 4096 * 10)
        // Growing keeps content; shrinking never happens.
        try store.createDiskImage(at: disk, sizeBytes: 4096 * 5)
        #expect(store.fileSize(disk) == 4096 * 10)
        try store.createDiskImage(at: disk, sizeBytes: 4096 * 20)
        #expect(store.fileSize(disk) == 4096 * 20)
    }

    @Test func stalePidReadsAsStopped() throws {
        let name = "stale"
        try store.saveConfig(VMConfig(
            name: name, os: .linux, cpus: 1, memoryBytes: 1, diskSizeBytes: 1,
            user: "u", macAddress: "aa:aa:aa:aa:aa:ac"))
        try FileManager.default.createDirectory(
            at: store.runDir(name), withIntermediateDirectories: true)
        // A PID that can't exist.
        try "999999".write(to: store.pidPath(name), atomically: true, encoding: .utf8)
        #expect(!(store.isRunning(name)))
        // And the stale file is cleaned up.
        #expect(!(FileManager.default.fileExists(atPath: store.pidPath(name).path)))
    }

    @Test func listEntriesReportsState() throws {
        try store.saveConfig(VMConfig(
            name: "one", os: .linux, cpus: 2, memoryBytes: 1024, diskSizeBytes: 0,
            user: "dev", macAddress: "aa:aa:aa:aa:aa:ad"))
        let entries = try store.listEntries { _ in "10.0.0.9" }
        #expect(entries.count == 1)
        #expect(entries[0].name == "one")
        #expect(entries[0].state == "stopped")
        // The resolver only runs for running VMs.
        #expect(entries[0].ip == nil)
        #expect(entries[0].user == "dev")
    }
}

@Suite struct ArgumentBagTests {
    @Test func optionsFlagsAndRemainder() {
        let bag = ArgumentBag(
            ["--name", "vm1", "--gui", "--user", "root", "--", "echo", "hi"],
            flagNames: ["gui"])
        #expect(bag.options["name"] == "vm1")
        #expect(bag.options["user"] == "root")
        #expect(bag.flags.contains("gui"))
        #expect(bag.remainder == ["echo", "hi"])
    }

    @Test func requireThrowsWhenMissing() {
        let bag = ArgumentBag([], flagNames: [])
        #expect(throws: (any Error).self) { try bag.require("name") }
    }

    @Test func intFallsBackToDefault() {
        let bag = ArgumentBag(["--cpus", "8", "--memory", "x"], flagNames: [])
        #expect(bag.int("cpus", default: 2) == 8)
        #expect(bag.int("memory", default: 4) == 4)
        #expect(bag.int("disk-size", default: 32) == 32)
    }
}
