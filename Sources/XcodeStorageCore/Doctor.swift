import Foundation

public enum CheckStatus: String, Codable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"
}

public struct DoctorCheck: Codable, Equatable, Sendable {
    public let status: CheckStatus
    public let label: String
    public let detail: String?

    public init(_ status: CheckStatus, _ label: String, detail: String? = nil) {
        self.status = status
        self.label = label
        self.detail = detail
    }

    public var humanLine: String {
        if let detail, !detail.isEmpty {
            return "\(status.rawValue) \(label): \(detail)"
        }
        return "\(status.rawValue) \(label)"
    }
}

public struct DoctorReport: Codable, Equatable, Sendable {
    public let checks: [DoctorCheck]

    public var failureCount: Int {
        checks.filter { $0.status == .fail }.count
    }

    public var warningCount: Int {
        checks.filter { $0.status == .warn }.count
    }

    public var passed: Bool {
        failureCount == 0
    }

    public init(checks: [DoctorCheck]) {
        self.checks = checks
    }
}

public struct Doctor {
    private let runner: CommandRunning
    private let fileManager: FileManager

    public init(runner: CommandRunning = SystemCommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func run(
        config: StorageConfig,
        requireShims: Bool,
        validateSimctl: Bool
    ) -> DoctorReport {
        var checks: [DoctorCheck] = []

        checks.append(pathExists(config.root, label: "External SSD exists"))
        checks.append(pathExists(config.xcodeRoot, label: "External Xcode root exists"))
        checks.append(pathExists(config.derivedData, label: "DerivedData root exists"))
        checks.append(pathExists(config.packageCache, label: "Package cache root exists"))
        checks.append(pathExists(config.tmp, label: "External tmp root exists"))
        checks.append(tmpWritable(config.tmp))
        checks.append(contentsOf: deviceMountChecks(config: config))
        checks.append(cacheMountCheck(config: config))

        if requireShims {
            checks.append(executableExists(config.xcrunShim, label: "xcrun wrapper exists"))
            checks.append(executableExists(config.simctlShim, label: "simctl wrapper exists"))
            checks.append(executableExists(config.xcodebuildShim, label: "xcodebuild wrapper exists"))
        }

        if validateSimctl {
            checks.append(simctlCheck(arguments: ["list", "runtimes"], label: "simctl runtimes responds"))
            checks.append(simctlCheck(arguments: ["list", "devices", "available"], label: "simctl devices responds"))
        }

        return DoctorReport(checks: checks)
    }

    private func pathExists(_ path: String, label: String) -> DoctorCheck {
        if fileManager.fileExists(atPath: path) {
            return DoctorCheck(.pass, label, detail: path)
        }
        return DoctorCheck(.fail, label.replacingOccurrences(of: " exists", with: " missing"), detail: path)
    }

    private func executableExists(_ path: String, label: String) -> DoctorCheck {
        if fileManager.isExecutableFile(atPath: path) {
            return DoctorCheck(.pass, label, detail: path)
        }
        return DoctorCheck(.fail, label.replacingOccurrences(of: " exists", with: " missing"), detail: path)
    }

    private func tmpWritable(_ path: String) -> DoctorCheck {
        guard fileManager.isWritableFile(atPath: path) else {
            return DoctorCheck(.fail, "External tmp is not writable", detail: path)
        }

        let probe = "\(path)/doctor.\(UUID().uuidString)"
        do {
            try "ok".write(toFile: probe, atomically: true, encoding: .utf8)
            try? fileManager.removeItem(atPath: probe)
            return DoctorCheck(.pass, "External tmp is writable")
        } catch {
            return DoctorCheck(.fail, "External tmp mktemp failed", detail: error.localizedDescription)
        }
    }

    private func deviceMountChecks(config: StorageConfig) -> [DoctorCheck] {
        guard let mountOutput = try? runner.run("/sbin/mount", arguments: [], environment: [:]),
              mountOutput.succeeded else {
            return [DoctorCheck(.fail, "Could not inspect mounts")]
        }

        guard let mountLine = TextParsers.mountLine(for: config.deviceMount, in: mountOutput.stdout) else {
            return [DoctorCheck(.fail, "CoreSimulator Devices is not mounted at \(config.deviceMount)")]
        }

        var checks = [DoctorCheck(.pass, "CoreSimulator Devices is mounted", detail: mountLine)]

        let hdiutilInfo = (try? runner.run("/usr/bin/hdiutil", arguments: ["info"], environment: [:]))?.stdout ?? ""
        if hdiutilInfo.contains(config.deviceStoreImage) {
            checks.append(DoctorCheck(.pass, "CoreSimulator Devices uses certified sparsebundle backend", detail: config.deviceStoreImage))
            return checks
        }

        let diskutilInfo = (try? runner.run("/usr/sbin/diskutil", arguments: ["info", config.deviceMount], environment: [:]))?.stdout ?? ""
        if TextParsers.volumeName(fromDiskutilInfo: diskutilInfo) == config.apfsDeviceVolumeName {
            if mountLine.contains("noowners") {
                checks.append(DoctorCheck(.fail, "CoreSimulator Devices APFS volume is mounted noowners"))
            } else {
                checks.append(DoctorCheck(.warn, "CoreSimulator Devices uses experimental APFS volume", detail: config.apfsDeviceVolumeName))
            }
        } else {
            checks.append(DoctorCheck(.fail, "CoreSimulator Devices mount is not certified sparsebundle backend or experimental APFS volume"))
        }

        return checks
    }

    private func cacheMountCheck(config: StorageConfig) -> DoctorCheck {
        guard let mountOutput = try? runner.run("/sbin/mount", arguments: [], environment: [:]),
              mountOutput.succeeded else {
            return DoctorCheck(.fail, "Could not inspect mounts")
        }

        guard let mountLine = TextParsers.mountLine(for: config.cacheMount, in: mountOutput.stdout) else {
            return DoctorCheck(.fail, "CoreSimulator Caches is not mounted at \(config.cacheMount)")
        }

        return DoctorCheck(.pass, "CoreSimulator Caches is mounted", detail: mountLine)
    }

    private func simctlCheck(arguments: [String], label: String) -> DoctorCheck {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let environment = ["PATH": "\(NSHomeDirectory())/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(path)"]

        do {
            let result = try runner.run("/usr/bin/xcrun", arguments: ["simctl"] + arguments, environment: environment)
            if result.succeeded {
                return DoctorCheck(.pass, label)
            }

            let detail = [result.stderr, result.stdout].filter { !$0.isEmpty }.joined(separator: "\n")
            return DoctorCheck(.fail, label, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return DoctorCheck(.fail, label, detail: error.localizedDescription)
        }
    }
}
