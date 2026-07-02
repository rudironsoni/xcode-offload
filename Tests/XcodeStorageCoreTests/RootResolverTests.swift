import Testing
@testable import XcodeStorageCore

@Test func rootResolverDoesNotGuessAMachineSpecificDefault() {
    #expect(throws: CommandError.self) {
        try RootResolver.resolveRoot(explicitRoot: nil, environment: [:], runner: StubRunner())
    }
}

@Test func rootResolverUsesProductEnvironmentRoot() throws {
    let root = try RootResolver.resolveRoot(
        explicitRoot: nil,
        environment: ["XCODE_STORAGE_ROOT": "/Volumes/ExternalXcode"],
        runner: StubRunner()
    )

    #expect(root == "/Volumes/ExternalXcode")
}

@Test func rootResolverUsesConfiguredVolumeName() throws {
    let root = try RootResolver.resolveRoot(
        explicitRoot: nil,
        environment: ["XCODE_STORAGE_VOLUME_NAME": "ExternalXcode"],
        runner: StubRunner()
    )

    #expect(root == "/Volumes/ExternalXcode")
}

private struct StubRunner: CommandRunning {
    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult {
        ProcessResult(exitCode: 1, stdout: "", stderr: "")
    }
}
