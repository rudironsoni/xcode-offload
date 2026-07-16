import Testing
@testable import XcodeOffloadCore

@Test func systemCommandRunnerReturnsTimeoutWithoutWaitingForProcessExit() throws {
    let result = try SystemCommandRunner().run(
        "/bin/sleep",
        arguments: ["2"],
        timeoutSeconds: 0.05
    )

    #expect(result.exitCode == 124)
    #expect(result.stderr.contains("command timed out after 0.05 seconds"))
}

@Test func systemCommandRunnerPreservesSuccessfulTimedCommandOutput() throws {
    let result = try SystemCommandRunner().run(
        "/bin/echo",
        arguments: ["responsive"],
        timeoutSeconds: 1
    )

    #expect(result.exitCode == 0)
    #expect(result.stdout == "responsive\n")
    #expect(result.stderr.isEmpty)
}
