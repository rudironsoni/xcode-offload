import Foundation

public enum NativeMountScope: String, Codable, Sendable {
    case user
    case system
}

public enum NativeMountPreparation: String, Codable, Sendable {
    case standard
    case coreSimulatorImages
}

public struct NativeMount: Codable, Equatable, Sendable {
    public let id: String
    public let scope: NativeMountScope
    public let imagePath: String
    public let mountPoint: String
    public let volumeName: String
    public let defaultSize: String
    public let requiredOwner: String
    public let requiredMode: String
    public let preparation: NativeMountPreparation

    public init(
        id: String,
        scope: NativeMountScope,
        imagePath: String,
        mountPoint: String,
        volumeName: String,
        defaultSize: String,
        requiredOwner: String,
        requiredMode: String,
        preparation: NativeMountPreparation = .standard
    ) {
        self.id = id
        self.scope = scope
        self.imagePath = imagePath
        self.mountPoint = mountPoint
        self.volumeName = volumeName
        self.defaultSize = defaultSize
        self.requiredOwner = requiredOwner
        self.requiredMode = requiredMode
        self.preparation = preparation
    }
}

public enum NativeMounts {
    public static func all(config: StorageConfig) -> [NativeMount] {
        user(config: config) + system(config: config)
    }

    public static func matching(scope: LaunchdScope, config: StorageConfig) -> [NativeMount] {
        switch scope {
        case .user:
            return user(config: config)
        case .system:
            return system(config: config)
        case .all:
            return all(config: config)
        }
    }

    public static func user(config: StorageConfig) -> [NativeMount] {
        [
            NativeMount(
                id: "devices",
                scope: .user,
                imagePath: config.deviceStoreImage,
                mountPoint: config.deviceMount,
                volumeName: "XcodeSimulatorDevices",
                defaultSize: "900g",
                requiredOwner: "user",
                requiredMode: "0755"
            ),
            NativeMount(
                id: "derived-data",
                scope: .user,
                imagePath: config.nativeDerivedDataImage,
                mountPoint: config.nativeDerivedDataMount,
                volumeName: "XcodeDerivedData",
                defaultSize: "300g",
                requiredOwner: "user",
                requiredMode: "0755"
            ),
            NativeMount(
                id: "archives",
                scope: .user,
                imagePath: config.nativeArchivesImage,
                mountPoint: config.nativeArchivesMount,
                volumeName: "XcodeArchives",
                defaultSize: "200g",
                requiredOwner: "user",
                requiredMode: "0755"
            )
        ]
    }

    public static func system(config: StorageConfig) -> [NativeMount] {
        [
            NativeMount(
                id: "caches",
                scope: .system,
                imagePath: config.cacheImage,
                mountPoint: config.cacheMount,
                volumeName: "XcodeSimulatorCaches",
                defaultSize: "100g",
                requiredOwner: "root:wheel",
                requiredMode: "0755"
            ),
            NativeMount(
                id: "images",
                scope: .system,
                imagePath: config.nativeImagesImage,
                mountPoint: config.nativeImagesMount,
                volumeName: "XcodeSimulatorImages",
                defaultSize: "150g",
                requiredOwner: "root:wheel",
                requiredMode: "0755",
                preparation: .coreSimulatorImages
            ),
            NativeMount(
                id: "volumes",
                scope: .system,
                imagePath: config.nativeVolumesImage,
                mountPoint: config.nativeVolumesMount,
                volumeName: "XcodeSimulatorVolumes",
                defaultSize: "50g",
                requiredOwner: "root:wheel",
                requiredMode: "0755"
            )
        ]
    }
}
