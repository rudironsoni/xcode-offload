import Foundation
import Testing
@testable import XcodeStorageCore

@Test func nativeCertificationUserModeRunsToolSubcommandsAndCleansArtifacts() throws {
    let certRoot = try temporaryCertificationDirectory()
    let runner = CertificationRecordingRunner()
    var events: [String] = []

    try NativeCertification(runner: runner).run(
        options: NativeCertificationOptions(
            mode: .user,
            certRoot: certRoot,
            home: "/Users/rudi",
            toolPath: "/tmp/xcode-storage"
        )
    ) { events.append($0) }

    #expect(runner.calls.map(\.arguments).contains { $0.starts(with: ["native", "install"]) && $0.contains("--dry-run") })
    #expect(runner.calls.map(\.arguments).contains { $0.starts(with: ["native", "install"]) && !$0.contains("--dry-run") })
    #expect(runner.calls.map(\.arguments).contains { $0.starts(with: ["native", "status"]) && $0.contains("--json") })
    #expect(runner.calls.map(\.arguments).contains { $0.starts(with: ["native", "uninstall"]) })
    #expect(events.contains("==> native certification passed"))
    #expect((try FileManager.default.contentsOfDirectory(atPath: certRoot)).isEmpty)
}

@Test func nativeCertificationRejectsUnsafeCertRoot() throws {
    #expect(throws: CommandError.self) {
        try NativeCertification(runner: CertificationRecordingRunner()).run(
            options: NativeCertificationOptions(
                mode: .user,
                certRoot: "/Volumes",
                home: "/Users/rudi",
                toolPath: "/tmp/xcode-storage"
            )
        ) { _ in }
    }
}

@Test func nativeCertificationSystemModeRequiresExplicitGate() throws {
    let certRoot = try temporaryCertificationDirectory()

    #expect(throws: CommandError.self) {
        try NativeCertification(runner: CertificationRecordingRunner()).run(
            options: NativeCertificationOptions(
                mode: .system,
                certRoot: certRoot,
                home: "/Users/rudi",
                toolPath: "/tmp/xcode-storage"
            )
        ) { _ in }
    }
}

@Test func nativeCertificationE2ERequiresExplicitSimulatorDeletionGate() throws {
    let certRoot = try temporaryCertificationDirectory()

    #expect(throws: CommandError.self) {
        try NativeCertification(runner: CertificationRecordingRunner()).run(
            options: NativeCertificationOptions(
                mode: .e2e,
                certRoot: certRoot,
                home: "/Users/rudi",
                toolPath: "/tmp/xcode-storage"
            )
        ) { _ in }
    }
}

private struct CertificationCall: Sendable {
    let executable: String
    let arguments: [String]
    let environment: [String: String]
}

private final class CertificationRecordingRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCalls: [CertificationCall] = []

    var calls: [CertificationCall] {
        lock.withLock {
            storedCalls
        }
    }

    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult {
        lock.withLock {
            storedCalls.append(CertificationCall(executable: executable, arguments: arguments, environment: environment))
        }
        return ProcessResult(exitCode: 0, stdout: "ok\n", stderr: "")
    }
}

private func temporaryCertificationDirectory() throws -> String {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xcode-storage-cert-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}
