import Darwin
import Foundation

public enum NativeCertificationMode: String, Codable, Sendable {
    case user
    case system
    case e2e
}

public struct NativeCertificationOptions: Sendable {
    public let mode: NativeCertificationMode
    public let certRoot: String
    public let home: String
    public let toolPath: String
    public let runtime: String?
    public let deviceType: String?
    public let keepArtifacts: Bool
    public let allowSystem: Bool
    public let allowSimDelete: Bool
    public let bootTimeoutSeconds: Int

    public init(
        mode: NativeCertificationMode,
        certRoot: String,
        home: String,
        toolPath: String,
        runtime: String? = nil,
        deviceType: String? = nil,
        keepArtifacts: Bool = false,
        allowSystem: Bool = false,
        allowSimDelete: Bool = false,
        bootTimeoutSeconds: Int = 1800
    ) {
        self.mode = mode
        self.certRoot = certRoot
        self.home = home
        self.toolPath = toolPath
        self.runtime = runtime
        self.deviceType = deviceType
        self.keepArtifacts = keepArtifacts
        self.allowSystem = allowSystem
        self.allowSimDelete = allowSimDelete
        self.bootTimeoutSeconds = bootTimeoutSeconds
    }
}

public struct NativeCertification {
    private let runner: CommandRunning
    private let fileManager: FileManager

    public init(runner: CommandRunning = SystemCommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func run(options: NativeCertificationOptions, event: (String) -> Void) throws {
        let certRoot = try validatedCertRoot(options.certRoot)
        let runID = timestampWithPID()
        let root = "\(certRoot)/xcode-storage-cert-\(runID)"
        var cleanupCommands: [[String]] = []
        var primaryError: Error?

        try fileManager.createDirectory(atPath: root, withIntermediateDirectories: true)

        event("==> certification mode: \(options.mode.rawValue)")
        event("==> certification root: \(root)")

        do {
            switch options.mode {
            case .user:
                let home = "\(root)/home"
                try runTool(["native", "install", "--root", root, "--home", home, "--scope", "user", "--dry-run"], toolPath: options.toolPath, event: event)
                cleanupCommands.append(["native", "uninstall", "--root", root, "--home", home, "--scope", "user"])
                try runTool(["native", "install", "--root", root, "--home", home, "--scope", "user"], toolPath: options.toolPath, event: event)
                try runTool(["native", "status", "--root", root, "--home", home, "--scope", "user", "--json"], toolPath: options.toolPath, event: event)
                try runTool(cleanupCommands.removeLast(), toolPath: options.toolPath, event: event)

            case .system:
                guard options.allowSystem else {
                    throw CommandError("system certification requires --allow-system or XCODE_STORAGE_CERT_ALLOW_SYSTEM=1", exitCode: 77)
                }
                guard geteuid() == 0 else {
                    throw CommandError("system certification requires root", exitCode: 77)
                }
                try runTool(["native", "install", "--root", root, "--home", options.home, "--scope", "system", "--dry-run"], toolPath: options.toolPath, event: event)
                cleanupCommands.append(["native", "uninstall", "--root", root, "--home", options.home, "--scope", "system", "--unload"])
                try runTool(["native", "install", "--root", root, "--home", options.home, "--scope", "system", "--load"], toolPath: options.toolPath, event: event)
                try runTool(["native", "status", "--root", root, "--home", options.home, "--scope", "system", "--json"], toolPath: options.toolPath, event: event)
                try runTool(cleanupCommands.removeLast(), toolPath: options.toolPath, event: event)

            case .e2e:
                guard options.allowSimDelete else {
                    throw CommandError("e2e certification requires --allow-sim-delete or XCODE_STORAGE_CERT_ALLOW_SIM_DELETE=1", exitCode: 77)
                }
                cleanupCommands.append(["native", "uninstall", "--root", root, "--home", options.home, "--scope", "user", "--unload"])
                try runTool(["native", "install", "--root", root, "--home", options.home, "--scope", "user", "--load"], toolPath: options.toolPath, event: event)
                try runCommand("/usr/bin/xcrun", ["simctl", "list", "runtimes"], environment: defaultAppleToolEnvironment, event: event)
                try runCommand("/usr/bin/xcrun", ["simctl", "list", "devices", "available"], environment: defaultAppleToolEnvironment, event: event)
                try runCommand("/usr/bin/xcodebuild", ["-version"], environment: defaultAppleToolEnvironment, event: event)
                if let runtime = options.runtime, !runtime.isEmpty,
                   let deviceType = options.deviceType, !deviceType.isEmpty {
                    let name = "xcode-storage-cert-\(runID)"
                    try runTool([
                        "sim", "recreate",
                        "--name", name,
                        "--device-type", deviceType,
                        "--runtime", runtime,
                        "--boot",
                        "--boot-timeout", "\(options.bootTimeoutSeconds)"
                    ], toolPath: options.toolPath, event: event)
                    try runCommand("/usr/bin/xcrun", ["simctl", "delete", name], environment: defaultAppleToolEnvironment, event: event)
                }
                try runTool(cleanupCommands.removeLast(), toolPath: options.toolPath, event: event)
            }
        } catch {
            primaryError = error
        }

        for command in cleanupCommands.reversed() {
            try? runTool(command, toolPath: options.toolPath, event: event)
        }

        if options.keepArtifacts {
            event("==> keeping certification artifacts at \(root)")
        } else {
            event("==> cleaning certification artifacts at \(root)")
            do {
                try fileManager.removeItem(atPath: root)
            } catch where primaryError == nil {
                primaryError = error
            } catch {
                event("cleanup warning: \(error.localizedDescription)")
            }
        }

        if let primaryError {
            throw primaryError
        }

        event("==> native certification passed")
    }

    private var defaultAppleToolEnvironment: [String: String] {
        ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    }

    private func runTool(_ arguments: [String], toolPath: String, event: (String) -> Void) throws {
        try runCommand(toolPath, arguments, environment: [:], event: event)
    }

    private func runCommand(_ executable: String, _ arguments: [String], environment: [String: String], event: (String) -> Void) throws {
        event("==> \(([executable] + arguments).map(\.shellQuoted).joined(separator: " "))")
        let result = try runner.run(executable, arguments: arguments, environment: environment)
        emit(result.stdout, event: event)
        emit(result.stderr, event: event)
        guard result.succeeded else {
            let detail = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw CommandError(detail.isEmpty ? "certification command failed: \(executable)" : detail, exitCode: result.exitCode)
        }
    }

    private func emit(_ output: String, event: (String) -> Void) {
        guard !output.isEmpty else {
            return
        }
        output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).forEach(event)
    }

    private func validatedCertRoot(_ path: String) throws -> String {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let unsafe = ["/", "/Users", "/System", "/Library", "/Volumes"]
        guard !unsafe.contains(normalized) else {
            throw CommandError("refusing unsafe certification root: \(normalized)", exitCode: 78)
        }
        return normalized
    }

    private func timestampWithPID() -> String {
        "\(timestamp())-\(getpid())"
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
