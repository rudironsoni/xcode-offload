import Testing
@testable import XcodeStorageCore

@Test func userAgentPlistMountsDeviceStoreForConfiguredHome() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let plist = LaunchdTemplates(config: config, toolPath: "/opt/homebrew/bin/xcode-storage").userAgentPlist

    #expect(plist.contains("<string>io.github.rudironsoni.xcode-storage.device-store</string>"))
    #expect(plist.contains("<string>/opt/homebrew/bin/xcode-storage</string>"))
    #expect(plist.contains("<string>mount</string>"))
    #expect(plist.contains("<string>devices</string>"))
    #expect(plist.contains("<string>--root</string>"))
    #expect(plist.contains("<string>/Volumes/ExternalXcode</string>"))
    #expect(plist.contains("<string>--home</string>"))
    #expect(plist.contains("<string>/Users/rudi</string>"))
    #expect(plist.contains("<string>/Users/rudi/Library/Logs/xcode-storage-device-store.log</string>"))
}

@Test func systemDaemonPlistRunsPrivilegedCacheHelperAtInterval() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let plist = LaunchdTemplates(config: config, toolPath: "/opt/homebrew/bin/xcode-storage").systemDaemonPlist

    #expect(plist.contains("<string>io.github.rudironsoni.xcode-storage.caches</string>"))
    #expect(plist.contains("<string>/Library/PrivilegedHelperTools/io.github.rudironsoni.xcode-storage.mount-coresimulator-caches</string>"))
    #expect(plist.contains("<key>RunAtLoad</key>"))
    #expect(plist.contains("<true/>"))
    #expect(plist.contains("<key>StartInterval</key>"))
    #expect(plist.contains("<integer>60</integer>"))
    #expect(plist.contains("<string>/var/log/xcode-storage-coresimulator-caches.log</string>"))
}

@Test func cacheMountHelperBacksUpNonEmptyMountpointBeforeAttach() {
    let config = StorageConfig(root: "/Volumes/ExternalXcode", home: "/Users/rudi")
    let helper = LaunchdTemplates(config: config, toolPath: "/opt/homebrew/bin/xcode-storage").cacheMountHelper

    #expect(helper.contains("root=/Volumes/ExternalXcode"))
    #expect(helper.contains("Caches.sparsebundle"))
    #expect(helper.contains("/var/run/io.github.rudironsoni.xcode-storage.caches.lock"))
    #expect(helper.contains("/var/tmp/io.github.rudironsoni.xcode-storage.caches-backups"))
    #expect(helper.contains("/bin/mv \"$mountpoint\" \"$backup_dir/Caches\""))
    #expect(helper.contains("/usr/bin/hdiutil attach \"$image\" -mountpoint \"$mountpoint\" -nobrowse -owners on"))
}
