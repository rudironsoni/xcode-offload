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

        if isMounted(mountPoint) {
            return ["already mounted \(mountPoint.shellQuoted)"]
        }

        guard dryRun || fileManager.fileExists(atPath: imagePath) else {
            throw CommandError("missing sparsebundle: \(imagePath)", exitCode: 78)
        }

        var actions: [String] = []

        if kind == .caches {
            actions.append(contentsOf: try prepareCacheMountpoint(config: config, dryRun: dryRun))
        } else {
            let parent = URL(fileURLWithPath: mountPoint).deletingLastPathComponent().path
            actions.append("mkdir -p \(parent.shellQuoted)")
            if !dryRun {
                try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
        }

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

        actions.append(command.map(\.shellQuoted).joined(separator: " "))
        return actions
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
        try preflightSystemScope(scope: scope, dryRun: dryRun)

        let templates = LaunchdTemplates(config: config, toolPath: toolPath)
        var actions: [String] = []

        if scope == .user || scope == .all {
            let agentDirectory = URL(fileURLWithPath: config.userLaunchAgentPath).deletingLastPathComponent().path
            let logsDirectory = "\(config.home)/Library/Logs"
            actions.append("mkdir -p \(agentDirectory.shellQuoted) \(logsDirectory.shellQuoted)")
            actions.append("write \(config.userLaunchAgentPath.shellQuoted)")
            actions.append("chmod 0644 \(config.userLaunchAgentPath.shellQuoted)")

            if !dryRun {
                try validatePlist(templates.userAgentPlist, name: "user LaunchAgent")
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
            let helperDirectory = URL(fileURLWithPath: config.cacheHelperPath).deletingLastPathComponent().path
            let daemonDirectory = URL(fileURLWithPath: config.systemLaunchDaemonPath).deletingLastPathComponent().path
            actions.append("mkdir -p \(helperDirectory.shellQuoted) \(daemonDirectory.shellQuoted)")
            actions.append("write \(config.cacheHelperPath.shellQuoted)")
            actions.append("chown root:wheel \(config.cacheHelperPath.shellQuoted)")
            actions.append("chmod 0755 \(config.cacheHelperPath.shellQuoted)")
            actions.append("write \(config.systemLaunchDaemonPath.shellQuoted)")
            actions.append("chown root:wheel \(config.systemLaunchDaemonPath.shellQuoted)")
            actions.append("chmod 0644 \(config.systemLaunchDaemonPath.shellQuoted)")

            if !dryRun {
                try validatePlist(templates.systemDaemonPlist, name: "system LaunchDaemon")
                try fileManager.createDirectory(atPath: helperDirectory, withIntermediateDirectories: true)
                try fileManager.createDirectory(atPath: daemonDirectory, withIntermediateDirectories: true)
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
        try preflightSystemScope(scope: scope, dryRun: dryRun)

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

    private func preflightSystemScope(scope: LaunchdScope, dryRun: Bool) throws {
        guard !dryRun, scope == .system || scope == .all else {
            return
        }

        guard geteuid() == 0 else {
            throw CommandError("system launchd scope requires root. Re-run with sudo or use --scope user.", exitCode: 77)
        }
    }

    private func prepareCacheMountpoint(config: StorageConfig, dryRun: Bool) throws -> [String] {
        var actions = [
            "mkdir -p \(config.cacheMount.shellQuoted)",
            "chown root:wheel \(config.cacheMount.shellQuoted) || true",
            "chmod 0700 \(config.cacheMount.shellQuoted) || true"
        ]

        if isMounted(config.cacheMount) {
            return actions
        }

        if !dryRun {
            try fileManager.createDirectory(atPath: config.cacheMount, withIntermediateDirectories: true)
            _ = try? runner.run("/usr/sbin/chown", arguments: ["root:wheel", config.cacheMount], environment: [:])
            _ = try? runner.run("/bin/chmod", arguments: ["0700", config.cacheMount], environment: [:])
        }

        let contents = (try? fileManager.contentsOfDirectory(atPath: config.cacheMount)) ?? []
        let isNonEmpty = !contents.isEmpty

        if isNonEmpty {
            let backup = "/var/tmp/io.github.rudironsoni.xcode-offload.caches-backups/\(timestamp())/Caches"
            actions.append("mv \(config.cacheMount.shellQuoted) \(backup.shellQuoted)")
            actions.append("mkdir -p \(config.cacheMount.shellQuoted)")
            if !dryRun {
                try fileManager.createDirectory(atPath: URL(fileURLWithPath: backup).deletingLastPathComponent().path, withIntermediateDirectories: true)
                try fileManager.moveItem(atPath: config.cacheMount, toPath: backup)
                try fileManager.createDirectory(atPath: config.cacheMount, withIntermediateDirectories: true)
                _ = try? runner.run("/usr/sbin/chown", arguments: ["root:wheel", config.cacheMount], environment: [:])
                _ = try? runner.run("/bin/chmod", arguments: ["0700", config.cacheMount], environment: [:])
            }
        }

        return actions
    }

    private func isMounted(_ mountPoint: String) -> Bool {
        guard let result = try? runner.run("/sbin/mount", arguments: [], environment: [:]), result.succeeded else {
            return false
        }
        return TextParsers.mountLine(for: mountPoint, in: result.stdout) != nil
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
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

    private func validatePlist(_ plist: String, name: String) throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcode-offload-\(UUID().uuidString).plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)
        defer {
            try? fileManager.removeItem(at: url)
        }

        let result = try runner.run("/usr/bin/plutil", arguments: ["-lint", url.path], environment: [:])
        guard result.succeeded else {
            let detail = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw CommandError("\(name) plist validation failed: \(detail)")
        }
    }
}
