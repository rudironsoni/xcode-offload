import Foundation

public struct StorageConfig: Codable, Equatable, Sendable {
    public let root: String
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
    ) -> String {
        if let explicitRoot, !explicitRoot.isEmpty {
            return explicitRoot
        }

        if let override = environment["EXTERNAL_SSD_ROOT_OVERRIDE"], !override.isEmpty {
            return override
        }

        let volumeUUID = environment["EXTERNAL_SSD_VOLUME_UUID"] ?? "F0F5B9A5-419F-4937-A02F-7B08A3AB06AF"
        let volumeName = environment["EXTERNAL_SSD_VOLUME_NAME"] ?? "1TB"

        if let result = try? runner.run("/usr/sbin/diskutil", arguments: ["info", volumeUUID], environment: [:]),
           result.succeeded,
           let mountPoint = TextParsers.volumeMountPoint(fromDiskutilInfo: result.stdout),
           !mountPoint.isEmpty {
            return mountPoint
        }

        return "/Volumes/\(volumeName)"
    }
}
