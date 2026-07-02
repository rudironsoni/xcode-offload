import Foundation

public enum TextParsers {
    public static func mountLine(for mountPoint: String, in mountOutput: String) -> String? {
        let expectedMountPaths = normalizedPathCandidates(for: mountPoint)
        return mountOutput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { line in
                guard let mountedPath = mountedPath(fromMountLine: line) else {
                    return false
                }
                return !expectedMountPaths.isDisjoint(with: normalizedPathCandidates(for: mountedPath))
            }
    }

    public static func volumeName(fromDiskutilInfo output: String) -> String? {
        value(forDiskutilKey: "Volume Name", in: output)
    }

    public static func volumeMountPoint(fromDiskutilInfo output: String) -> String? {
        value(forDiskutilKey: "Mount Point", in: output)
    }

    public static func fileSystemPersonality(fromDiskutilInfo output: String) -> String? {
        value(forDiskutilKey: "File System Personality", in: output)
            ?? value(forDiskutilKey: "Type (Bundle)", in: output)
            ?? value(forDiskutilKey: "File System", in: output)
    }

    public static func isAPFS(fromDiskutilInfo output: String) -> Bool {
        guard let value = fileSystemPersonality(fromDiskutilInfo: output) else {
            return false
        }
        return value.localizedCaseInsensitiveContains("apfs")
    }

    public static func launchctlLastExitStatus(from output: String) -> Int? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.localizedCaseInsensitiveContains("last exit") else {
                continue
            }

            let digits = trimmed.split(whereSeparator: { !$0.isNumber && $0 != "-" })
            if let last = digits.last, let value = Int(last) {
                return value
            }
        }

        return nil
    }

    public static func containsConnectionFailure(_ stderr: String) -> Bool {
        let patterns = [
            "Code=61",
            "Code=409",
            "Code=410",
            "connection interrupted",
            "connection invalid",
            "failed to connect",
            "Failed to connect",
            "Connection interrupted"
        ]
        return patterns.contains { stderr.localizedCaseInsensitiveContains($0) }
    }

    private static func value(forDiskutilKey key: String, in output: String) -> String? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let foundKey = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard foundKey == key else {
                continue
            }

            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private static func mountedPath(fromMountLine line: String) -> String? {
        guard let onRange = line.range(of: " on "),
              let optionsRange = line.range(of: " (", range: onRange.upperBound..<line.endIndex) else {
            return nil
        }
        return String(line[onRange.upperBound..<optionsRange.lowerBound])
    }

    private static func normalizedPathCandidates(for path: String) -> Set<String> {
        let standardized = (path as NSString).standardizingPath
        let resolved = (standardized as NSString).resolvingSymlinksInPath
        var candidates: Set<String> = [path, standardized, resolved]
        for candidate in candidates {
            if candidate == "/tmp" || candidate.hasPrefix("/tmp/") {
                candidates.insert("/private\(candidate)")
            } else if candidate == "/private/tmp" || candidate.hasPrefix("/private/tmp/") {
                candidates.insert(String(candidate.dropFirst("/private".count)))
            }
        }
        return candidates
    }
}

public extension String {
    var shellQuoted: String {
        if isEmpty {
            return "''"
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-")
        if unicodeScalars.allSatisfy({ allowed.contains($0) }) {
            return self
        }

        return "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
