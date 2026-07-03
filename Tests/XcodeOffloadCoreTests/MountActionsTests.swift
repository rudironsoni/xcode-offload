import Foundation
import Testing
@testable import XcodeOffloadCore

@Test func managedMountInventoryUsesApplePathsAndExternalSparsebundles() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let mounts = ManagedMounts.all(config: config)

    #expect(mounts.map(\.id) == ["devices", "derived-data", "archives", "caches", "images", "volumes", "xcode-apps"])
    #expect(mounts.first { $0.id == "images" }?.mountPoint == "/Library/Developer/CoreSimulator/Images")
    #expect(mounts.first { $0.id == "volumes" }?.mountPoint == "/Library/Developer/CoreSimulator/Volumes")
    #expect(mounts.first { $0.id == "xcode-apps" }?.mountPoint == "/Applications/Xcodes")
    #expect(mounts.first { $0.id == "derived-data" }?.mountPoint == "/Users/rudi/Library/Developer/Xcode/DerivedData")
    #expect(mounts.allSatisfy { $0.imagePath.hasPrefix("/Volumes/ExternalXcode/Xcode/") })
    #expect(mounts.first { $0.id == "images" }?.preparation == .coreSimulatorImages)
}

@Test func mountInstallDryRunCreatesSparsebundlesAndMountsWithoutSymlinks() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    let actions = try MountActions(runner: MountStubRunner(results: [:])).install(
        config: config,
        toolPath: "/opt/homebrew/bin/xcode-offload",
        scope: .all,
        load: true,
        dryRun: true
    )

    #expect(actions.contains { $0.contains("hdiutil create") && $0.contains("Images.sparsebundle") && $0.contains("-fs APFS") })
    #expect(actions.contains { $0.contains("hdiutil create") && $0.contains("DerivedData.sparsebundle") && $0.contains("-type SPARSEBUNDLE") })
    #expect(actions.contains { $0.contains("chmod 1777") && $0.contains("/mnt") })
    #expect(actions.contains { $0.contains("hdiutil attach") && $0.contains("/Library/Developer/CoreSimulator/Images") })
    #expect(actions.contains { $0.contains("xcrun") && $0.contains("simctl") && $0.contains("scan-and-mount") })
    #expect(actions.contains { $0 == "write \(config.mountUserLaunchAgentPath)" })
    #expect(actions.contains { $0 == "write \(config.mountSystemLaunchDaemonPath)" })
    #expect(!actions.contains { $0.localizedCaseInsensitiveContains("ln -s") })
}

@Test func mountInstallRejectsSymlinkMountpoints() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    let target = "\(home)/real-devices"
    try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        atPath: URL(fileURLWithPath: config.deviceMount).deletingLastPathComponent().path,
        withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(atPath: config.deviceMount, withDestinationPath: target)

    #expect(throws: CommandError.self) {
        _ = try MountActions(runner: MountStubRunner(results: [:])).install(
            config: config,
            toolPath: "/opt/homebrew/bin/xcode-offload",
            scope: .user,
            load: false,
            dryRun: true
        )
    }
}

@Test func mountStatusFailsSymlinkAndWrongBackend() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createMountFixture(config: config)
    let target = "\(home)/real-derived-data"
    try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(atPath: config.mountDerivedDataMount)
    try FileManager.default.createSymbolicLink(atPath: config.mountDerivedDataMount, withDestinationPath: target)

    let runner = MountStubRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: managedMountOutput(config: config),
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(
            exitCode: 0,
            stdout: mountHdiutilOutput(config: config, only: ["devices"]),
            stderr: ""
        ),
        "/usr/sbin/diskutil": ProcessResult(
            exitCode: 0,
            stdout: "File System Personality:  APFS\nOwners: Enabled\n",
            stderr: ""
        )
    ])

    let report = MountActions(runner: runner).status(config: config, scope: .user)

    #expect(!report.passed)
    #expect(report.checks.contains { $0.status == .fail && $0.label == "Mount derived-data mountpoint is not a symlink" })
    #expect(report.checks.contains { $0.status == .fail && $0.label == "Mount derived-data uses configured sparsebundle" })
}

