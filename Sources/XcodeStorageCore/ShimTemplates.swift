import Foundation

public struct ShimTemplate: Equatable, Sendable {
    public let name: String
    public let body: String
}

public enum ShimTemplates {
    public static func renderAll(config: StorageConfig, toolPath: String) -> [ShimTemplate] {
        [
            ShimTemplate(name: "xcrun", body: xcrun(toolPath: toolPath)),
            ShimTemplate(name: "simctl", body: simctl(toolPath: toolPath)),
            ShimTemplate(name: "xcodebuild", body: xcodebuild(toolPath: toolPath))
        ]
    }

    public static func xcrun(toolPath: String) -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        if [ "${1:-}" = "simctl" ]; then
          shift
          exec \(toolPath.shellQuoted) wrap-simctl "$@"
        fi

        exec \(toolPath.shellQuoted) wrap-xcrun "$@"
        """
    }

    public static func simctl(toolPath: String) -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        exec \(toolPath.shellQuoted) wrap-simctl "$@"
        """
    }

    public static func xcodebuild(toolPath: String) -> String {
        """
        #!/bin/zsh
        set -euo pipefail

        exec \(toolPath.shellQuoted) wrap-xcodebuild "$@"
        """
    }
}
