import Foundation

public struct StorageConfig: Codable, Equatable, Sendable {
    public let root: String
    public let home: String
    public let xcodeRoot: String
    public let coreSimulatorRoot: String
    public let deviceStoreImage: String
    public let cacheImage: String
    public let deviceMount: String
    public let cacheMount: String
    public let derivedData: String
    public let packageCache: String
    public let tmp: String
    public let shimDirectory: String
    public let apfsDeviceVolumeName: String
    public let launchAgentLabel: String
    public let launchDaemonLabel: String
    public let cacheHelperPath: String
    public let userLaunchAgentPath: String
    public let systemLaunchDaemonPath: String

    public init(
        root: String,
        home: String = NSHomeDirectory(),
        shimDirectory: String? = nil,
        apfsDeviceVolumeName: String = "XcodeSimulatorDevicesAPFS"
    ) {
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let normalizedHome = URL(fileURLWithPath: home).standardizedFileURL.path
        let xcodeRoot = "\(normalizedRoot)/Xcode"

        self.root = normalizedRoot
        self.home = normalizedHome
        self.xcodeRoot = xcodeRoot
        self.coreSimulatorRoot = "\(xcodeRoot)/CoreSimulator"
        self.deviceStoreImage = "\(xcodeRoot)/CoreSimulator/DeviceSet.sparsebundle"
        self.cacheImage = "\(xcodeRoot)/CoreSimulator/Caches.sparsebundle"
        self.deviceMount = "\(normalizedHome)/Library/Developer/CoreSimulator/Devices"
        self.cacheMount = "/Library/Developer/CoreSimulator/Caches"
        self.derivedData = "\(xcodeRoot)/DerivedData"
        self.packageCache = "\(xcodeRoot)/PackageCache"
        self.tmp = "\(xcodeRoot)/tmp"
        self.shimDirectory = shimDirectory ?? "\(normalizedHome)/.local/bin"
        self.apfsDeviceVolumeName = apfsDeviceVolumeName
        self.launchAgentLabel = "io.github.rudironsoni.xcode-storage.device-store"
        self.launchDaemonLabel = "io.github.rudironsoni.xcode-storage.caches"
        self.cacheHelperPath = "/Library/PrivilegedHelperTools/io.github.rudironsoni.xcode-storage.mount-coresimulator-caches"
        self.userLaunchAgentPath = "\(normalizedHome)/Library/LaunchAgents/io.github.rudironsoni.xcode-storage.device-store.plist"
        self.systemLaunchDaemonPath = "/Library/LaunchDaemons/io.github.rudironsoni.xcode-storage.caches.plist"
    }

    public var xcrunShim: String {
        "\(shimDirectory)/xcrun"
    }

    public var simctlShim: String {
        "\(shimDirectory)/simctl"
    }

    public var xcodebuildShim: String {
        "\(shimDirectory)/xcodebuild"
    }

    public var supportDirectories: [String] {
        [
            xcodeRoot,
            coreSimulatorRoot,
            derivedData,
            packageCache,
            "\(xcodeRoot)/Archives",
            "\(xcodeRoot)/Products",
            "\(xcodeRoot)/Exports",
            "\(xcodeRoot)/Index.noindex",
            "\(xcodeRoot)/Logs",
            "\(xcodeRoot)/Results",
            tmp,
            "\(xcodeRoot)/XCFrameworks",
            URL(fileURLWithPath: deviceMount).deletingLastPathComponent().path
        ]
    }
}

public enum RootResolver {
    public static func resolveRoot(
        explicitRoot: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: CommandRunning = SystemCommandRunner()
    ) throws -> String {
        if let explicitRoot, !explicitRoot.isEmpty {
            return explicitRoot
        }

        if let root = environment["XCODE_STORAGE_ROOT"], !root.isEmpty {
            return root
        }

        let volumeUUID = environment["XCODE_STORAGE_VOLUME_UUID"]
        let volumeName = environment["XCODE_STORAGE_VOLUME_NAME"]

        if let volumeUUID,
           let result = try? runner.run("/usr/sbin/diskutil", arguments: ["info", volumeUUID], environment: [:]),
           result.succeeded,
           let mountPoint = TextParsers.volumeMountPoint(fromDiskutilInfo: result.stdout),
           !mountPoint.isEmpty {
            return mountPoint
        }

        if let volumeName, !volumeName.isEmpty {
            return "/Volumes/\(volumeName)"
        }

        throw CommandError("missing storage root. Pass --root PATH or set XCODE_STORAGE_ROOT.", exitCode: 78)
    }
}
