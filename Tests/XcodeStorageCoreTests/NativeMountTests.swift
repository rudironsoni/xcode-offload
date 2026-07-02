import Foundation
import Testing
@testable import XcodeStorageCore

@Test func nativeMountInventoryUsesApplePathsAndExternalSparsebundles() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let mounts = NativeMounts.all(config: config)

    #expect(mounts.map(\.id) == ["devices", "derived-data", "archives", "caches", "images", "volumes"])
    #expect(mounts.first { $0.id == "images" }?.mountPoint == "/Library/Developer/CoreSimulator/Images")
    #expect(mounts.first { $0.id == "volumes" }?.mountPoint == "/Library/Developer/CoreSimulator/Volumes")
    #expect(mounts.first { $0.id == "derived-data" }?.mountPoint == "/Users/rudi/Library/Developer/Xcode/DerivedData")
    #expect(mounts.allSatisfy { $0.imagePath.hasPrefix("/Volumes/ExternalXcode/Xcode/") })
    #expect(mounts.first { $0.id == "images" }?.preparation == .coreSimulatorImages)
}

@Test func nativeInstallDryRunCreatesSparsebundlesAndMountsWithoutSymlinks() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    let actions = try NativeActions(runner: NativeStubRunner(results: [:])).install(
        config: config,
        toolPath: "/opt/homebrew/bin/xcode-storage",
        scope: .all,
        load: true,
        dryRun: true
    )

    #expect(actions.contains { $0.contains("hdiutil create") && $0.contains("Images.sparsebundle") && $0.contains("-fs APFS") })
    #expect(actions.contains { $0.contains("hdiutil create") && $0.contains("DerivedData.sparsebundle") && $0.contains("-type SPARSEBUNDLE") })
    #expect(actions.contains { $0.contains("chmod 1777") && $0.contains("/mnt") })
    #expect(actions.contains { $0.contains("hdiutil attach") && $0.contains("/Library/Developer/CoreSimulator/Images") })
    #expect(actions.contains { $0 == "write \(config.nativeUserLaunchAgentPath)" })
    #expect(actions.contains { $0 == "write \(config.nativeSystemLaunchDaemonPath)" })
    #expect(!actions.contains { $0.localizedCaseInsensitiveContains("ln -s") })
}

@Test func nativeInstallRejectsSymlinkMountpoints() throws {
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
        _ = try NativeActions(runner: NativeStubRunner(results: [:])).install(
            config: config,
            toolPath: "/opt/homebrew/bin/xcode-storage",
            scope: .user,
            load: false,
            dryRun: true
        )
    }
}

@Test func nativeStatusFailsSymlinkAndWrongBackend() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createNativeFixture(config: config)
    let target = "\(home)/real-derived-data"
    try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(atPath: config.nativeDerivedDataMount)
    try FileManager.default.createSymbolicLink(atPath: config.nativeDerivedDataMount, withDestinationPath: target)

    let runner = NativeStubRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: nativeMountOutput(config: config),
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(
            exitCode: 0,
            stdout: nativeHdiutilOutput(config: config, only: ["devices"]),
            stderr: ""
        ),
        "/usr/sbin/diskutil": ProcessResult(
            exitCode: 0,
            stdout: "File System Personality:  APFS\nOwners: Enabled\n",
            stderr: ""
        )
    ])

    let report = NativeActions(runner: runner).status(config: config, scope: .user)

    #expect(!report.passed)
    #expect(report.checks.contains { $0.status == .fail && $0.label == "Native derived-data mountpoint is not a symlink" })
    #expect(report.checks.contains { $0.status == .fail && $0.label == "Native derived-data uses configured sparsebundle" })
}

@Test func nativeLaunchdPlistsPassPlutilLintAndHelpersAvoidSymlinks() throws {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let templates = NativeLaunchdTemplates(config: config, toolPath: "/opt/homebrew/bin/xcode-storage")

    try assertPlistLintPasses(templates.userAgentPlist)
    try assertPlistLintPasses(templates.systemDaemonPlist)
    #expect(templates.userAgentPlist.contains("<string>native</string>"))
    #expect(templates.systemHelper.contains("reject_symlink"))
    try assertZshSyntaxPasses(templates.systemHelper)
    #expect(templates.systemHelper.contains("/Library/Developer/CoreSimulator/Images"))
    #expect(templates.systemHelper.contains("/Library/Developer/CoreSimulator/Volumes"))
    #expect(!templates.systemHelper.localizedCaseInsensitiveContains("ln -s"))
}

@Test func nativeSystemHelperKeepsRecordPathsWithSpacesParseable() {
    let config = StorageConfig(root: "/Volumes/External Xcode", home: "/Users/rudi")
    let helper = NativeLaunchdTemplates(config: config, toolPath: "/opt/homebrew/bin/xcode-storage").systemHelper

    #expect(helper.contains("records='caches|/Volumes/External Xcode/Xcode/CoreSimulator/Caches.sparsebundle|/Library/Developer/CoreSimulator/Caches|0755|standard"))
    #expect(!helper.contains("'\\''/Volumes/External Xcode"))
    #expect(!helper.contains("|'/Volumes/External Xcode"))
}

@Test func nativeRepairSkipsImagesPreparationWhenAlreadyMounted() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createNativeFixture(config: config)

    let runner = NativeStubRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: nativeMountOutput(config: config),
            stderr: ""
        )
    ])

    let actions = try NativeActions(runner: runner).repair(
        config: config,
        toolPath: "/opt/homebrew/bin/xcode-storage",
        scope: .system,
        load: false,
        dryRun: true
    )

    #expect(actions.contains("already prepared /Library/Developer/CoreSimulator/Images"))
    #expect(!actions.contains { $0.contains("/tmp/xcode-storage-images-") && $0.contains("hdiutil attach") })
}

private struct NativeStubRunner: CommandRunning {
    let results: [String: ProcessResult]

    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult {
        results[executable] ?? ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private func createNativeFixture(config: StorageConfig) throws {
    for nativeMount in NativeMounts.all(config: config) {
        try FileManager.default.createDirectory(
            atPath: nativeMount.imagePath,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: nativeMount.mountPoint,
            withIntermediateDirectories: true
        )
    }
}

private func nativeMountOutput(config: StorageConfig) -> String {
    NativeMounts.all(config: config)
        .map { "/dev/disk1s1 on \($0.mountPoint) (apfs, local, nodev, nosuid, journaled, nobrowse)" }
        .joined(separator: "\n")
}

private func nativeHdiutilOutput(config: StorageConfig, only ids: Set<String>? = nil) -> String {
    NativeMounts.all(config: config)
        .filter { ids?.contains($0.id) ?? true }
        .map { nativeMount in
            """
            image-path      : \(nativeMount.imagePath)
            /dev/disk1s1\t41504653-0000-11AA-AA11-00306543ECAC\t\(nativeMount.mountPoint)
            """
        }
        .joined(separator: "\n================================================\n")
}

private func temporaryDirectory() throws -> String {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xcode-storage-native-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}

private func assertPlistLintPasses(_ plist: String) throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xcode-storage-native-test-\(UUID().uuidString).plist")
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
        .appendingPathComponent("xcode-storage-native-test-\(UUID().uuidString).zsh")
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
