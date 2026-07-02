import Testing
@testable import XcodeStorageCore

@Test func queryOnlyXcodebuildArgumentsAreNotRewritten() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode")

    #expect(XcodebuildArguments.rewrite(arguments: ["-version"], config: config) == ["-version"])
    #expect(XcodebuildArguments.rewrite(arguments: ["-list", "-project", "App.xcodeproj"], config: config) == ["-list", "-project", "App.xcodeproj"])
}

@Test func xcodebuildArgumentsRouteBuildProductsToExternalStorage() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode")

    let rewritten = XcodebuildArguments.rewrite(
        arguments: [
            "-project",
            "App.xcodeproj",
            "-derivedDataPath",
            "/tmp/old",
            "-clonedSourcePackagesDirPath",
            "/tmp/packages"
        ],
        config: config
    )

    #expect(rewritten.contains("-derivedDataPath"))
    #expect(rewritten.contains("/Volumes/ExternalXcode/Xcode/DerivedData"))
    #expect(rewritten.contains("-clonedSourcePackagesDirPath"))
    #expect(rewritten.contains("/Volumes/ExternalXcode/Xcode/PackageCache"))
    #expect(rewritten.contains("SYMROOT=/Volumes/ExternalXcode/Xcode/DerivedData/Build/Products"))
    #expect(rewritten.contains("OBJROOT=/Volumes/ExternalXcode/Xcode/DerivedData/Build/Intermediates.noindex"))
    #expect(rewritten.contains("-project"))
    #expect(rewritten.contains("App.xcodeproj"))
    #expect(!rewritten.contains("/tmp/old"))
    #expect(!rewritten.contains("/tmp/packages"))
}
