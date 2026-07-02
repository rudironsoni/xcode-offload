import Darwin
import Foundation

public struct NativeStatusReport: Codable, Equatable, Sendable {
    public let checks: [DoctorCheck]

    public var passed: Bool {
        checks.allSatisfy { $0.status != .fail }
    }

    public var failureCount: Int {
        checks.filter { $0.status == .fail }.count
    }
}

public struct NativeActions {
    private let runner: CommandRunning
    private let fileManager: FileManager

    public init(runner: CommandRunning = SystemCommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func install(config: StorageConfig, toolPath: String, scope: LaunchdScope, load: Bool, dryRun: Bool) throws -> [String] {
        try preflight(scope: scope, dryRun: dryRun)
        var actions: [String] = []
        let mounts = NativeMounts.matching(scope: scope, config: config)
        actions.append(contentsOf: try createSparsebundles(mounts: mounts, dryRun: dryRun))
        actions.append(contentsOf: try mount(mounts: mounts, config: config, dryRun: dryRun))
        actions.append(contentsOf: try installLaunchd(config: config, toolPath: toolPath, scope: scope, load: load, dryRun: dryRun))
        return actions
    }

    public func repair(config: StorageConfig, toolPath: String, scope: LaunchdScope, load: Bool, dryRun: Bool) throws -> [String] {
        try install(config: config, toolPath: toolPath, scope: scope, load: load, dryRun: dryRun)
    }

    public func uninstall(config: StorageConfig, scope: LaunchdScope, unload: Bool, dryRun: Bool) throws -> [String] {
        try preflight(scope: scope, dryRun: dryRun)
        var actions: [String] = []

        if scope == .user || scope == .all {
            if unload {
                let uid = getuid()
                actions.append("launchctl bootout gui/\(uid) \(config.nativeUserLaunchAgentPath.shellQuoted) || true")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "gui/\(uid)", config.nativeUserLaunchAgentPath], environment: [:])
                }
            }
            actions.append("rm -f \(config.nativeUserLaunchAgentPath.shellQuoted)")
            if !dryRun {
                try? fileManager.removeItem(atPath: config.nativeUserLaunchAgentPath)
            }
        }

        if scope == .system || scope == .all {
            if unload {
                actions.append("launchctl bootout system \(config.nativeSystemLaunchDaemonPath.shellQuoted) || true")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "system", config.nativeSystemLaunchDaemonPath], environment: [:])
                }
            }
            actions.append("rm -f \(config.nativeSystemLaunchDaemonPath.shellQuoted)")
            actions.append("rm -f \(config.nativeSystemHelperPath.shellQuoted)")
            if !dryRun {
                try? fileManager.removeItem(atPath: config.nativeSystemLaunchDaemonPath)
                try? fileManager.removeItem(atPath: config.nativeSystemHelperPath)
            }
        }

        for nativeMount in NativeMounts.matching(scope: scope, config: config) {
            actions.append(contentsOf: try unmount(nativeMount: nativeMount, dryRun: dryRun))
        }

        return actions
    }

    public func status(config: StorageConfig, scope: LaunchdScope) -> NativeStatusReport {
        NativeStatusReport(checks: nativeChecks(config: config, scope: scope, includeLaunchd: true))
    }

    public func nativeChecks(config: StorageConfig, scope: LaunchdScope, includeLaunchd: Bool) -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        let mounts = NativeMounts.matching(scope: scope, config: config)
        let mountOutput = (try? runner.run("/sbin/mount", arguments: [], environment: [:]))?.stdout ?? ""
        let hdiutilOutput = (try? runner.run("/usr/bin/hdiutil", arguments: ["info"], environment: [:]))?.stdout ?? ""

        for nativeMount in mounts {
            checks.append(symlinkCheck(nativeMount))
            checks.append(imageCheck(nativeMount))
            checks.append(mountCheck(nativeMount, mountOutput: mountOutput))
            checks.append(apfsCheck(nativeMount))
            checks.append(ownersCheck(nativeMount))
            checks.append(backendCheck(nativeMount, hdiutilOutput: hdiutilOutput))
        }

        if includeLaunchd {
            if scope == .user || scope == .all {
                checks.append(pathExists(config.nativeUserLaunchAgentPath, label: "Native user LaunchAgent exists"))
            }
            if scope == .system || scope == .all {
                checks.append(pathExists(config.nativeSystemLaunchDaemonPath, label: "Native system LaunchDaemon exists"))
                checks.append(executableExists(config.nativeSystemHelperPath, label: "Native system helper exists"))
            }
        }

        return checks
    }

    private func createSparsebundles(mounts: [NativeMount], dryRun: Bool) throws -> [String] {
        var actions: [String] = []
        for nativeMount in mounts {
            let parent = URL(fileURLWithPath: nativeMount.imagePath).deletingLastPathComponent().path
            actions.append("mkdir -p \(parent.shellQuoted)")
            if !dryRun {
                try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: nativeMount.imagePath) {
                let command = hdiutilCreateCommand(nativeMount)
                actions.append(command.map(\.shellQuoted).joined(separator: " "))
                if !dryRun {
                    try runOrThrow(command)
                }
            }

            if nativeMount.preparation == .coreSimulatorImages {
                actions.append(contentsOf: try prepareImagesSparsebundle(nativeMount, dryRun: dryRun))
            }
        }
        return actions
    }

    private func mount(mounts: [NativeMount], config: StorageConfig, dryRun: Bool) throws -> [String] {
        var actions: [String] = []
        for nativeMount in mounts {
            actions.append(contentsOf: try mount(nativeMount: nativeMount, backupRoot: config.nativeBackupRoot, dryRun: dryRun))
        }
        return actions
    }

    private func mount(nativeMount: NativeMount, backupRoot: String, dryRun: Bool) throws -> [String] {
        try rejectSymlink(nativeMount.mountPoint)

        if isMounted(nativeMount.mountPoint) {
            if dryRun || isMountedFromConfiguredBackend(nativeMount) {
                return ["already mounted \(nativeMount.mountPoint.shellQuoted)"]
            }
            throw CommandError("native mountpoint is already mounted from a different backend: \(nativeMount.mountPoint)", exitCode: 78)
        }

        guard dryRun || fileManager.fileExists(atPath: nativeMount.imagePath) else {
            throw CommandError("missing sparsebundle: \(nativeMount.imagePath)", exitCode: 78)
        }

        var actions = try prepareMountpoint(nativeMount, backupRoot: backupRoot, dryRun: dryRun)
        let command = [
            "/usr/bin/hdiutil",
            "attach",
            nativeMount.imagePath,
            "-mountpoint",
            nativeMount.mountPoint,
            "-nobrowse",
            "-owners",
            "on"
        ]
        actions.append(command.map(\.shellQuoted).joined(separator: " "))
        if !dryRun {
            try runOrThrow(command)
        }
        return actions
    }

    private func unmount(nativeMount: NativeMount, dryRun: Bool) throws -> [String] {
        if !isMounted(nativeMount.mountPoint) {
            return ["not mounted \(nativeMount.mountPoint.shellQuoted)"]
        }

        if !dryRun && !isMountedFromConfiguredBackend(nativeMount) {
            throw CommandError("refusing to detach native mountpoint from a different backend: \(nativeMount.mountPoint)", exitCode: 78)
        }

        let command = ["/usr/bin/hdiutil", "detach", nativeMount.mountPoint]
        if !dryRun {
            try runOrThrow(command)
        }
        return [command.map(\.shellQuoted).joined(separator: " ")]
    }

    private func prepareMountpoint(_ nativeMount: NativeMount, backupRoot: String, dryRun: Bool) throws -> [String] {
        let parent = URL(fileURLWithPath: nativeMount.mountPoint).deletingLastPathComponent().path
        var actions = ["mkdir -p \(parent.shellQuoted)"]
        if !dryRun {
            try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: nativeMount.mountPoint) {
            let contents = (try? fileManager.contentsOfDirectory(atPath: nativeMount.mountPoint)) ?? []
            if !contents.isEmpty {
                let backupDirectory = "\(backupRoot)/\(timestamp())/\(nativeMount.id)"
                let manifest = "\(backupDirectory).manifest"
                actions.append("mkdir -p \(URL(fileURLWithPath: backupDirectory).deletingLastPathComponent().path.shellQuoted)")
                actions.append("write \(manifest.shellQuoted)")
                actions.append("mv \(nativeMount.mountPoint.shellQuoted) \(backupDirectory.shellQuoted)")
                if !dryRun {
                    try fileManager.createDirectory(
                        atPath: URL(fileURLWithPath: backupDirectory).deletingLastPathComponent().path,
                        withIntermediateDirectories: true
                    )
                    let body = "id=\(nativeMount.id)\nmountPoint=\(nativeMount.mountPoint)\nbackup=\(backupDirectory)\n"
                    try body.write(toFile: manifest, atomically: true, encoding: .utf8)
                    try fileManager.moveItem(atPath: nativeMount.mountPoint, toPath: backupDirectory)
                }
            }
        }

        actions.append("mkdir -p \(nativeMount.mountPoint.shellQuoted)")
        if nativeMount.requiredOwner == "root:wheel" {
            actions.append("chown root:wheel \(nativeMount.mountPoint.shellQuoted) || true")
        }
        actions.append("chmod \(nativeMount.requiredMode) \(nativeMount.mountPoint.shellQuoted) || true")

        if !dryRun {
            try fileManager.createDirectory(atPath: nativeMount.mountPoint, withIntermediateDirectories: true)
            if nativeMount.requiredOwner == "root:wheel" {
                _ = try? runner.run("/usr/sbin/chown", arguments: ["root:wheel", nativeMount.mountPoint], environment: [:])
            }
            _ = try? runner.run("/bin/chmod", arguments: [nativeMount.requiredMode, nativeMount.mountPoint], environment: [:])
        }

        return actions
    }

    private func prepareImagesSparsebundle(_ nativeMount: NativeMount, dryRun: Bool) throws -> [String] {
        let tempMount = "\(NSTemporaryDirectory())xcode-storage-images-\(UUID().uuidString)"
        let attach = ["/usr/bin/hdiutil", "attach", nativeMount.imagePath, "-mountpoint", tempMount, "-nobrowse", "-owners", "on"]
        let detach = ["/usr/bin/hdiutil", "detach", tempMount]
        let actions = [
            "mkdir -p \(tempMount.shellQuoted)",
            attach.map(\.shellQuoted).joined(separator: " "),
            "mkdir -p \(tempMount.shellQuoted)/mnt",
            "chmod 1777 \(tempMount.shellQuoted)/mnt",
            detach.map(\.shellQuoted).joined(separator: " ")
        ]

        if isMounted(nativeMount.mountPoint) {
            return ["already prepared \(nativeMount.mountPoint.shellQuoted)"]
        }

        if dryRun || !fileManager.fileExists(atPath: nativeMount.imagePath) {
            return actions
        }

        try fileManager.createDirectory(atPath: tempMount, withIntermediateDirectories: true)
        var attached = false
        defer {
            if attached {
                try? runOrThrow(detach)
            }
            try? fileManager.removeItem(atPath: tempMount)
        }
        try runOrThrow(attach)
        attached = true
        try fileManager.createDirectory(atPath: "\(tempMount)/mnt", withIntermediateDirectories: true)
        try runOrThrow(["/bin/chmod", "1777", "\(tempMount)/mnt"])
        try runOrThrow(detach)
        attached = false
        return actions
    }

    private func installLaunchd(config: StorageConfig, toolPath: String, scope: LaunchdScope, load: Bool, dryRun: Bool) throws -> [String] {
        let templates = NativeLaunchdTemplates(config: config, toolPath: toolPath)
        var actions: [String] = []

        if scope == .user || scope == .all {
            let directory = URL(fileURLWithPath: config.nativeUserLaunchAgentPath).deletingLastPathComponent().path
            actions.append("mkdir -p \(directory.shellQuoted)")
            actions.append("write \(config.nativeUserLaunchAgentPath.shellQuoted)")
            actions.append("chmod 0644 \(config.nativeUserLaunchAgentPath.shellQuoted)")
            if !dryRun {
                try validatePlist(templates.userAgentPlist, name: "native user LaunchAgent")
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try templates.userAgentPlist.write(toFile: config.nativeUserLaunchAgentPath, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: config.nativeUserLaunchAgentPath)
            }

            if load {
                let uid = getuid()
                actions.append("launchctl bootout gui/\(uid) \(config.nativeUserLaunchAgentPath.shellQuoted) || true")
                actions.append("launchctl bootstrap gui/\(uid) \(config.nativeUserLaunchAgentPath.shellQuoted)")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "gui/\(uid)", config.nativeUserLaunchAgentPath], environment: [:])
                    try runOrThrow(["/bin/launchctl", "bootstrap", "gui/\(uid)", config.nativeUserLaunchAgentPath])
                }
            }
        }

        if scope == .system || scope == .all {
            let helperDirectory = URL(fileURLWithPath: config.nativeSystemHelperPath).deletingLastPathComponent().path
            let daemonDirectory = URL(fileURLWithPath: config.nativeSystemLaunchDaemonPath).deletingLastPathComponent().path
            actions.append("mkdir -p \(helperDirectory.shellQuoted) \(daemonDirectory.shellQuoted)")
            actions.append("write \(config.nativeSystemHelperPath.shellQuoted)")
            actions.append("chown root:wheel \(config.nativeSystemHelperPath.shellQuoted)")
            actions.append("chmod 0755 \(config.nativeSystemHelperPath.shellQuoted)")
            actions.append("write \(config.nativeSystemLaunchDaemonPath.shellQuoted)")
            actions.append("chown root:wheel \(config.nativeSystemLaunchDaemonPath.shellQuoted)")
            actions.append("chmod 0644 \(config.nativeSystemLaunchDaemonPath.shellQuoted)")
            if !dryRun {
                try validatePlist(templates.systemDaemonPlist, name: "native system LaunchDaemon")
                try fileManager.createDirectory(atPath: helperDirectory, withIntermediateDirectories: true)
                try fileManager.createDirectory(atPath: daemonDirectory, withIntermediateDirectories: true)
                try templates.systemHelper.write(toFile: config.nativeSystemHelperPath, atomically: true, encoding: .utf8)
                try templates.systemDaemonPlist.write(toFile: config.nativeSystemLaunchDaemonPath, atomically: true, encoding: .utf8)
                try runOrThrow(["/usr/sbin/chown", "root:wheel", config.nativeSystemHelperPath])
                try runOrThrow(["/bin/chmod", "0755", config.nativeSystemHelperPath])
                try runOrThrow(["/usr/sbin/chown", "root:wheel", config.nativeSystemLaunchDaemonPath])
                try runOrThrow(["/bin/chmod", "0644", config.nativeSystemLaunchDaemonPath])
            }

            if load {
                actions.append("launchctl bootout system \(config.nativeSystemLaunchDaemonPath.shellQuoted) || true")
                actions.append("launchctl bootstrap system \(config.nativeSystemLaunchDaemonPath.shellQuoted)")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "system", config.nativeSystemLaunchDaemonPath], environment: [:])
                    try runOrThrow(["/bin/launchctl", "bootstrap", "system", config.nativeSystemLaunchDaemonPath])
                }
            }
        }

        return actions
    }

    private func symlinkCheck(_ nativeMount: NativeMount) -> DoctorCheck {
        if isSymlink(nativeMount.mountPoint) {
            return DoctorCheck(.fail, "Native \(nativeMount.id) mountpoint is not a symlink", detail: nativeMount.mountPoint)
        }
        return DoctorCheck(.pass, "Native \(nativeMount.id) mountpoint is not a symlink", detail: nativeMount.mountPoint)
    }

    private func imageCheck(_ nativeMount: NativeMount) -> DoctorCheck {
        if fileManager.fileExists(atPath: nativeMount.imagePath) {
            return DoctorCheck(.pass, "Native \(nativeMount.id) sparsebundle exists", detail: nativeMount.imagePath)
        }
        return DoctorCheck(.fail, "Native \(nativeMount.id) sparsebundle missing", detail: nativeMount.imagePath)
    }

    private func mountCheck(_ nativeMount: NativeMount, mountOutput: String) -> DoctorCheck {
        guard let mountLine = TextParsers.mountLine(for: nativeMount.mountPoint, in: mountOutput) else {
            return DoctorCheck(.fail, "Native \(nativeMount.id) is mounted at \(nativeMount.mountPoint)")
        }
        if mountLine.contains("noowners") {
            return DoctorCheck(.fail, "Native \(nativeMount.id) mount is owners-enabled", detail: mountLine)
        }
        return DoctorCheck(.pass, "Native \(nativeMount.id) is mounted at \(nativeMount.mountPoint)", detail: mountLine)
    }

    private func apfsCheck(_ nativeMount: NativeMount) -> DoctorCheck {
        let result = try? runner.run("/usr/sbin/diskutil", arguments: ["info", nativeMount.mountPoint], environment: [:])
        guard let result, result.succeeded, TextParsers.isAPFS(fromDiskutilInfo: result.stdout) else {
            return DoctorCheck(.fail, "Native \(nativeMount.id) filesystem is APFS", detail: nativeMount.mountPoint)
        }
        return DoctorCheck(.pass, "Native \(nativeMount.id) filesystem is APFS")
    }

    private func ownersCheck(_ nativeMount: NativeMount) -> DoctorCheck {
        let result = try? runner.run("/usr/sbin/diskutil", arguments: ["info", nativeMount.mountPoint], environment: [:])
        guard let result, result.succeeded else {
            return DoctorCheck(.fail, "Native \(nativeMount.id) owners are enabled", detail: nativeMount.mountPoint)
        }
        if TextParsers.ownersEnabled(fromDiskutilInfo: result.stdout) == true {
            return DoctorCheck(.pass, "Native \(nativeMount.id) owners are enabled")
        }
        return DoctorCheck(.fail, "Native \(nativeMount.id) owners are enabled", detail: nativeMount.mountPoint)
    }

    private func backendCheck(_ nativeMount: NativeMount, hdiutilOutput: String) -> DoctorCheck {
        if TextParsers.hdiutilInfoContains(imagePath: nativeMount.imagePath, mountPoint: nativeMount.mountPoint, in: hdiutilOutput) {
            return DoctorCheck(.pass, "Native \(nativeMount.id) uses configured sparsebundle", detail: nativeMount.imagePath)
        }
        return DoctorCheck(.fail, "Native \(nativeMount.id) uses configured sparsebundle", detail: nativeMount.imagePath)
    }

    private func pathExists(_ path: String, label: String) -> DoctorCheck {
        fileManager.fileExists(atPath: path)
            ? DoctorCheck(.pass, label, detail: path)
            : DoctorCheck(.fail, label, detail: path)
    }

    private func executableExists(_ path: String, label: String) -> DoctorCheck {
        fileManager.isExecutableFile(atPath: path)
            ? DoctorCheck(.pass, label, detail: path)
            : DoctorCheck(.fail, label, detail: path)
    }

    private func rejectSymlink(_ path: String) throws {
        if isSymlink(path) {
            throw CommandError("native mountpoint must not be a symlink: \(path)", exitCode: 78)
        }
    }

    private func isSymlink(_ path: String) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private func preflight(scope: LaunchdScope, dryRun: Bool) throws {
        guard !dryRun, scope == .system || scope == .all else {
            return
        }
        guard geteuid() == 0 else {
            throw CommandError("system native scope requires root. Re-run with sudo or use --scope user.", exitCode: 77)
        }
    }

    private func hdiutilCreateCommand(_ nativeMount: NativeMount) -> [String] {
        [
            "/usr/bin/hdiutil",
            "create",
            "-size",
            nativeMount.defaultSize,
            "-type",
            "SPARSEBUNDLE",
            "-fs",
            "APFS",
            "-volname",
            nativeMount.volumeName,
            nativeMount.imagePath
        ]
    }

    private func runOrThrow(_ command: [String]) throws {
        guard let executable = command.first else {
            throw CommandError("empty command")
        }
        let result = try runner.run(executable, arguments: Array(command.dropFirst()), environment: [:])
        guard result.succeeded else {
            let detail = [result.stderr, result.stdout]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw CommandError(detail.isEmpty ? "command failed: \(command.joined(separator: " "))" : detail)
        }
    }

    private func validatePlist(_ plist: String, name: String) throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xcode-storage-\(UUID().uuidString).plist")
        try plist.write(to: url, atomically: true, encoding: .utf8)
        defer {
            try? fileManager.removeItem(at: url)
        }
        let result = try runner.run("/usr/bin/plutil", arguments: ["-lint", url.path], environment: [:])
        guard result.succeeded else {
            throw CommandError("\(name) plist validation failed")
        }
    }

    private func isMounted(_ mountPoint: String) -> Bool {
        guard let result = try? runner.run("/sbin/mount", arguments: [], environment: [:]), result.succeeded else {
            return false
        }
        return TextParsers.mountLine(for: mountPoint, in: result.stdout) != nil
    }

    private func isMountedFromConfiguredBackend(_ nativeMount: NativeMount) -> Bool {
        guard let result = try? runner.run("/usr/bin/hdiutil", arguments: ["info"], environment: [:]), result.succeeded else {
            return false
        }
        return TextParsers.hdiutilInfoContains(
            imagePath: nativeMount.imagePath,
            mountPoint: nativeMount.mountPoint,
            in: result.stdout
        )
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
