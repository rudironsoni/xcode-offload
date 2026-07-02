# xcode-storage

`xcode-storage` is a macOS CLI for moving Xcode build state and CoreSimulator
state onto external storage without losing the normal Apple command surface.

The first target is the workflow proven by the original extraction:

- external Xcode root under a user-selected volume, for example
  `$XCODE_STORAGE_ROOT/Xcode`
- external `DerivedData`, package cache, temporary directory, logs, products,
  and result bundles
- sparsebundle-backed CoreSimulator device store
- sparsebundle-backed CoreSimulator cache store
- optional shims for `xcrun`, `simctl`, and `xcodebuild`
- doctor checks that validate the actual mount and command state

This is intentionally separate from `xcodes`. `xcodes` manages Xcode versions
and simulator runtimes. `xcode-storage` manages where developer state lives and
how that state is mounted, repaired, and verified. A later `xcodes` integration
should be diagnostic or delegate to this tool.

## Build

```sh
swift build
```

## Versioning

`xcode-storage` uses SemVer for releases. Release tags must start with `v`, for
example `v0.1.0`.

Development builds report git-derived metadata:

```sh
xcode-storage version
```

Release builds regenerate `GeneratedBuildMetadata.swift` from the tag before
compilation, so a tagged `v0.1.0` build reports `0.1.0`.

## Commands

```sh
xcode-storage doctor [--root PATH] [--require-shims] [--skip-simctl] [--strict] [--json]
xcode-storage repair [--root PATH] [--home PATH] [--tool-path PATH] [--shim-dir PATH] [--install-shims] [--load] [--dry-run]
xcode-storage init [--root PATH] [--dry-run] [--no-create-images]
xcode-storage mount devices|caches [--root PATH] [--dry-run]
xcode-storage unmount devices|caches [--root PATH] [--dry-run]
xcode-storage install-shims [--root PATH] [--shim-dir PATH] [--tool-path PATH] [--dry-run]
xcode-storage install-launchd [--root PATH] [--home PATH] [--tool-path PATH] [--scope user|system|all] [--load] [--dry-run]
xcode-storage uninstall-launchd [--root PATH] [--home PATH] [--scope user|system|all] [--unload] [--dry-run]
xcode-storage sim runtimes
xcode-storage sim devices [--all]
xcode-storage sim recreate --name NAME --device-type TYPE --runtime RUNTIME [--boot] [--boot-timeout SECONDS]
```

## Safety Rules

- `doctor` is read-mostly and exits non-zero when required state is missing.
- `doctor --strict` also checks sparsebundle readability, APFS mounted
  filesystems, cache sparsebundle provenance, launchd plist validity, and
  launchd last exit status.
- `repair --dry-run` prints the init, mount, launchd, and optional shim actions
  needed to bring a machine toward the expected state.
- `init --dry-run` prints the directory and sparsebundle creation plan.
- `mount --dry-run`, `unmount --dry-run`, and `install-shims --dry-run` print
  planned actions without changing the system.
- `install-launchd --dry-run` prints the LaunchAgent, LaunchDaemon, and helper
  install plan without writing into `~/Library` or `/Library`.
- Shims are opt-in through `install-shims`.
- Backup deletion is not implemented as an implicit repair action.
- Simulator first boot defaults to a long timeout because recent iOS runtimes can
  spend many minutes in first-boot data migration.

## Launchd

The user LaunchAgent keeps the CoreSimulator device store mounted:

```sh
xcode-storage install-launchd --scope user --root "$XCODE_STORAGE_ROOT" --load
```

The system LaunchDaemon installs a root-owned helper that keeps
`/Library/Developer/CoreSimulator/Caches` mounted from the external cache
sparsebundle:

```sh
sudo xcode-storage install-launchd --scope system --root "$XCODE_STORAGE_ROOT" --home "$HOME" --load
```

Pass `--home` when running through `sudo`; otherwise the tool will target
`/var/root` for user-specific paths.

## Repair

Use `repair --dry-run` first:

```sh
xcode-storage repair --root "$XCODE_STORAGE_ROOT" --home "$HOME" --install-shims --dry-run
```

Then run without `--dry-run` when the plan is correct. Add `--load` to reload
the generated launchd jobs after writing them.

## Current Status

This repository is an initial product extraction from the shell proof in the
dotfiles repository. It is not yet a Homebrew formula.

## Release

Tagged releases are built by GitHub Actions:

```sh
git tag v0.1.0
git push origin v0.1.0
```

The release workflow builds a macOS arm64 tarball, generates release notes from
the git log, uploads the artifact and SHA-256 checksum, and publishes a GitHub
Release.
