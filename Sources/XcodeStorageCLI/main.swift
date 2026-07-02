import Foundation
import XcodeStorageCore

@main
enum Main {
    static func main() {
        do {
            try CLI().run(Array(CommandLine.arguments.dropFirst()))
        } catch let exit as ExitRequested {
            Foundation.exit(exit.code)
        } catch let error as CommandError {
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            Foundation.exit(error.exitCode)
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            Foundation.exit(1)
        }
    }
}

struct CLI {
    func run(_ rawArguments: [String]) throws {
        var arguments = Arguments(rawArguments)
        let command = arguments.popCommand() ?? "help"

        switch command {
        case "help", "-h", "--help":
            printHelp()
        case "version", "--version":
            print(Version.current.displayString)
        case "doctor":
            try doctor(arguments: &arguments)
        case "repair":
            try repair(arguments: &arguments)
        case "init":
            try initialize(arguments: &arguments)
        case "mount":
            try mount(arguments: &arguments)
        case "unmount":
            try unmount(arguments: &arguments)
        case "install-shims":
            try installShims(arguments: &arguments)
        case "install-launchd":
            try installLaunchd(arguments: &arguments)
        case "uninstall-launchd":
            try uninstallLaunchd(arguments: &arguments)
        case "sim":
            try sim(arguments: &arguments)
        case "wrap-xcrun":
            try wrapper(arguments: arguments.remaining, kind: .xcrun)
        case "wrap-simctl":
            try wrapper(arguments: arguments.remaining, kind: .simctl)
        case "wrap-xcodebuild":
            try wrapper(arguments: arguments.remaining, kind: .xcodebuild)
        default:
            throw CommandError("unknown command: \(command)\n\nRun xcode-storage help.", exitCode: 64)
        }
    }

