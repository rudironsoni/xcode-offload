import Foundation

public struct SimulatorActions {
    private let runner: CommandRunning

    public init(runner: CommandRunning = SystemCommandRunner()) {
        self.runner = runner
    }

    public func listRuntimes() throws -> String {
        try runSimctl(["list", "runtimes"])
    }

    public func listDevices(availableOnly: Bool) throws -> String {
        var arguments = ["list", "devices"]
        if availableOnly {
            arguments.append("available")
        }
        return try runSimctl(arguments)
    }

    public func recreate(
        name: String,
        deviceType: String,
        runtime: String,
        boot: Bool,
        bootTimeoutSeconds: Int
    ) throws -> [String] {
        var actions: [String] = []

        _ = try? runner.run("/usr/bin/xcrun", arguments: ["simctl", "shutdown", name], environment: [:])
        _ = try? runner.run("/usr/bin/xcrun", arguments: ["simctl", "delete", name], environment: [:])
        actions.append("xcrun simctl delete \(name.shellQuoted)")

        let createResult = try runner.run(
            "/usr/bin/xcrun",
            arguments: ["simctl", "create", name, deviceType, runtime],
            environment: [:]
        )
        guard createResult.succeeded else {
            throw CommandError(nonEmptyOutput(from: createResult), exitCode: createResult.exitCode)
        }

        let udid = createResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        actions.append("xcrun simctl create \(name.shellQuoted) \(deviceType.shellQuoted) \(runtime.shellQuoted)")

        if boot {
            let bootResult = try runner.run("/usr/bin/xcrun", arguments: ["simctl", "boot", udid], environment: [:])
            if !bootResult.succeeded && !bootResult.stderr.localizedCaseInsensitiveContains("Unable to boot device in current state: Booted") {
                throw CommandError(nonEmptyOutput(from: bootResult), exitCode: bootResult.exitCode)
            }
            actions.append("xcrun simctl boot \(udid.shellQuoted)")

            let bootStatus = try runner.run(
                "/usr/bin/xcrun",
                arguments: ["simctl", "bootstatus", udid, "-b"],
                environment: ["SIMCTL_CHILD_BOOTSTATUS_TIMEOUT": "\(bootTimeoutSeconds)"]
            )
            guard bootStatus.succeeded else {
                throw CommandError(nonEmptyOutput(from: bootStatus), exitCode: bootStatus.exitCode)
            }
            actions.append("xcrun simctl bootstatus \(udid.shellQuoted) -b")
        }

        return actions
    }

    private func runSimctl(_ arguments: [String]) throws -> String {
        let result = try runner.run("/usr/bin/xcrun", arguments: ["simctl"] + arguments, environment: [:])
        guard result.succeeded else {
            throw CommandError(nonEmptyOutput(from: result), exitCode: result.exitCode)
        }
        return result.stdout
    }

    private func nonEmptyOutput(from result: ProcessResult) -> String {
        let output = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return output.isEmpty ? "simctl command failed" : output
    }
}
