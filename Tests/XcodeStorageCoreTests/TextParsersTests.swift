import Testing
@testable import XcodeStorageCore

@Test func mountLineFindsExactMountPoint() {
    let output = """
    /dev/disk7s1 on /Users/rudi/Library/Developer/CoreSimulator/Devices (apfs, local, nodev, nosuid, journaled, nobrowse)
    /dev/disk11s1 on /Library/Developer/CoreSimulator/Caches (apfs, local, nodev, nosuid, journaled, nobrowse)
    """

    let line = TextParsers.mountLine(
        for: "/Library/Developer/CoreSimulator/Caches",
        in: output
    )

    #expect(line == "/dev/disk11s1 on /Library/Developer/CoreSimulator/Caches (apfs, local, nodev, nosuid, journaled, nobrowse)")
}

@Test func diskutilParsersTrimValues() {
    let output = """
       Volume Name:              XcodeSimulatorDevicesAPFS
       Mount Point:              /Volumes/ExternalXcode
    """

    #expect(TextParsers.volumeName(fromDiskutilInfo: output) == "XcodeSimulatorDevicesAPFS")
    #expect(TextParsers.volumeMountPoint(fromDiskutilInfo: output) == "/Volumes/ExternalXcode")
}

@Test func connectionFailureParserMatchesCoreSimulatorErrors() {
    #expect(TextParsers.containsConnectionFailure("The connection was interrupted. Code=409"))
    #expect(TextParsers.containsConnectionFailure("Failed to connect to CoreSimulatorService"))
    #expect(!TextParsers.containsConnectionFailure("invalid device type"))
}

@Test func shellQuoteOnlyQuotesWhenNeeded() {
    #expect("/Volumes/ExternalXcode/Xcode".shellQuoted == "/Volumes/ExternalXcode/Xcode")
    #expect("/Volumes/My Disk/Xcode".shellQuoted == "'/Volumes/My Disk/Xcode'")
    #expect("Rudi's Disk".shellQuoted == "'Rudi'\\''s Disk'")
}
