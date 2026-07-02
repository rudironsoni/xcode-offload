import Foundation

public struct NativeLaunchdTemplates {
    public let config: StorageConfig
    public let toolPath: String

    public init(config: StorageConfig, toolPath: String) {
        self.config = config
        self.toolPath = toolPath
    }

    public var userAgentPlist: String {
        plist(
            label: config.nativeUserLaunchAgentLabel,
            programArguments: [
                toolPath,
                "native",
                "repair",
                "--root",
                config.root,
                "--home",
                config.home,
                "--scope",
                "user"
            ],
            runAtLoad: true,
            startInterval: 60,
            stdout: "\(config.home)/Library/Logs/xcode-storage-native-user.log",
            stderr: "\(config.home)/Library/Logs/xcode-storage-native-user.err"
        )
    }

    public var systemDaemonPlist: String {
        plist(
            label: config.nativeSystemLaunchDaemonLabel,
            programArguments: [config.nativeSystemHelperPath],
            runAtLoad: true,
            startInterval: 60,
            stdout: "/var/log/xcode-storage-native-system.log",
            stderr: "/var/log/xcode-storage-native-system.err"
        )
    }

    public var systemHelper: String {
        let mounts = NativeMounts.system(config: config)
        let records = mounts.map { nativeMount in
            [
                nativeMount.id,
                nativeMount.imagePath,
                nativeMount.mountPoint,
                nativeMount.requiredMode,
                nativeMount.preparation.rawValue
            ].joined(separator: "|")
        }.joined(separator: "\n")

        return """
        #!/bin/zsh
        set -euo pipefail

        root=\(config.root.shellQuoted)
        backup_root=\(config.nativeBackupRoot.shellQuoted)
        records=\(records.shellQuoted)

        log() {
          echo "xcode-storage native system: $*" >&2
        }

        fail() {
          log "$*"
          exit 78
        }

        is_mounted() {
          /sbin/mount | /usr/bin/grep -F " on $1 " >/dev/null 2>&1
        }

        reject_symlink() {
          if [[ -L "$1" ]]; then
            fail "native mountpoint must not be a symlink: $1"
          fi
        }

        prepare_mountpoint() {
          local id="$1"
          local mountpoint="$2"
          local mode="$3"
          reject_symlink "$mountpoint"
          /bin/mkdir -p "$(/usr/bin/dirname "$mountpoint")"
          if [[ -e "$mountpoint" && ! -d "$mountpoint" ]]; then
            fail "native mountpoint is not a directory: $mountpoint"
          fi
          if [[ -d "$mountpoint" && "$(/bin/ls -A "$mountpoint" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')" != "0" ]]; then
            local backup="$backup_root/$(/bin/date +%Y%m%d-%H%M%S)/$id"
            /bin/mkdir -p "$(/usr/bin/dirname "$backup")"
            /bin/mv "$mountpoint" "$backup"
            printf 'id=%s\\nmountPoint=%s\\nbackup=%s\\n' "$id" "$mountpoint" "$backup" > "$backup.manifest"
          fi
          /bin/mkdir -p "$mountpoint"
          /usr/sbin/chown root:wheel "$mountpoint" 2>/dev/null || true
          /bin/chmod "$mode" "$mountpoint" 2>/dev/null || true
        }

        prepare_images_sparsebundle() {
          local image="$1"
          local tmp="/tmp/xcode-storage-images-$$"
          /bin/mkdir -p "$tmp"
          /usr/bin/hdiutil attach "$image" -mountpoint "$tmp" -nobrowse -owners on >/dev/null
          /bin/mkdir -p "$tmp/mnt"
          /bin/chmod 1777 "$tmp/mnt"
          /usr/bin/hdiutil detach "$tmp" >/dev/null
          /bin/rmdir "$tmp" 2>/dev/null || true
        }

        if [[ ! -d "$root" ]]; then
          log "external root is not available: $root"
          exit 0
        fi

        while IFS='|' read -r id image mountpoint mode preparation; do
          [[ -n "$id" ]] || continue
          [[ -e "$image" ]] || fail "missing sparsebundle: $image"
          if is_mounted "$mountpoint"; then
            continue
          fi
          if [[ "$preparation" == "coreSimulatorImages" ]]; then
            prepare_images_sparsebundle "$image"
          fi
          prepare_mountpoint "$id" "$mountpoint" "$mode"
          /usr/bin/hdiutil attach "$image" -mountpoint "$mountpoint" -nobrowse -owners on
        done <<< "$records"
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
