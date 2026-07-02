# xcode-storage

`xcode-storage` is a macOS CLI for moving Xcode and CoreSimulator state onto
external storage while preserving the normal Apple command surface.

It manages:

- Xcode state under a user-selected root, for example `$XCODE_STORAGE_ROOT/Xcode`
- APFS sparsebundle mountpoints at Apple default paths
- CoreSimulator device, cache, image, and volume storage
- Xcode `DerivedData` and `Archives`
- optional `xcrun`, `simctl`, and `xcodebuild` shims for explicit flag rewriting
- diagnostics that validate actual mount state

This is intentionally separate from `xcodes`. `xcodes` manages Xcode versions
and simulator runtimes. `xcode-storage` manages where developer state lives and
how that state is mounted, repaired, and verified. A later `xcodes` integration
should delegate storage diagnostics and repair to this tool.

## Build

```sh
swift build
```

## Versioning

`xcode-storage` uses SemVer releases. Release tags must start with `v`, for
example `v0.1.0`.

```sh
xcode-storage version
```

Release builds regenerate `GeneratedBuildMetadata.swift` from the tag before
compilation, so a tagged `v0.1.0` build reports `0.1.0`.

## Commands

Command groups use `xcode-storage <group> <verb>`.

```sh
xcode-storage doctor [--root PATH] [--require-shims] [--skip-simctl] [--strict] [--json]
xcode-storage repair [--root PATH] [--home PATH] [--tool-path PATH] [--shim-dir PATH] [--scope user|system|all] [--install-shims] [--load] [--dry-run]
xcode-storage init [--root PATH] [--dry-run] [--no-create-images]
xcode-storage mount devices|caches [--root PATH] [--dry-run]
xcode-storage unmount devices|caches [--root PATH] [--dry-run]
xcode-storage install-shims [--root PATH] [--shim-dir PATH] [--tool-path PATH] [--dry-run]
xcode-storage daemon install [--root PATH] [--home PATH] [--tool-path PATH] [--no-load] [--dry-run]
xcode-storage launchd install [--root PATH] [--home PATH] [--tool-path PATH] [--no-load] [--dry-run]
xcode-storage mounts install [--root PATH] [--home PATH] [--tool-path PATH] [--scope user|system|all] [--load] [--dry-run]
xcode-storage mounts repair [--root PATH] [--home PATH] [--tool-path PATH] [--scope user|system|all] [--load] [--dry-run]
xcode-storage mounts uninstall [--root PATH] [--home PATH] [--scope user|system|all] [--unload] [--dry-run]
xcode-storage mounts status [--root PATH] [--home PATH] [--scope user|system|all] [--json]
xcode-storage mounts verify --scratch-root PATH [--mode user|system|e2e] [--home PATH] [--tool-path PATH] [--runtime ID] [--device-type ID] [--keep-artifacts] [--allow-system] [--allow-sim-delete]
xcode-storage install-launchd [--root PATH] [--home PATH] [--tool-path PATH] [--scope user|system|all] [--load] [--dry-run]
xcode-storage uninstall-launchd [--root PATH] [--home PATH] [--scope user|system|all] [--unload] [--dry-run]
xcode-storage sim runtimes
xcode-storage sim devices [--all]
xcode-storage sim recreate --name NAME --device-type TYPE --runtime RUNTIME [--boot] [--boot-timeout SECONDS]
```

`daemon install` and `launchd install` are equivalent product-facing commands
for installing the system LaunchDaemon and root-owned helper. The older
`install-launchd --scope system` command remains available as a lower-level
compatibility spelling.

## Safety Rules

- `doctor` is read-mostly and exits non-zero when required state is missing.
- `doctor --strict` also checks sparsebundle readability, APFS filesystems,
  sparsebundle provenance, launchd plist validity, and launchd last exit status.
- `repair --dry-run` prints the init, mount, launchd, and optional shim actions
  needed to move the machine toward expected state.
- `init --dry-run` prints the directory and sparsebundle creation plan.
- `mount --dry-run`, `unmount --dry-run`, and `install-shims --dry-run` print
  planned actions without changing system state.
- `daemon install --dry-run` and `launchd install --dry-run` print the
  root-owned LaunchDaemon/helper install plan without writing into `/Library`.
- `mounts install --dry-run` prints APFS sparsebundle creation, backup, mount,
  and launchd actions for transparent Apple default paths.
- `mounts install` never creates symlinks at Apple paths. Symlinked managed
  paths are invalid and must be replaced by real directories used as APFS
  mountpoints.
- Backup deletion is never an implicit repair action.
- Simulator first boot uses a long timeout because recent iOS runtimes spend
  many minutes in first-boot data migration.

## Setup

Choose an external storage root explicitly. The tool never defaults to a
machine-specific volume:

```sh
export XCODE_STORAGE_ROOT="/Volumes/YourExternalVolume"
```

Preview the full plan:

```sh
xcode-storage repair --root "$XCODE_STORAGE_ROOT" --home "$HOME" --install-shims --dry-run
```

Install user-owned pieces without sudo:

```sh
xcode-storage repair \
  --root "$XCODE_STORAGE_ROOT" \
  --home "$HOME" \
  --scope user \
  --install-shims \
  --load
```

Install the root-owned CoreSimulator cache daemon once:

```sh
sudo xcode-storage daemon install --root "$XCODE_STORAGE_ROOT" --home "$HOME"
```

The equivalent launchd spelling is:

```sh
sudo xcode-storage launchd install --root "$XCODE_STORAGE_ROOT" --home "$HOME"
```

After one privileged install, normal `xcode-storage`, `xcrun`, `simctl`, and
`xcodebuild` usage should run as your user. Use `sudo` again only when
reinstalling, unloading, or changing the system LaunchDaemon/helper.

