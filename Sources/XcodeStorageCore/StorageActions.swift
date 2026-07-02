import Darwin
import Foundation

public enum MountKind: String, Sendable {
    case devices
    case caches
}

public struct StorageActions {
    private let runner: CommandRunning
    private let fileManager: FileManager

    public init(runner: CommandRunning = SystemCommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func initialize(config: StorageConfig, createImages: Bool, dryRun: Bool) throws -> [String] {
        var actions: [String] = []

        for directory in config.supportDirectories {
            actions.append("mkdir -p \(directory.shellQuoted)")
            if !dryRun {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            }
        }

        if createImages {
            if !fileManager.fileExists(atPath: config.deviceStoreImage) {
                let command = hdiutilCreateCommand(
                    imagePath: config.deviceStoreImage,
                    size: "900g",
                    volumeName: "XcodeSimulatorDevices"
                )
                actions.append(command.map(\.shellQuoted).joined(separator: " "))
                if !dryRun {
                    try runOrThrow(command)
                }
            }

            if !fileManager.fileExists(atPath: config.cacheImage) {
                let command = hdiutilCreateCommand(
                    imagePath: config.cacheImage,
                    size: "100g",
                    volumeName: "XcodeSimulatorCaches"
                )
                actions.append(command.map(\.shellQuoted).joined(separator: " "))
                if !dryRun {
                    try runOrThrow(command)
                }
            }
        }

        return actions
    }

    public func mount(_ kind: MountKind, config: StorageConfig, dryRun: Bool) throws -> [String] {
        let mountPoint = kind == .devices ? config.deviceMount : config.cacheMount
        let imagePath = kind == .devices ? config.deviceStoreImage : config.cacheImage

        guard fileManager.fileExists(atPath: imagePath) else {
            throw CommandError("missing sparsebundle: \(imagePath)", exitCode: 78)
        }

        try fileManager.createDirectory(
            atPath: URL(fileURLWithPath: mountPoint).deletingLastPathComponent().path,
            withIntermediateDirectories: true
        )

        let command = [
            "/usr/bin/hdiutil",
            "attach",
            imagePath,
            "-mountpoint",
            mountPoint,
            "-nobrowse",
            "-owners",
            "on"
        ]

        if !dryRun {
            try runOrThrow(command)
        }

        return [command.map(\.shellQuoted).joined(separator: " ")]
    }

    public func unmount(_ kind: MountKind, config: StorageConfig, dryRun: Bool) throws -> [String] {
        let mountPoint = kind == .devices ? config.deviceMount : config.cacheMount
        let command = ["/usr/bin/hdiutil", "detach", mountPoint]

        if !dryRun {
            try runOrThrow(command)
        }

        return [command.map(\.shellQuoted).joined(separator: " ")]
    }

    public func installShims(config: StorageConfig, toolPath: String, dryRun: Bool) throws -> [String] {
        let templates = ShimTemplates.renderAll(config: config, toolPath: toolPath)
        var actions = ["mkdir -p \(config.shimDirectory.shellQuoted)"]

        if !dryRun {
            try fileManager.createDirectory(atPath: config.shimDirectory, withIntermediateDirectories: true)
        }

        for template in templates {
            let path = "\(config.shimDirectory)/\(template.name)"
            actions.append("install shim \(path.shellQuoted)")
            if !dryRun {
                try template.body.write(toFile: path, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            }
        }

        return actions
    }

    public func installLaunchd(
        config: StorageConfig,
        toolPath: String,
        scope: LaunchdScope,
        load: Bool,
        dryRun: Bool
    ) throws -> [String] {
        let templates = LaunchdTemplates(config: config, toolPath: toolPath)
        var actions: [String] = []

        if scope == .user || scope == .all {
            let agentDirectory = URL(fileURLWithPath: config.userLaunchAgentPath).deletingLastPathComponent().path
            let logsDirectory = "\(config.home)/Library/Logs"
            actions.append("mkdir -p \(agentDirectory.shellQuoted) \(logsDirectory.shellQuoted)")
            actions.append("write \(config.userLaunchAgentPath.shellQuoted)")
            actions.append("chmod 0644 \(config.userLaunchAgentPath.shellQuoted)")

            if !dryRun {
                try fileManager.createDirectory(atPath: agentDirectory, withIntermediateDirectories: true)
                try fileManager.createDirectory(atPath: logsDirectory, withIntermediateDirectories: true)
                try templates.userAgentPlist.write(toFile: config.userLaunchAgentPath, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: config.userLaunchAgentPath)
            }

            if load {
                let uid = getuid()
                actions.append("launchctl bootout gui/\(uid) \(config.userLaunchAgentPath.shellQuoted) || true")
                actions.append("launchctl bootstrap gui/\(uid) \(config.userLaunchAgentPath.shellQuoted)")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "gui/\(uid)", config.userLaunchAgentPath], environment: [:])
                    try runOrThrow(["/bin/launchctl", "bootstrap", "gui/\(uid)", config.userLaunchAgentPath])
                }
            }
        }

