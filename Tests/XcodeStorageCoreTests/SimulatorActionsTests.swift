import Foundation
import Testing
@testable import XcodeStorageCore

@Test func simulatorListsAvailableDevicesByDefault() throws {
    let runner = RecordingRunner { _, arguments, _ in
        #expect(arguments == ["simctl", "list", "devices", "available"])
        return ProcessResult(exitCode: 0, stdout: "== Devices ==\n", stderr: "")
    }

    let output = try SimulatorActions(runner: runner).listDevices(availableOnly: true)

    #expect(output == "== Devices ==\n")
}

@Test func simulatorListsAllDevicesWhenRequested() throws {
    let runner = RecordingRunner { _, arguments, _ in
        #expect(arguments == ["simctl", "list", "devices"])
        return ProcessResult(exitCode: 0, stdout: "== Devices ==\n", stderr: "")
    }

    let output = try SimulatorActions(runner: runner).listDevices(availableOnly: false)

    #expect(output == "== Devices ==\n")
}

@Test func simulatorRecreateDeletesCreatesBootsAndWaits() throws {
    let runner = RecordingRunner { _, arguments, environment in
        switch arguments {
        case ["simctl", "shutdown", "Orlix"]:
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        case ["simctl", "delete", "Orlix"]:
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        case ["simctl", "create", "Orlix", "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "com.apple.CoreSimulator.SimRuntime.iOS-26-5"]:
            return ProcessResult(exitCode: 0, stdout: "NEW-UDID\n", stderr: "")
        case ["simctl", "boot", "NEW-UDID"]:
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        case ["simctl", "bootstatus", "NEW-UDID", "-b"]:
            #expect(environment["SIMCTL_CHILD_BOOTSTATUS_TIMEOUT"] == "42")
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        default:
            return ProcessResult(exitCode: 99, stdout: "", stderr: "unexpected \(arguments)")
        }
    }

    let plan = try SimulatorActions(runner: runner).recreate(
        name: "Orlix",
        deviceType: "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
        runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        boot: true,
        bootTimeoutSeconds: 42
    )

    #expect(plan == [
        "xcrun simctl delete Orlix",
        "xcrun simctl create Orlix com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        "xcrun simctl boot NEW-UDID",
        "xcrun simctl bootstatus NEW-UDID -b"
    ])
}

@Test func simulatorRecreateAcceptsAlreadyBootedDevice() throws {
    let runner = RecordingRunner { _, arguments, _ in
        switch arguments {
        case ["simctl", "create", "Orlix", "device", "runtime"]:
            return ProcessResult(exitCode: 0, stdout: "BOOTED-UDID\n", stderr: "")
        case ["simctl", "boot", "BOOTED-UDID"]:
            return ProcessResult(exitCode: 2, stdout: "", stderr: "Unable to boot device in current state: Booted")
        default:
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
    }

    let plan = try SimulatorActions(runner: runner).recreate(
        name: "Orlix",
        deviceType: "device",
        runtime: "runtime",
        boot: true,
        bootTimeoutSeconds: 5
    )

    #expect(plan.contains("xcrun simctl boot BOOTED-UDID"))
}

@Test func simulatorRecreateFailsWhenBootstatusFails() {
    let runner = RecordingRunner { _, arguments, _ in
        switch arguments {
        case ["simctl", "create", "Orlix", "device", "runtime"]:
            return ProcessResult(exitCode: 0, stdout: "UDID\n", stderr: "")
        case ["simctl", "bootstatus", "UDID", "-b"]:
            return ProcessResult(exitCode: 65, stdout: "", stderr: "Data Migration Failed")
        default:
            return ProcessResult(exitCode: 0, stdout: "", stderr: "")
        }
    }

    #expect(throws: CommandError.self) {
        _ = try SimulatorActions(runner: runner).recreate(
            name: "Orlix",
            deviceType: "device",
            runtime: "runtime",
            boot: true,
            bootTimeoutSeconds: 5
        )
    }
}

private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    typealias Handler = @Sendable (String, [String], [String: String]) throws -> ProcessResult

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult {
        try handler(executable, arguments, environment)
    }
}