Verify:

```sh
xcode-storage doctor --root "$XCODE_STORAGE_ROOT" --require-shims --strict
```

## APFS Mount Manager

The mount manager makes default Apple tools see regular Apple paths backed by
mounted APFS sparsebundles. It does not rely on symlinks.

Managed paths include:

```text
~/Library/Developer/CoreSimulator/Devices
~/Library/Developer/Xcode/DerivedData
~/Library/Developer/Xcode/Archives
/Library/Developer/CoreSimulator/Caches
/Library/Developer/CoreSimulator/Images
/Library/Developer/CoreSimulator/Volumes
```

Install user-owned mountpoints:

```sh
xcode-storage mounts install --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope user --load
```

Install root-owned mountpoints once:

```sh
sudo xcode-storage mounts install --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope system --load
```

Check status:

```sh
xcode-storage mounts status --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope all
```

`mounts status` verifies each managed path:

- is not a symlink
- has a configured sparsebundle
- is mounted at the expected Apple path
- is APFS
- has owners enabled
- belongs to the configured sparsebundle backend reported by `hdiutil info`

The mount manager deliberately refuses symlinked Apple paths because
CoreSimulator and `simdiskimaged` can reject symlinked mount parents. If a
managed path already contains data, it backs that data up under
`$XCODE_STORAGE_ROOT/Xcode/Backups/mounts/<timestamp>/` before mounting.
Backups are never deleted automatically.

If a managed path is already mounted from a backend that is not the configured
sparsebundle, repair fails instead of detaching or replacing that mount. This
protects unrelated mounts and catches partial or drifted storage setups.

After the mount manager has mounted the Apple paths, default Apple tools can use
those paths without shims:

```sh
PATH="/usr/bin:/bin:/usr/sbin:/sbin" /usr/bin/xcrun simctl list devices available
PATH="/usr/bin:/bin:/usr/sbin:/sbin" /usr/bin/xcodebuild -version
```

Shims remain available when automation wants explicit build flag rewriting and
`TMPDIR` routing, but they are not the transparent storage mechanism.

## Launchd

The user LaunchAgent keeps the CoreSimulator device store mounted:

```sh
xcode-storage install-launchd --scope user --root "$XCODE_STORAGE_ROOT" --load
```

The system LaunchDaemon installs a root-owned helper that keeps
`/Library/Developer/CoreSimulator/Caches` mounted from the external cache
sparsebundle:

```sh
sudo xcode-storage daemon install --root "$XCODE_STORAGE_ROOT" --home "$HOME"
```

`launchd install` is an equivalent spelling:

```sh
sudo xcode-storage launchd install --root "$XCODE_STORAGE_ROOT" --home "$HOME"
```

Pass `--home` when running through `sudo`; otherwise the tool targets
`/var/root` user-specific paths. Use `--no-load` when staging files without
immediately bootstrapping the system LaunchDaemon:

```sh
sudo xcode-storage daemon install --root "$XCODE_STORAGE_ROOT" --home "$HOME" --no-load
```

## Repair

Use `repair --dry-run` first:

```sh
xcode-storage repair --root "$XCODE_STORAGE_ROOT" --home "$HOME" --install-shims --dry-run
```

Run without `--dry-run` when the plan is correct. Add `--load` to reload the
generated jobs while writing them. Use `--scope user` for non-privileged user
LaunchAgent repair, and use explicit `--root` and `--home` when running
privileged system repairs through `sudo`.

Recommended split install:

```sh
xcode-storage repair --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope user --install-shims --load
sudo xcode-storage daemon install --root "$XCODE_STORAGE_ROOT" --home "$HOME"
xcode-storage doctor --root "$XCODE_STORAGE_ROOT" --require-shims --strict
```

`repair --scope all` is still supported, but split install is easier to reason
about because only the system LaunchDaemon/helper step needs sudo.

## Current Status

This repository is the initial product extraction from the shell proof in the
dotfiles repository. It is not yet a Homebrew formula.

## Reliability

Reliability work is CI-only by default. Tests must not require sudo, a specific
external volume, live system mount mutation, launchd bootstrap, or destructive
CoreSimulator device changes. Privileged destructive paths should be covered
with dry-run CLI smoke checks and stubbed Swift tests.

Before merging a storage release change, run:

```sh
sh -n scripts/*.sh
swift test
scripts/check-no-machine-defaults.sh
scripts/smoke-cli.sh
scripts/check-release-artifact.sh
```

Live machine verification can still be done manually with `doctor --strict`,
but it is intentionally not part of regular GitHub Actions. The mount manager
includes a gated verification command for dedicated machines:

```sh
xcode-storage mounts verify \
  --scratch-root "/Volumes/YourExternalVolume/xcode-storage-verify" \
  --mode user

sudo xcode-storage mounts verify \
  --scratch-root "/Volumes/YourExternalVolume/xcode-storage-verify" \
  --mode system \
  --allow-system
```

`--mode e2e` can recreate a disposable simulator only when
`--allow-sim-delete` is set.

## Release

Prepare releases from GitHub Actions:

```sh
gh workflow run prepare-release.yml
```

The prepare workflow runs tests, updates and commits `CHANGELOG.md`, creates
the next SemVer tag from Conventional Commits, builds the macOS arm64 tarball,
verifies the SHA-256 checksum, and publishes a GitHub Release. The first
release falls back to `v0.1.0` when no older release tag exists.

Existing tags can also be released manually:

```sh
gh workflow run release.yml -f tag=v0.1.0
```

The tag release workflow validates the SemVer tag, builds the artifact, verifies
the checksum, uploads both files, and publishes GitHub Release generated release
notes.