@Test func mountLaunchdPlistsPassPlutilLintAndHelpersAvoidSymlinks() throws {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let templates = MountLaunchdTemplates(config: config, toolPath: "/opt/homebrew/bin/xcode-offload")

    try assertPlistLintPasses(templates.userAgentPlist)
    try assertPlistLintPasses(templates.systemDaemonPlist)
    #expect(templates.userAgentPlist.contains("<string>mounts</string>"))
    #expect(templates.systemHelper.contains("reject_symlink"))
    #expect(templates.systemHelper.contains("nested_mounts_under"))
    #expect(templates.systemHelper.contains("mountpoint contains active nested mounts"))
    #expect(templates.systemHelper.contains(config.mountSystemBackupRoot))
    #expect(!templates.systemHelper.contains(config.mountUserBackupRoot))
    #expect(templates.systemHelper.contains("simctl runtime scan-and-mount"))
    try assertZshSyntaxPasses(templates.systemHelper)
    #expect(templates.systemHelper.contains("/Library/Developer/CoreSimulator/Images"))
    #expect(templates.systemHelper.contains("/Library/Developer/CoreSimulator/Volumes"))
    #expect(templates.systemHelper.contains("/Applications/Xcodes"))
    #expect(!templates.systemHelper.localizedCaseInsensitiveContains("ln -s"))
}

@Test func mountSystemHelperKeepsRecordPathsWithSpacesParseable() {
    let config = StorageConfig(root: "/Volumes/External Xcode", home: "/Users/rudi")
    let helper = MountLaunchdTemplates(config: config, toolPath: "/opt/homebrew/bin/xcode-offload").systemHelper

    #expect(helper.contains("images=('/Volumes/External Xcode/Xcode/CoreSimulator/Caches.sparsebundle'"))
    #expect(helper.contains("mountpoints=(/Library/Developer/CoreSimulator/Caches"))
    #expect(helper.contains("mounted_from_configured_backend"))
    #expect(helper.contains("already mounted from a different backend"))
    #expect(helper.contains("trim(value) == image"))
    #expect(helper.contains("equivalent_path(value, mountpoint)"))
    #expect(!helper.contains("IFS='|'"))
    #expect(!helper.contains("index($0, image)"))
}

@Test func mountRepairSkipsImagesPreparationWhenAlreadyMounted() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createMountFixture(config: config)

    let runner = MountStubRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: managedMountOutput(config: config),
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(
            exitCode: 0,
            stdout: mountHdiutilOutput(config: config),
            stderr: ""
        )
    ])

    let actions = try MountActions(runner: runner).repair(
        config: config,
        toolPath: "/opt/homebrew/bin/xcode-offload",
        scope: .system,
        load: false,
        dryRun: true
    )

    #expect(actions.contains("already prepared /Library/Developer/CoreSimulator/Images"))
    #expect(!actions.contains { $0.contains("/tmp/xcode-offload-images-") && $0.contains("hdiutil attach") })
}

@Test func userMountInstallUsesUserBackupRootForExistingData() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createMountFixture(config: config)
    try "marker".write(
        toFile: "\(config.deviceMount)/existing-file",
        atomically: true,
        encoding: .utf8
    )

    let actions = try MountActions(runner: MountStubRunner(results: [:])).install(
        config: config,
        toolPath: "/opt/homebrew/bin/xcode-offload",
        scope: .user,
        load: false,
        dryRun: true
    )

    #expect(actions.contains { $0.contains("mv \(config.deviceMount)") && $0.contains(config.mountUserBackupRoot) })
    #expect(!actions.contains { $0.contains("mv \(config.deviceMount)") && $0.contains(config.mountSystemBackupRoot) })
    #expect(!actions.contains { $0.contains("mv \(config.deviceMount)") && $0.contains(config.mountBackupRoot) })
}

