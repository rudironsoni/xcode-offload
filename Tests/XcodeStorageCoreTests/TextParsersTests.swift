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

@Test func mountLineHandlesSpacesAndPrefixCollisions() {
    let output = """
    /dev/disk1s1 on /Volumes/My Disk/DevicesBackup (apfs, local)
    /dev/disk2s1 on /Volumes/My Disk/Devices (apfs, local, nobrowse)
    """

    let line = TextParsers.mountLine(
        for: "/Volumes/My Disk/Devices",
        in: output
    )

    #expect(line == "/dev/disk2s1 on /Volumes/My Disk/Devices (apfs, local, nobrowse)")
}

@Test func diskutilParsersTrimValues() {
    let output = """
       Volume Name:              XcodeSimulatorDevicesAPFS
       Mount Point:              /Volumes/ExternalXcode
       File System Personality:  APFS
    """

    #expect(TextParsers.volumeName(fromDiskutilInfo: output) == "XcodeSimulatorDevicesAPFS")
    #expect(TextParsers.volumeMountPoint(fromDiskutilInfo: output) == "/Volumes/ExternalXcode")
    #expect(TextParsers.fileSystemPersonality(fromDiskutilInfo: output) == "APFS")
    #expect(TextParsers.isAPFS(fromDiskutilInfo: output))
}

@Test func diskutilParserReportsMissingValues() {
    let output = "   Device Identifier:        disk7s1\n"

    #expect(TextParsers.volumeName(fromDiskutilInfo: output) == nil)
    #expect(TextParsers.volumeMountPoint(fromDiskutilInfo: output) == nil)
    #expect(TextParsers.fileSystemPersonality(fromDiskutilInfo: output) == nil)
    #expect(!TextParsers.isAPFS(fromDiskutilInfo: output))
}

@Test func launchctlLastExitParserFindsStatus() {
    let output = """
    domain = system
    service = io.github.rudironsoni.xcode-storage.caches
    last exit code = 0
    """

    #expect(TextParsers.launchctlLastExitStatus(from: output) == 0)
}

@Test func launchctlLastExitParserFindsNonZeroStatus() {
    let output = """
    path = /Library/LaunchDaemons/io.github.rudironsoni.xcode-storage.caches.plist
    last exit status = -78
    """

    #expect(TextParsers.launchctlLastExitStatus(from: output) == -78)
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
    #expect("".shellQuoted == "''")
}
