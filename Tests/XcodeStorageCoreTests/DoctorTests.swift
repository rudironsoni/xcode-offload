import Foundation
import Testing
@testable import XcodeStorageCore

@Test func doctorReportsMountedConfiguredSparsebundles() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createDoctorFixture(config: config)

    let runner = DoctorRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: """
            /dev/disk7s1 on \(config.deviceMount) (apfs, local, nodev, nosuid, journaled, nobrowse)
            /dev/disk11s1 on \(config.cacheMount) (apfs, local, nodev, nosuid, journaled, nobrowse)
            """,
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(
            exitCode: 0,
            stdout: """
            image-path      : \(config.deviceStoreImage)
            image-path      : \(config.cacheImage)
            """,
            stderr: ""
        )
    ])

    let report = Doctor(runner: runner).run(
        config: config,
        requireShims: false,
        validateSimctl: false
    )

    #expect(report.passed)
    #expect(report.checks.contains(DoctorCheck(.pass, "CoreSimulator Devices uses certified sparsebundle backend", detail: config.deviceStoreImage)))
    #expect(report.checks.contains { $0.status == .pass && $0.label == "CoreSimulator Caches is mounted" })
}

@Test func doctorFailsWhenCacheMountIsMissing() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createDoctorFixture(config: config)

    let runner = DoctorRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: "/dev/disk7s1 on \(config.deviceMount) (apfs, local)\n",
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(
            exitCode: 0,
            stdout: "image-path      : \(config.deviceStoreImage)\n",
            stderr: ""
        )
    ])

    let report = Doctor(runner: runner).run(
        config: config,
        requireShims: false,
        validateSimctl: false
    )

    #expect(!report.passed)
    #expect(report.checks.contains(DoctorCheck(.fail, "CoreSimulator Caches is not mounted at \(config.cacheMount)")))
}

@Test func doctorPropagatesSimctlFailureDetail() throws {
    let root = try temporaryDirectory()
    let home = try temporaryDirectory()
    let config = StorageConfig(root: root, home: home)
    try createDoctorFixture(config: config)

    let runner = DoctorRunner(results: [
        "/sbin/mount": ProcessResult(
            exitCode: 0,
            stdout: """
            /dev/disk7s1 on \(config.deviceMount) (apfs, local)
            /dev/disk11s1 on \(config.cacheMount) (apfs, local)
            """,
            stderr: ""
        ),
        "/usr/bin/hdiutil": ProcessResult(
            exitCode: 0,
            stdout: """
            image-path      : \(config.deviceStoreImage)
            image-path      : \(config.cacheImage)
            """,
            stderr: ""
        ),
        "/usr/bin/xcrun": ProcessResult(
            exitCode: 72,
            stdout: "",
            stderr: "simctl unavailable"
        )
    ])

    let report = Doctor(runner: runner).run(
        config: config,
        requireShims: false,
        validateSimctl: true
    )

    #expect(!report.passed)
    #expect(report.checks.contains(DoctorCheck(.fail, "simctl runtimes responds", detail: "simctl unavailable")))
    #expect(report.checks.contains(DoctorCheck(.fail, "simctl devices responds", detail: "simctl unavailable")))
}

private struct DoctorRunner: CommandRunning {
    let results: [String: ProcessResult]

    func run(
        _ executable: String,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult {
        results[executable] ?? ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private func createDoctorFixture(config: StorageConfig) throws {
    let directories = [
        config.xcodeRoot,
        config.coreSimulatorRoot,
        config.derivedData,
        config.packageCache,
        config.tmp,
        config.deviceStoreImage,
        config.cacheImage
    ]

    for directory in directories {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }
}

private func temporaryDirectory() throws -> String {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xcode-storage-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.path
}

