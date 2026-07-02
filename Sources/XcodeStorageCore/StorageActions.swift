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