        if scope == .system || scope == .all {
            actions.append("write \(config.cacheHelperPath.shellQuoted)")
            actions.append("chown root:wheel \(config.cacheHelperPath.shellQuoted)")
            actions.append("chmod 0755 \(config.cacheHelperPath.shellQuoted)")
            actions.append("write \(config.systemLaunchDaemonPath.shellQuoted)")
            actions.append("chown root:wheel \(config.systemLaunchDaemonPath.shellQuoted)")
            actions.append("chmod 0644 \(config.systemLaunchDaemonPath.shellQuoted)")

            if !dryRun {
                try templates.cacheMountHelper.write(toFile: config.cacheHelperPath, atomically: true, encoding: .utf8)
                try templates.systemDaemonPlist.write(toFile: config.systemLaunchDaemonPath, atomically: true, encoding: .utf8)
                try runOrThrow(["/usr/sbin/chown", "root:wheel", config.cacheHelperPath])
                try runOrThrow(["/bin/chmod", "0755", config.cacheHelperPath])
                try runOrThrow(["/usr/sbin/chown", "root:wheel", config.systemLaunchDaemonPath])
                try runOrThrow(["/bin/chmod", "0644", config.systemLaunchDaemonPath])
            }

            if load {
                actions.append("launchctl bootout system \(config.systemLaunchDaemonPath.shellQuoted) || true")
                actions.append("launchctl bootstrap system \(config.systemLaunchDaemonPath.shellQuoted)")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "system", config.systemLaunchDaemonPath], environment: [:])
                    try runOrThrow(["/bin/launchctl", "bootstrap", "system", config.systemLaunchDaemonPath])
                }
            }
        }

        return actions
    }

    public func uninstallLaunchd(
        config: StorageConfig,
        scope: LaunchdScope,
        unload: Bool,
        dryRun: Bool
    ) throws -> [String] {
        var actions: [String] = []

        if scope == .user || scope == .all {
            if unload {
                let uid = getuid()
                actions.append("launchctl bootout gui/\(uid) \(config.userLaunchAgentPath.shellQuoted) || true")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "gui/\(uid)", config.userLaunchAgentPath], environment: [:])
                }
            }

            actions.append("rm -f \(config.userLaunchAgentPath.shellQuoted)")
            if !dryRun {
                try? fileManager.removeItem(atPath: config.userLaunchAgentPath)
            }
        }

        if scope == .system || scope == .all {
            if unload {
                actions.append("launchctl bootout system \(config.systemLaunchDaemonPath.shellQuoted) || true")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "system", config.systemLaunchDaemonPath], environment: [:])
                }
            }

            actions.append("rm -f \(config.systemLaunchDaemonPath.shellQuoted)")
            actions.append("rm -f \(config.cacheHelperPath.shellQuoted)")
            if !dryRun {
                try? fileManager.removeItem(atPath: config.systemLaunchDaemonPath)
                try? fileManager.removeItem(atPath: config.cacheHelperPath)
            }
        }

        return actions
    }

    private func hdiutilCreateCommand(imagePath: String, size: String, volumeName: String) -> [String] {
        [
            "/usr/bin/hdiutil",
            "create",
            "-size",
            size,
            "-type",
            "SPARSEBUNDLE",
            "-fs",
            "APFS",
            "-volname",
            volumeName,
            imagePath
        ]
    }

    private func runOrThrow(_ command: [String]) throws {
        guard let executable = command.first else {
            throw CommandError("empty command")
        }

        let result = try runner.run(executable, arguments: Array(command.dropFirst()), environment: [:])
        guard result.succeeded else {
            let detail = [result.stderr, result.stdout]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            throw CommandError(detail.isEmpty ? "command failed: \(command.joined(separator: " "))" : detail)
        }
    }
}
