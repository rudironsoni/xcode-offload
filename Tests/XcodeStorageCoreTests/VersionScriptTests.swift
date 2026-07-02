import Foundation
import Testing

@Test func versionScriptUsesCleanSemVerReleaseTag() throws {
    let output = try temporaryOutputPath()
    defer { try? FileManager.default.removeItem(atPath: output) }

    let version = try runVersionScript(output: output, environment: ["GITHUB_REF_NAME": "v1.2.3-beta.1+build.7"])

    #expect(version == "1.2.3-beta.1+build.7")
    #expect(try String(contentsOfFile: output, encoding: .utf8).contains("public static let version = \"1.2.3-beta.1+build.7\""))
}

@Test func versionScriptUsesDevelopmentBuildMetadataForInvalidTagLikeValues() throws {
    let output = try temporaryOutputPath()
    defer { try? FileManager.default.removeItem(atPath: output) }

    let version = try runVersionScript(output: output, environment: ["GITHUB_REF_NAME": "v1.2.3.not-semver"])

    #expect(version.wholeMatch(of: #/[0-9]+\.[0-9]+\.[0-9]+-dev\.[0-9]+\+[0-9a-f]+/#) != nil)
}

@Test func versionScriptCurrentCheckoutVersionIsSemVerCompatible() throws {
    let output = try temporaryOutputPath()
    defer { try? FileManager.default.removeItem(atPath: output) }

    let version = try runVersionScript(output: output, environment: [:])

    #expect(version.wholeMatch(of: #/[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?/#) != nil)
}

private func runVersionScript(output: String, environment: [String: String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["scripts/generate-version-source.sh", output]
    process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
    let outputText = String(data: outputData, encoding: .utf8) ?? ""
    let errorText = String(data: errorData, encoding: .utf8) ?? ""

    #expect(process.terminationStatus == 0, Comment(rawValue: errorText))
    return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func temporaryOutputPath() throws -> String {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("xcode-storage-version-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("GeneratedBuildMetadata.swift").path
}
