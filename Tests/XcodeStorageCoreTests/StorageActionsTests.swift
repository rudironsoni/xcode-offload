import Foundation
import Testing
@testable import XcodeStorageCore

@Test func mountSkipsAlreadyMountedDeviceStore() throws {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let actions = StorageActions(
        runner: StubRunner(results: [
            "/sbin/mount": ProcessResult(
                exitCode: 0,
                stdout: "/dev/disk7s1 on /Users/rudi/Library/Developer/CoreSimulator/Devices (apfs, local)\n",
                stderr: ""
            )
        ])
    )

    let plan = try actions.mount(.devices, config: config, dryRun: false)

    #expect(plan == ["already mounted /Users/rudi/Library/Developer/CoreSimulator/Devices"])
}

@Test func systemLaunchdInstallRequiresRootOutsideDryRun() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let actions = StorageActions(runner: StubRunner(results: [:]))

    #expect(throws: CommandError.self) {
        _ = try actions.installLaunchd(
            config: config,
            toolPath: "/opt/homebrew/bin/xcode-storage",
            scope: .system,
            load: false,
            dryRun: false
        )
    }
}

private struct StubRunner: CommandRunning {
    let results: [String: ProcessResult]

    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult {
        results[executable] ?? ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