@Test func mountInstallRejectsAlreadyMountedWrongBackend() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createMountFixture(config: config)

    let runner = MountStubRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: "/dev/disk9s1 on \(config.deviceMount) (apfs, local, nodev, nosuid, journaled, nobrowse)",
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(
            exitCode: 0,
            stdout: mountHdiutilOutput(config: config, only: ["derived-data"]),
            stderr: ""
        )
    ])

    #expect(throws: CommandError.self) {
        _ = try MountActions(runner: runner).install(
            config: config,
            toolPath: "/opt/homebrew/bin/xcode-offload",
            scope: .user,
            load: false,
            dryRun: true
        )
    }
}

@Test func mountInstallRejectsNestedRuntimeMountBeforeMovingVolumesParent() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createMountFixture(config: config)
    let runtimeMount = "\(config.mountVolumesMount)/iOS_23F77"
    let runner = MountStubRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: "/dev/disk7s1 on \(runtimeMount) (apfs, sealed, local, nodev, nosuid, read-only, journaled, noatime, nobrowse)",
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(exitCode: 0, stdout: "", stderr: "")
    ])

    do {
        _ = try MountActions(runner: runner).install(
            config: config,
            toolPath: "/opt/homebrew/bin/xcode-offload",
            scope: .system,
            load: false,
            dryRun: true
        )
        Issue.record("expected nested runtime mount to be rejected")
    } catch let error as CommandError {
        #expect(error.exitCode == 78)
        #expect(error.message.contains("mountpoint contains active nested mounts"))
        #expect(error.message.contains(runtimeMount))
        #expect(error.message.contains("Shut down simulators"))
    }
}

@Test func mountUninstallRefusesToDetachWrongBackend() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createMountFixture(config: config)

    let runner = MountStubRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: "/dev/disk9s1 on \(config.deviceMount) (apfs, local, nodev, nosuid, journaled, nobrowse)",
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(
            exitCode: 0,
            stdout: mountHdiutilOutput(config: config, only: ["derived-data"]),
            stderr: ""
        )
    ])

    #expect(throws: CommandError.self) {
        _ = try MountActions(runner: runner).uninstall(
            config: config,
            scope: .user,
            unload: false,
            dryRun: true
        )
    }
}

private struct MountStubRunner: CommandRunning {
    let results: [String: ProcessResult]

    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult {
        results[executable] ?? ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private func createMountFixture(config: StorageConfig) throws {
    for managedMount in ManagedMounts.all(config: config) {
        try FileManager.default.createDirectory(
            atPath: managedMount.imagePath,
            withIntermediateDirectories: true
        )
        if managedMount.mountPoint.hasPrefix(config.home) {
            try FileManager.default.createDirectory(
                atPath: managedMount.mountPoint,
                withIntermediateDirectories: true
            )
        }
    }
}

private func managedMountOutput(config: StorageConfig) -> String {
    ManagedMounts.all(config: config)
        .map { "/dev/disk1s1 on \($0.mountPoint) (apfs, local, nodev, nosuid, journaled, nobrowse)" }
        .joined(separator: "\n")
}

private func mountHdiutilOutput(config: StorageConfig, only ids: Set<String>? = nil) -> String {
    ManagedMounts.all(config: config)
        .filter { ids?.contains($0.id) ?? true }
        .map { managedMount in
            """
            image-path      : \(managedMount.imagePath)
            /dev/disk1s1\t41504653-0000-11AA-AA11-00306543ECAC\t\(managedMount.mountPoint)
            """
        }
        .joined(separator: "\n================================================\n")
}

private func temporaryDirectory() throws -> String {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xcode-offload-mounts-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}

private func assertPlistLintPasses(_ plist: String) throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xcode-offload-mounts-test-\(UUID().uuidString).plist")
    try plist.write(to: url, atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: url)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
    process.arguments = ["-lint", url.path]
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
}

private func assertZshSyntaxPasses(_ script: String) throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xcode-offload-mounts-test-\(UUID().uuidString).zsh")
    try script.write(to: url, atomically: true, encoding: .utf8)
    defer {
        try? FileManager.default.removeItem(at: url)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-n", url.path]
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
}
