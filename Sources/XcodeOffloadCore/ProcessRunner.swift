import Darwin
import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool {
        exitCode == 0
    }

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning: Sendable {
    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult

    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval
    ) throws -> ProcessResult
}

public extension CommandRunning {
    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds _: TimeInterval
    ) throws -> ProcessResult {
        try run(executable, arguments: arguments, environment: environment)
    }
}

public struct SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) throws -> ProcessResult {
        try runProcess(
            executable,
            arguments: arguments,
            environment: environment,
            timeoutSeconds: nil
        )
    }

    public func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval
    ) throws -> ProcessResult {
        try runProcess(
            executable,
            arguments: arguments,
            environment: environment,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func runProcess(
        _ executable: String,
        arguments: [String],
        environment: [String: String],
        timeoutSeconds: TimeInterval?
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        if !environment.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        var timedOut = false
        if let timeoutSeconds {
            let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }

            if process.isRunning {
                timedOut = true
                process.terminate()

                let terminationDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }

                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }

        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        var stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if timedOut, let timeoutSeconds {
            if !stderrText.isEmpty && !stderrText.hasSuffix("\n") {
                stderrText.append("\n")
            }
            stderrText.append("command timed out after \(timeoutSeconds) seconds\n")
        }

        return ProcessResult(
            exitCode: timedOut ? 124 : process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText
        )
    }
}

public struct CommandError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public let exitCode: Int32

    public init(_ message: String, exitCode: Int32 = 1) {
        self.message = message
        self.exitCode = exitCode
    }

    public var description: String {
        message
    }
}
