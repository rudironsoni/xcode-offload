import Testing
@testable import XcodeStorageCore

@Test func generatedShimsPassConfiguredRootAndHome() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let shims = ShimTemplates.renderAll(config: config, toolPath: "/opt/homebrew/bin/xcode-storage")

    for shim in shims {
        #expect(shim.body.contains("--root /Volumes/ExternalXcode"))
        #expect(shim.body.contains("--home /Users/rudi"))
        #expect(shim.body.contains("/opt/homebrew/bin/xcode-storage"))
    }
}
