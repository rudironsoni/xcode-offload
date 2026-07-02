import Foundation

public enum LaunchdScope: String, Sendable {
    case user
    case system
    case all
}

public struct LaunchdTemplates {
    public let config: StorageConfig
    public let toolPath: String

    public init(config: StorageConfig, toolPath: String) {
        self.config = config
        self.toolPath = toolPath
    }

    public var userAgentPlist: String {
        plist(
            label: config.launchAgentLabel,
            programArguments: [
                toolPath,
                "mount",
                "devices",
                "--root",
                config.root,
                "--home",
                config.home
            ],
            runAtLoad: true,
            startInterval: nil,
            stdout: "\(config.home)/Library/Logs/xcode-storage-device-store.log",
            stderr: "\(config.home)/Library/Logs/xcode-storage-device-store.err"
        )
    }

    public var systemDaemonPlist: String {
        plist(
            label: config.launchDaemonLabel,
            programArguments: [config.cacheHelperPath],
            runAtLoad: true,
            startInterval: 60,
            stdout: "/var/log/xcode-storage-coresimulator-caches.log",
            stderr: "/var/log/xcode-storage-coresimulator-caches.err"
        )
    }

    public var cacheMountHelper: String {
        """
        #!/bin/zsh
        set -euo pipefail

        root=\(config.root.shellQuoted)
        image="$root/Xcode/CoreSimulator/Caches.sparsebundle"
        mountpoint=\(config.cacheMount.shellQuoted)
        lockdir="/var/run/io.github.rudironsoni.xcode-storage.caches.lock"
        backup_root="/var/tmp/io.github.rudironsoni.xcode-storage.caches-backups"

        fail() {
          echo "xcode CoreSimulator cache mount: $*" >&2
          exit 78
        }

        is_mounted() {
          /sbin/mount | /usr/bin/grep -F " on $mountpoint " >/dev/null 2>&1
        }

        acquire_lock() {
          local i
          for i in {1..240}; do
            if /bin/mkdir "$lockdir" 2>/dev/null; then
              trap '/bin/rmdir "$lockdir" 2>/dev/null || true' EXIT INT TERM
              return 0
            fi
            if is_mounted; then
              exit 0
            fi
            /bin/sleep 0.25
          done
          fail "timed out waiting $lockdir"
        }

        [[ -d "$root" ]] || fail "external SSD is not mounted: $root"
        [[ -e "$image" ]] || fail "missing cache sparsebundle: $image"

        if is_mounted; then
          exit 0
        fi

        acquire_lock

        if is_mounted; then
          exit 0
        fi

        /bin/mkdir -p "$mountpoint"
        /usr/sbin/chown root:wheel "$mountpoint" 2>/dev/null || true
        /bin/chmod 0700 "$mountpoint" 2>/dev/null || true

        if [[ "$(/bin/ls -A "$mountpoint" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')" != "0" ]]; then
          backup_dir="$backup_root/$(/bin/date +%Y%m%d-%H%M%S)"
          /bin/mkdir -p "$backup_dir"
          /bin/mv "$mountpoint" "$backup_dir/Caches"
          /bin/mkdir -p "$mountpoint"
          /usr/sbin/chown root:wheel "$mountpoint" 2>/dev/null || true
          /bin/chmod 0700 "$mountpoint" 2>/dev/null || true
        fi

        /usr/bin/hdiutil attach "$image" -mountpoint "$mountpoint" -nobrowse -owners on
        """
    }

    private func plist(
        label: String,
        programArguments: [String],
        runAtLoad: Bool,
        startInterval: Int?,
        stdout: String,
        stderr: String
    ) -> String {
        let arguments = programArguments
            .map { "        <string>\($0.xmlEscaped)</string>" }
            .joined(separator: "\n")
        let interval = startInterval.map {
            """
                <key>StartInterval</key>
                <integer>\($0)</integer>
            """
        } ?? ""

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label.xmlEscaped)</string>
            <key>ProgramArguments</key>
            <array>
        \(arguments)
            </array>
            <key>RunAtLoad</key>
            \(runAtLoad ? "<true/>" : "<false/>")
        \(interval)
            <key>StandardOutPath</key>
            <string>\(stdout.xmlEscaped)</string>
            <key>StandardErrorPath</key>
            <string>\(stderr.xmlEscaped)</string>
        </dict>
        </plist>
        """
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
