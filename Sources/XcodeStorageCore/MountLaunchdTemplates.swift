import Foundation

public struct MountLaunchdTemplates {
    public let config: StorageConfig
    public let toolPath: String

    public init(config: StorageConfig, toolPath: String) {
        self.config = config
        self.toolPath = toolPath
    }

    public var userAgentPlist: String {
        plist(
            label: config.mountUserLaunchAgentLabel,
            programArguments: [
                toolPath,
                "mounts",
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
            stdout: "\(config.home)/Library/Logs/xcode-storage-mounts-user.log",
            stderr: "\(config.home)/Library/Logs/xcode-storage-mounts-user.err"
        )
    }

    public var systemDaemonPlist: String {
        plist(
            label: config.mountSystemLaunchDaemonLabel,
            programArguments: [config.mountSystemHelperPath],
            runAtLoad: true,
            startInterval: 60,
            stdout: "/var/log/xcode-storage-mounts-system.log",
            stderr: "/var/log/xcode-storage-mounts-system.err"
        )
    }

    public var systemHelper: String {
        let mounts = ManagedMounts.system(config: config)
        let ids = mounts.map(\.id).map(\.shellQuoted).joined(separator: " ")
        let images = mounts.map(\.imagePath).map(\.shellQuoted).joined(separator: " ")
        let mountpoints = mounts.map(\.mountPoint).map(\.shellQuoted).joined(separator: " ")
        let modes = mounts.map(\.requiredMode).map(\.shellQuoted).joined(separator: " ")
        let preparations = mounts.map(\.preparation.rawValue).map(\.shellQuoted).joined(separator: " ")

        return """
        #!/bin/zsh
        set -euo pipefail

        root=\(config.root.shellQuoted)
        backup_root=\(config.mountSystemBackupRoot.shellQuoted)
        ids=(\(ids))
        images=(\(images))
        mountpoints=(\(mountpoints))
        modes=(\(modes))
        preparations=(\(preparations))

        log() {
          echo "xcode-storage mount system: $*" >&2
        }

        fail() {
          log "$*"
          exit 78
        }

        is_mounted() {
          /sbin/mount | /usr/bin/grep -F " on $1 " >/dev/null 2>&1
        }

        mounted_from_configured_backend() {
          local image="$1"
          local mountpoint="$2"
          /usr/bin/hdiutil info | /usr/bin/awk -v image="$image" -v mountpoint="$mountpoint" '
            function trim(value) {
              sub(/^[[:space:]]+/, "", value)
              sub(/[[:space:]]+$/, "", value)
              return value
            }
            function equivalent_path(left, right) {
              if (left == right) {
                return 1
              }
              if (left == "/private" right) {
                return 1
              }
              if (right == "/private" left) {
                return 1
              }
              return 0
            }
            /^=+$/ {
              if (seen_image && seen_mount) {
                found = 1
              }
              seen_image = 0
              seen_mount = 0
              next
            }
            /^[[:space:]]*image-path[[:space:]]*:/ {
              value = $0
              sub(/^[^:]*:/, "", value)
              if (trim(value) == image) {
                seen_image = 1
              }
            }
            /\t/ {
              split($0, fields, "\t")
              value = trim(fields[length(fields)])
              if (substr(value, 1, 1) == "/" && equivalent_path(value, mountpoint)) {
                seen_mount = 1
              }
            }
            END {
              if (seen_image && seen_mount) {
                found = 1
              }
              exit(found ? 0 : 1)
            }
          '
        }

        reject_symlink() {
          if [[ -L "$1" ]]; then
            fail "mountpoint must not be a symlink: $1"
          fi
        }

        nested_mounts_under() {
          local mountpoint="$1"
          /sbin/mount | /usr/bin/awk -v mountpoint="$mountpoint" '
            function mounted_path(line) {
              sub(/^.* on /, "", line)
              sub(/ \\(.*$/, "", line)
              return line
            }
            function normalized(value) {
              if (value == "/private" mountpoint) {
                return mountpoint
              }
              return value
            }
            {
              path = normalized(mounted_path($0))
              if (index(path, mountpoint "/") == 1) {
                print path
              }
            }
          '
        }

        prepare_mountpoint() {
          local id="$1"
          local mountpoint="$2"
          local mode="$3"
          reject_symlink "$mountpoint"
          /bin/mkdir -p "$(/usr/bin/dirname "$mountpoint")"
          if [[ -e "$mountpoint" && ! -d "$mountpoint" ]]; then
            fail "mountpoint is not a directory: $mountpoint"
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
          local attached=0
          {
            /usr/bin/hdiutil attach "$image" -mountpoint "$tmp" -nobrowse -owners on >/dev/null
            attached=1
            /bin/mkdir -p "$tmp/mnt"
            /bin/chmod 1777 "$tmp/mnt"
          } always {
            if [[ "$attached" == "1" ]]; then
              /usr/bin/hdiutil detach "$tmp" >/dev/null 2>&1 || true
            fi
            /bin/rmdir "$tmp" 2>/dev/null || true
          }
        }

        if [[ ! -d "$root" ]]; then
          log "external root is not available: $root"
          exit 0
        fi

        mounted_any=0
        for index in {1..${#ids[@]}}; do
          id="${ids[$index]}"
          image="${images[$index]}"
          mountpoint="${mountpoints[$index]}"
          mode="${modes[$index]}"
          preparation="${preparations[$index]}"
          [[ -e "$image" ]] || fail "missing sparsebundle: $image"
          reject_symlink "$mountpoint"
          if is_mounted "$mountpoint"; then
            if mounted_from_configured_backend "$image" "$mountpoint"; then
              continue
            fi
            fail "mountpoint is already mounted from a different backend: $mountpoint"
          fi
          nested_mounts="$(nested_mounts_under "$mountpoint")"
          if [[ -n "$nested_mounts" ]]; then
            fail "mountpoint contains active nested mounts: $nested_mounts. Shut down simulators and detach those mounts before mounting $mountpoint."
          fi
          if [[ "$preparation" == "coreSimulatorImages" ]]; then
            prepare_images_sparsebundle "$image"
          fi
          prepare_mountpoint "$id" "$mountpoint" "$mode"
          /usr/bin/hdiutil attach "$image" -mountpoint "$mountpoint" -nobrowse -owners on
          mounted_any=1
        done

        if [[ "$mounted_any" == "1" ]]; then
          /usr/bin/xcrun simctl runtime scan-and-mount >/dev/null 2>&1 || true
        fi
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
