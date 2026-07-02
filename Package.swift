// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "xcode-storage",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "xcode-storage", targets: ["XcodeStorageCLI"]),
        .library(name: "XcodeStorageCore", targets: ["XcodeStorageCore"])
    ],
    targets: [
        .executableTarget(
            name: "XcodeStorageCLI",
            dependencies: ["XcodeStorageCore"]
        ),
        .target(
            name: "XcodeStorageCore"
        ),
        .testTarget(
            name: "XcodeStorageCoreTests",
            dependencies: ["XcodeStorageCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
