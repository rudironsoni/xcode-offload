import Darwin
import Foundation

public struct MountStatusReport: Codable, Equatable, Sendable {
    public let checks: [DoctorCheck]

    public var passed: Bool {
        checks.allSatisfy { $0.status != .fail }
    }

    public var failureCount: Int {
        checks.filter { $0.status == .fail }.count
    }
}

public struct MountActions {
    private let runner: CommandRunning
    private let fileManager: FileManager

    public init(runner: CommandRunning = SystemCommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func install(config: StorageConfig, toolPath: String, scope: LaunchdScope, load: Bool, dryRun: Bool) throws -> [String] {
        try preflight(scope: scope, dryRun: dryRun)
        var actions: [String] = []
        let mounts = ManagedMounts.matching(scope: scope, config: config)
        actions.append(contentsOf: try createSparsebundles(mounts: mounts, dryRun: dryRun))
        actions.append(contentsOf: try mount(mounts: mounts, config: config, dryRun: dryRun))
        if includesSystemMounts(scope) {
            actions.append(contentsOf: try scanAndMountRuntimes(dryRun: dryRun))
        }
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
                actions.append("launchctl bootout gui/\(uid) \(config.mountUserLaunchAgentPath.shellQuoted) || true")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "gui/\(uid)", config.mountUserLaunchAgentPath], environment: [:])
                }
            }
            actions.append("rm -f \(config.mountUserLaunchAgentPath.shellQuoted)")
            if !dryRun {
                try? fileManager.removeItem(atPath: config.mountUserLaunchAgentPath)
            }
        }

        if scope == .system || scope == .all {
            if unload {
                actions.append("launchctl bootout system \(config.mountSystemLaunchDaemonPath.shellQuoted) || true")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "system", config.mountSystemLaunchDaemonPath], environment: [:])
                }
            }
            actions.append("rm -f \(config.mountSystemLaunchDaemonPath.shellQuoted)")
            actions.append("rm -f \(config.mountSystemHelperPath.shellQuoted)")
            if !dryRun {
                try? fileManager.removeItem(atPath: config.mountSystemLaunchDaemonPath)
                try? fileManager.removeItem(atPath: config.mountSystemHelperPath)
            }
        }

        for managedMount in ManagedMounts.matching(scope: scope, config: config) {
            actions.append(contentsOf: try unmount(managedMount: managedMount, dryRun: dryRun))
        }

        return actions
    }

    public func status(config: StorageConfig, scope: LaunchdScope) -> MountStatusReport {
        MountStatusReport(checks: mountChecks(config: config, scope: scope, includeLaunchd: true))
    }

    public func mountChecks(config: StorageConfig, scope: LaunchdScope, includeLaunchd: Bool) -> [DoctorCheck] {
        var checks: [DoctorCheck] = []
        let mounts = ManagedMounts.matching(scope: scope, config: config)
        let mountOutput = (try? runner.run("/sbin/mount", arguments: [], environment: [:]))?.stdout ?? ""
        let hdiutilOutput = (try? runner.run("/usr/bin/hdiutil", arguments: ["info"], environment: [:]))?.stdout ?? ""

        for managedMount in mounts {
            checks.append(symlinkCheck(managedMount))
            checks.append(imageCheck(managedMount))
            checks.append(mountCheck(managedMount, mountOutput: mountOutput))
            checks.append(apfsCheck(managedMount))
            checks.append(ownersCheck(managedMount))
            checks.append(backendCheck(managedMount, hdiutilOutput: hdiutilOutput))
        }

        if includeLaunchd {
            if scope == .user || scope == .all {
                checks.append(pathExists(config.mountUserLaunchAgentPath, label: "Mount user LaunchAgent exists"))
            }
            if scope == .system || scope == .all {
                checks.append(pathExists(config.mountSystemLaunchDaemonPath, label: "Mount system LaunchDaemon exists"))
                checks.append(executableExists(config.mountSystemHelperPath, label: "Mount system helper exists"))
            }
        }

        return checks
    }

    private func createSparsebundles(mounts: [ManagedMount], dryRun: Bool) throws -> [String] {
        var actions: [String] = []
        for managedMount in mounts {
            let parent = URL(fileURLWithPath: managedMount.imagePath).deletingLastPathComponent().path
            actions.append("mkdir -p \(parent.shellQuoted)")
            if !dryRun {
                try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: managedMount.imagePath) {
                let command = hdiutilCreateCommand(managedMount)
                actions.append(command.map(\.shellQuoted).joined(separator: " "))
                if !dryRun {
                    try runOrThrow(command)
                }
            }

            if managedMount.preparation == .coreSimulatorImages {
                actions.append(contentsOf: try prepareImagesSparsebundle(managedMount, dryRun: dryRun))
            }
        }
        return actions
    }

    private func mount(mounts: [ManagedMount], config: StorageConfig, dryRun: Bool) throws -> [String] {
        var actions: [String] = []
        for managedMount in mounts {
            actions.append(
                contentsOf: try mount(
                    managedMount: managedMount,
                    backupRoot: backupRoot(for: managedMount, config: config),
                    dryRun: dryRun
                )
            )
        }
        return actions
    }

    private func mount(managedMount: ManagedMount, backupRoot: String, dryRun: Bool) throws -> [String] {
        try rejectSymlink(managedMount.mountPoint)

        if isMounted(managedMount.mountPoint) {
            if isMountedFromConfiguredBackend(managedMount) {
                return ["already mounted \(managedMount.mountPoint.shellQuoted)"]
            }
            throw CommandError("mountpoint is already mounted from a different backend: \(managedMount.mountPoint)", exitCode: 78)
        }
        try rejectNestedMounts(under: managedMount.mountPoint)

        guard dryRun || fileManager.fileExists(atPath: managedMount.imagePath) else {
            throw CommandError("missing sparsebundle: \(managedMount.imagePath)", exitCode: 78)
        }

        var actions = try prepareMountpoint(managedMount, backupRoot: backupRoot, dryRun: dryRun)
        let command = [
            "/usr/bin/hdiutil",
            "attach",
            managedMount.imagePath,
            "-mountpoint",
            managedMount.mountPoint,
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

    private func unmount(managedMount: ManagedMount, dryRun: Bool) throws -> [String] {
        if !isMounted(managedMount.mountPoint) {
            return ["not mounted \(managedMount.mountPoint.shellQuoted)"]
        }

        if !isMountedFromConfiguredBackend(managedMount) {
            throw CommandError("refusing to detach mountpoint from a different backend: \(managedMount.mountPoint)", exitCode: 78)
        }

        let command = ["/usr/bin/hdiutil", "detach", managedMount.mountPoint]
        if !dryRun {
            try runOrThrow(command)
        }
        return [command.map(\.shellQuoted).joined(separator: " ")]
    }

    private func prepareMountpoint(_ managedMount: ManagedMount, backupRoot: String, dryRun: Bool) throws -> [String] {
        let parent = URL(fileURLWithPath: managedMount.mountPoint).deletingLastPathComponent().path
        var actions = ["mkdir -p \(parent.shellQuoted)"]
        if !dryRun {
            try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: managedMount.mountPoint) {
            let contents = (try? fileManager.contentsOfDirectory(atPath: managedMount.mountPoint)) ?? []
            if !contents.isEmpty {
                let backupDirectory = "\(backupRoot)/\(timestamp())/\(managedMount.id)"
                let manifest = "\(backupDirectory).manifest"
                actions.append("mkdir -p \(URL(fileURLWithPath: backupDirectory).deletingLastPathComponent().path.shellQuoted)")
                actions.append("write \(manifest.shellQuoted)")
                actions.append("mv \(managedMount.mountPoint.shellQuoted) \(backupDirectory.shellQuoted)")
                if !dryRun {
                    try fileManager.createDirectory(
                        atPath: URL(fileURLWithPath: backupDirectory).deletingLastPathComponent().path,
                        withIntermediateDirectories: true
                    )
                    let body = "id=\(managedMount.id)\nmountPoint=\(managedMount.mountPoint)\nbackup=\(backupDirectory)\n"
                    try body.write(toFile: manifest, atomically: true, encoding: .utf8)
                    try fileManager.moveItem(atPath: managedMount.mountPoint, toPath: backupDirectory)
                }
            }
        }

        actions.append("mkdir -p \(managedMount.mountPoint.shellQuoted)")
        if managedMount.requiredOwner == "root:wheel" {
            actions.append("chown root:wheel \(managedMount.mountPoint.shellQuoted) || true")
        }
        actions.append("chmod \(managedMount.requiredMode) \(managedMount.mountPoint.shellQuoted) || true")

        if !dryRun {
            try fileManager.createDirectory(atPath: managedMount.mountPoint, withIntermediateDirectories: true)
            if managedMount.requiredOwner == "root:wheel" {
                _ = try? runner.run("/usr/sbin/chown", arguments: ["root:wheel", managedMount.mountPoint], environment: [:])
            }
            _ = try? runner.run("/bin/chmod", arguments: [managedMount.requiredMode, managedMount.mountPoint], environment: [:])
        }

        return actions
    }

    private func prepareImagesSparsebundle(_ managedMount: ManagedMount, dryRun: Bool) throws -> [String] {
        let tempMount = "\(NSTemporaryDirectory())xcode-offload-images-\(UUID().uuidString)"
        let attach = ["/usr/bin/hdiutil", "attach", managedMount.imagePath, "-mountpoint", tempMount, "-nobrowse", "-owners", "on"]
        let detach = ["/usr/bin/hdiutil", "detach", tempMount]
        let actions = [
            "mkdir -p \(tempMount.shellQuoted)",
            attach.map(\.shellQuoted).joined(separator: " "),
            "mkdir -p \(tempMount.shellQuoted)/mnt",
            "chmod 1777 \(tempMount.shellQuoted)/mnt",
            detach.map(\.shellQuoted).joined(separator: " ")
        ]

        if isMounted(managedMount.mountPoint) {
            if !isMountedFromConfiguredBackend(managedMount) {
                throw CommandError("mountpoint is already mounted from a different backend: \(managedMount.mountPoint)", exitCode: 78)
            }
            return ["already prepared \(managedMount.mountPoint.shellQuoted)"]
        }

        if dryRun || !fileManager.fileExists(atPath: managedMount.imagePath) {
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
        let templates = MountLaunchdTemplates(config: config, toolPath: toolPath)
        var actions: [String] = []

        if scope == .user || scope == .all {
            let directory = URL(fileURLWithPath: config.mountUserLaunchAgentPath).deletingLastPathComponent().path
            actions.append("mkdir -p \(directory.shellQuoted)")
            actions.append("write \(config.mountUserLaunchAgentPath.shellQuoted)")
            actions.append("chmod 0644 \(config.mountUserLaunchAgentPath.shellQuoted)")
            if !dryRun {
                try validatePlist(templates.userAgentPlist, name: "mount user LaunchAgent")
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try templates.userAgentPlist.write(toFile: config.mountUserLaunchAgentPath, atomically: true, encoding: .utf8)
                try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: config.mountUserLaunchAgentPath)
            }

            if load {
                let uid = getuid()
                actions.append("launchctl bootout gui/\(uid) \(config.mountUserLaunchAgentPath.shellQuoted) || true")
                actions.append("launchctl bootstrap gui/\(uid) \(config.mountUserLaunchAgentPath.shellQuoted)")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "gui/\(uid)", config.mountUserLaunchAgentPath], environment: [:])
                    try runOrThrow(["/bin/launchctl", "bootstrap", "gui/\(uid)", config.mountUserLaunchAgentPath])
                }
            }
        }

        if scope == .system || scope == .all {
            let helperDirectory = URL(fileURLWithPath: config.mountSystemHelperPath).deletingLastPathComponent().path
            let daemonDirectory = URL(fileURLWithPath: config.mountSystemLaunchDaemonPath).deletingLastPathComponent().path
            actions.append("mkdir -p \(helperDirectory.shellQuoted) \(daemonDirectory.shellQuoted)")
            actions.append("write \(config.mountSystemHelperPath.shellQuoted)")
            actions.append("chown root:wheel \(config.mountSystemHelperPath.shellQuoted)")
            actions.append("chmod 0755 \(config.mountSystemHelperPath.shellQuoted)")
            actions.append("write \(config.mountSystemLaunchDaemonPath.shellQuoted)")
            actions.append("chown root:wheel \(config.mountSystemLaunchDaemonPath.shellQuoted)")
            actions.append("chmod 0644 \(config.mountSystemLaunchDaemonPath.shellQuoted)")
            if !dryRun {
                try validatePlist(templates.systemDaemonPlist, name: "mount system LaunchDaemon")
                try fileManager.createDirectory(atPath: helperDirectory, withIntermediateDirectories: true)
                try fileManager.createDirectory(atPath: daemonDirectory, withIntermediateDirectories: true)
                try templates.systemHelper.write(toFile: config.mountSystemHelperPath, atomically: true, encoding: .utf8)
                try templates.systemDaemonPlist.write(toFile: config.mountSystemLaunchDaemonPath, atomically: true, encoding: .utf8)
                try runOrThrow(["/usr/sbin/chown", "root:wheel", config.mountSystemHelperPath])
                try runOrThrow(["/bin/chmod", "0755", config.mountSystemHelperPath])
                try runOrThrow(["/usr/sbin/chown", "root:wheel", config.mountSystemLaunchDaemonPath])
                try runOrThrow(["/bin/chmod", "0644", config.mountSystemLaunchDaemonPath])
            }

            if load {
                actions.append("launchctl bootout system \(config.mountSystemLaunchDaemonPath.shellQuoted) || true")
                actions.append("launchctl bootstrap system \(config.mountSystemLaunchDaemonPath.shellQuoted)")
                if !dryRun {
                    _ = try? runner.run("/bin/launchctl", arguments: ["bootout", "system", config.mountSystemLaunchDaemonPath], environment: [:])
                    try runOrThrow(["/bin/launchctl", "bootstrap", "system", config.mountSystemLaunchDaemonPath])
                }
            }
        }

        return actions
    }

    private func symlinkCheck(_ managedMount: ManagedMount) -> DoctorCheck {
        if isSymlink(managedMount.mountPoint) {
            return DoctorCheck(.fail, "Mount \(managedMount.id) mountpoint is not a symlink", detail: managedMount.mountPoint)
        }
        return DoctorCheck(.pass, "Mount \(managedMount.id) mountpoint is not a symlink", detail: managedMount.mountPoint)
    }

    private func imageCheck(_ managedMount: ManagedMount) -> DoctorCheck {
        if fileManager.fileExists(atPath: managedMount.imagePath) {
            return DoctorCheck(.pass, "Mount \(managedMount.id) sparsebundle exists", detail: managedMount.imagePath)
        }
        return DoctorCheck(.fail, "Mount \(managedMount.id) sparsebundle missing", detail: managedMount.imagePath)
    }

    private func mountCheck(_ managedMount: ManagedMount, mountOutput: String) -> DoctorCheck {
        guard let mountLine = TextParsers.mountLine(for: managedMount.mountPoint, in: mountOutput) else {
            return DoctorCheck(.fail, "Mount \(managedMount.id) is mounted at \(managedMount.mountPoint)")
        }
        if mountLine.contains("noowners") {
            return DoctorCheck(.fail, "Mount \(managedMount.id) mount is owners-enabled", detail: mountLine)
        }
        return DoctorCheck(.pass, "Mount \(managedMount.id) is mounted at \(managedMount.mountPoint)", detail: mountLine)
    }

    private func apfsCheck(_ managedMount: ManagedMount) -> DoctorCheck {
        let result = try? runner.run("/usr/sbin/diskutil", arguments: ["info", managedMount.mountPoint], environment: [:])
        guard let result, result.succeeded, TextParsers.isAPFS(fromDiskutilInfo: result.stdout) else {
            return DoctorCheck(.fail, "Mount \(managedMount.id) filesystem is APFS", detail: managedMount.mountPoint)
        }
        return DoctorCheck(.pass, "Mount \(managedMount.id) filesystem is APFS")
    }

    private func ownersCheck(_ managedMount: ManagedMount) -> DoctorCheck {
        let result = try? runner.run("/usr/sbin/diskutil", arguments: ["info", managedMount.mountPoint], environment: [:])
        guard let result, result.succeeded else {
            return DoctorCheck(.fail, "Mount \(managedMount.id) owners are enabled", detail: managedMount.mountPoint)
        }
        if TextParsers.ownersEnabled(fromDiskutilInfo: result.stdout) == true {
            return DoctorCheck(.pass, "Mount \(managedMount.id) owners are enabled")
        }
        return DoctorCheck(.fail, "Mount \(managedMount.id) owners are enabled", detail: managedMount.mountPoint)
    }

    private func backendCheck(_ managedMount: ManagedMount, hdiutilOutput: String) -> DoctorCheck {
        if TextParsers.hdiutilInfoContains(imagePath: managedMount.imagePath, mountPoint: managedMount.mountPoint, in: hdiutilOutput) {
            return DoctorCheck(.pass, "Mount \(managedMount.id) uses configured sparsebundle", detail: managedMount.imagePath)
        }
        return DoctorCheck(.fail, "Mount \(managedMount.id) uses configured sparsebundle", detail: managedMount.imagePath)
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
            throw CommandError("mountpoint must not be a symlink: \(path)", exitCode: 78)
        }
    }

    private func rejectNestedMounts(under mountPoint: String) throws {
        guard let result = try? runner.run("/sbin/mount", arguments: [], environment: [:]), result.succeeded else {
            return
        }
        let nestedMounts = TextParsers.mountedPaths(under: mountPoint, in: result.stdout)
        guard !nestedMounts.isEmpty else {
            return
        }

        throw CommandError(
            """
            mountpoint contains active nested mounts: \(nestedMounts.joined(separator: ", "))
            Shut down simulators and detach those mounts before mounting \(mountPoint).
            """,
            exitCode: 78
        )
    }

    private func backupRoot(for managedMount: ManagedMount, config: StorageConfig) -> String {
        switch managedMount.scope {
        case .user:
            config.mountUserBackupRoot
        case .system:
            config.mountSystemBackupRoot
        }
    }

    private func includesSystemMounts(_ scope: LaunchdScope) -> Bool {
        scope == .system || scope == .all
    }

    private func scanAndMountRuntimes(dryRun: Bool) throws -> [String] {
        let command = ["/usr/bin/xcrun", "simctl", "runtime", "scan-and-mount"]
        if !dryRun {
            try runOrThrow(command)
        }
        return [command.map(\.shellQuoted).joined(separator: " ")]
    }

    private func isSymlink(_ path: String) -> Bool {
        (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
    }

    private func preflight(scope: LaunchdScope, dryRun: Bool) throws {
        guard !dryRun, scope == .system || scope == .all else {
            return
        }
        guard geteuid() == 0 else {
            throw CommandError("system mount scope requires root. Re-run with sudo or use --scope user.", exitCode: 77)
        }
    }

    private func hdiutilCreateCommand(_ managedMount: ManagedMount) -> [String] {
        [
            "/usr/bin/hdiutil",
            "create",
            "-size",
            managedMount.defaultSize,
            "-type",
            "SPARSEBUNDLE",
            "-fs",
            "APFS",
            "-volname",
            managedMount.volumeName,
            managedMount.imagePath
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
            .appendingPathComponent("xcode-offload-\(UUID().uuidString).plist")
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

    private func isMountedFromConfiguredBackend(_ managedMount: ManagedMount) -> Bool {
        guard let result = try? runner.run("/usr/bin/hdiutil", arguments: ["info"], environment: [:]), result.succeeded else {
            return false
        }
        return TextParsers.hdiutilInfoContains(
            imagePath: managedMount.imagePath,
            mountPoint: managedMount.mountPoint,
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