    private func doctor(arguments: inout Arguments) throws {
        let config = try makeConfig(arguments: &arguments)
        let json = arguments.popFlag("--json")
        let requireShims = arguments.popFlag("--require-shims")
        let skipSimctl = arguments.popFlag("--skip-simctl")
        let strict = arguments.popFlag("--strict")
        try arguments.rejectUnknown()

        let report = Doctor().run(config: config, requireShims: requireShims, validateSimctl: !skipSimctl, strict: strict)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(report))
            print()
        } else {
            for check in report.checks {
                print(check.humanLine)
            }

            if report.passed {
                print("OK xcode external storage doctor passed")
            } else {
                FileHandle.standardError.write(Data("FAIL xcode external storage doctor found \(report.failureCount) issue(s)\n".utf8))
            }
        }

        if !report.passed {
            throw ExitRequested(code: 1)
        }
    }

    private func repair(arguments: inout Arguments) throws {
        let toolPath = arguments.popOption("--tool-path") ?? defaultToolPath()
        let explicitShimDir = arguments.popOption("--shim-dir")
        let dryRun = arguments.popFlag("--dry-run")
        let load = arguments.popFlag("--load")
        let installShims = arguments.popFlag("--install-shims")
        let config = try makeConfig(arguments: &arguments, explicitShimDir: explicitShimDir)
        try arguments.rejectUnknown()

        let actions = StorageActions()
        var plan: [String] = []
        plan.append(contentsOf: try actions.initialize(config: config, createImages: true, dryRun: dryRun))
        plan.append(contentsOf: try actions.mount(.devices, config: config, dryRun: dryRun))
        plan.append(contentsOf: try actions.mount(.caches, config: config, dryRun: dryRun))
        plan.append(contentsOf: try actions.installLaunchd(config: config, toolPath: toolPath, scope: .all, load: load, dryRun: dryRun))
        if installShims {
            plan.append(contentsOf: try actions.installShims(config: config, toolPath: toolPath, dryRun: dryRun))
        }

        plan.forEach { print($0) }
    }

    private func initialize(arguments: inout Arguments) throws {
        let config = try makeConfig(arguments: &arguments)
        let dryRun = arguments.popFlag("--dry-run")
        let createImages = !arguments.popFlag("--no-create-images")
        try arguments.rejectUnknown()

        let actions = try StorageActions().initialize(config: config, createImages: createImages, dryRun: dryRun)
        for action in actions {
            print(action)
        }
    }

    private func mount(arguments: inout Arguments) throws {
        let kind = try mountKind(arguments.popCommand())
        let config = try makeConfig(arguments: &arguments)
        let dryRun = arguments.popFlag("--dry-run")
        try arguments.rejectUnknown()

        let actions = try StorageActions().mount(kind, config: config, dryRun: dryRun)
        actions.forEach { print($0) }
    }

    private func unmount(arguments: inout Arguments) throws {
        let kind = try mountKind(arguments.popCommand())
        let config = try makeConfig(arguments: &arguments)
        let dryRun = arguments.popFlag("--dry-run")
        try arguments.rejectUnknown()

        let actions = try StorageActions().unmount(kind, config: config, dryRun: dryRun)
        actions.forEach { print($0) }
    }

    private func installShims(arguments: inout Arguments) throws {
        let toolPath = arguments.popOption("--tool-path") ?? defaultToolPath()
        let explicitShimDir = arguments.popOption("--shim-dir")
        let dryRun = arguments.popFlag("--dry-run")
        let config = try makeConfig(arguments: &arguments, explicitShimDir: explicitShimDir)
        try arguments.rejectUnknown()

        let actions = try StorageActions().installShims(config: config, toolPath: toolPath, dryRun: dryRun)
        actions.forEach { print($0) }
    }

    private func installLaunchd(arguments: inout Arguments) throws {
        let toolPath = arguments.popOption("--tool-path") ?? defaultToolPath()
        let scope = try launchdScope(arguments.popOption("--scope") ?? "all")
        let dryRun = arguments.popFlag("--dry-run")
        let load = arguments.popFlag("--load")
        let config = try makeConfig(arguments: &arguments)
        try arguments.rejectUnknown()

        let actions = try StorageActions().installLaunchd(
            config: config,
            toolPath: toolPath,
            scope: scope,
            load: load,
            dryRun: dryRun
        )
        actions.forEach { print($0) }
    }

    private func uninstallLaunchd(arguments: inout Arguments) throws {
        let scope = try launchdScope(arguments.popOption("--scope") ?? "all")
        let dryRun = arguments.popFlag("--dry-run")
        let unload = arguments.popFlag("--unload")
        let config = try makeConfig(arguments: &arguments)
        try arguments.rejectUnknown()

        let actions = try StorageActions().uninstallLaunchd(
            config: config,
            scope: scope,
            unload: unload,
            dryRun: dryRun
        )
        actions.forEach { print($0) }
    }

    private func sim(arguments: inout Arguments) throws {
        let subcommand = arguments.popCommand() ?? "help"
        let simulator = SimulatorActions()

        switch subcommand {
        case "runtimes":
            try arguments.rejectUnknown()
            print(try simulator.listRuntimes(), terminator: "")
        case "devices":
            let availableOnly = !arguments.popFlag("--all")
            try arguments.rejectUnknown()
            print(try simulator.listDevices(availableOnly: availableOnly), terminator: "")
        case "recreate":
            let name = try arguments.requireOption("--name")
            let deviceType = try arguments.requireOption("--device-type")
            let runtime = try arguments.requireOption("--runtime")
            let boot = arguments.popFlag("--boot")
            let timeout = Int(arguments.popOption("--boot-timeout") ?? "1800") ?? 1800
            try arguments.rejectUnknown()

            let actions = try simulator.recreate(
                name: name,
                deviceType: deviceType,
                runtime: runtime,
                boot: boot,
                bootTimeoutSeconds: timeout
            )
            actions.forEach { print($0) }
        default:
            throw CommandError("unknown sim command: \(subcommand)", exitCode: 64)
        }
    }

    private func wrapper(arguments: [String], kind: WrapperKind) throws {
        var mutable = Arguments(arguments)
        let config = try makeConfig(arguments: &mutable)
        let dryRun = ProcessInfo.processInfo.environment["XCODE_SHIM_DRY_RUN"] == "1"
        let runner = WrapperRunner()

        switch kind {
        case .xcrun:
            try runner.runXcrun(arguments: mutable.remaining, config: config)
        case .simctl:
            try runner.runSimctl(arguments: mutable.remaining, config: config)
        case .xcodebuild:
            try runner.runXcodebuild(arguments: mutable.remaining, config: config, dryRun: dryRun)
        }
    }

    private func mountKind(_ value: String?) throws -> MountKind {
        guard let value, let kind = MountKind(rawValue: value) else {
            throw CommandError("expected mount kind: devices or caches", exitCode: 64)
        }
        return kind
    }

    private func launchdScope(_ value: String) throws -> LaunchdScope {
        guard let scope = LaunchdScope(rawValue: value) else {
            throw CommandError("expected launchd scope: user, system, or all", exitCode: 64)
        }
        return scope
    }

    private func makeConfig(arguments: inout Arguments, explicitShimDir: String? = nil) throws -> StorageConfig {
        let explicitRoot = arguments.popOption("--root")
        let explicitHome = arguments.popOption("--home")
        let root = try RootResolver.resolveRoot(explicitRoot: explicitRoot)
        return StorageConfig(root: root, home: explicitHome ?? NSHomeDirectory(), shimDirectory: explicitShimDir)
    }

    private func defaultToolPath() -> String {
        if let executablePath = Bundle.main.executablePath {
            return executablePath
        }

        let argument = CommandLine.arguments[0]
        if argument.hasPrefix("/") {
            return argument
        }

        return "\(FileManager.default.currentDirectoryPath)/\(argument)"
    }

    private func printHelp() {
        print(
            """
            xcode-storage manages external Xcode and CoreSimulator storage.

            Usage:
              xcode-storage doctor [--root PATH] [--require-shims] [--skip-simctl] [--strict] [--json]
              xcode-storage repair [--root PATH] [--home PATH] [--tool-path PATH] [--shim-dir PATH] [--install-shims] [--load] [--dry-run]
              xcode-storage init [--root PATH] [--dry-run] [--no-create-images]
              xcode-storage mount devices|caches [--root PATH] [--dry-run]
              xcode-storage unmount devices|caches [--root PATH] [--dry-run]
              xcode-storage install-shims [--root PATH] [--shim-dir PATH] [--tool-path PATH] [--dry-run]
              xcode-storage install-launchd [--root PATH] [--home PATH] [--tool-path PATH] [--scope user|system|all] [--load] [--dry-run]
              xcode-storage uninstall-launchd [--root PATH] [--home PATH] [--scope user|system|all] [--unload] [--dry-run]
              xcode-storage sim runtimes
              xcode-storage sim devices [--all]
              xcode-storage sim recreate --name NAME --device-type TYPE --runtime RUNTIME [--boot] [--boot-timeout SECONDS]
            """
        )
    }
}

enum WrapperKind {
    case xcrun
    case simctl
    case xcodebuild
}

struct Arguments {
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    var remaining: [String] {
        values
    }

    mutating func popCommand() -> String? {
        guard !values.isEmpty else {
            return nil
        }
        return values.removeFirst()
    }

    mutating func popFlag(_ flag: String) -> Bool {
        guard let index = values.firstIndex(of: flag) else {
            return false
        }
        values.remove(at: index)
        return true
    }

    mutating func popOption(_ name: String) -> String? {
        if let index = values.firstIndex(of: name) {
            values.remove(at: index)
            guard index < values.count else {
                return nil
            }
            return values.remove(at: index)
        }

        let prefix = "\(name)="
        if let index = values.firstIndex(where: { $0.hasPrefix(prefix) }) {
            let value = String(values[index].dropFirst(prefix.count))
            values.remove(at: index)
            return value
        }

        return nil
    }

    mutating func requireOption(_ name: String) throws -> String {
        guard let value = popOption(name), !value.isEmpty else {
            throw CommandError("missing required option: \(name)", exitCode: 64)
        }
        return value
    }

    func rejectUnknown() throws {
        guard values.isEmpty else {
            throw CommandError("unknown argument(s): \(values.joined(separator: " "))", exitCode: 64)
        }
    }
}
