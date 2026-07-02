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
xcode-storage install-launchd [--root PATH] [--home PATH] [--tool-path PATH] [--scope user|system|all] [--load] [--dry-run]
xcode-storage uninstall-launchd [--root PATH] [--home PATH] [--scope user|system|all] [--unload] [--dry-run]
xcode-storage sim runtimes
xcode-storage sim devices [--all]
xcode-storage sim recreate --name NAME --device-type TYPE --runtime RUNTIME [--boot] [--boot-timeout SECONDS]
```

`daemon install` and `launchd install` are equivalent product-facing commands
for installing the system LaunchDaemon and root-owned cache helper. The older
`install-launchd --scope system` command remains available as a lower-level
compatibility spelling.

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
- `daemon install --dry-run` and `launchd install --dry-run` print the
  root-owned LaunchDaemon and helper install plan without writing into
  `/Library`.
- `install-launchd --dry-run` prints the LaunchAgent, LaunchDaemon, and helper
  install plan without writing into `~/Library` or `/Library`.
- Shims are opt-in through `install-shims`.
- Backup deletion is not implemented as an implicit repair action.
- Simulator first boot defaults to a long timeout because recent iOS runtimes can
  spend many minutes in first-boot data migration.

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

After that one privileged install, normal `xcode-storage`, `xcrun`, `simctl`,
and `xcodebuild` usage should run as the user. Use `sudo` again only when
reinstalling, unloading, or changing the system LaunchDaemon/helper.

Verify:

```sh
xcode-storage doctor --root "$XCODE_STORAGE_ROOT" --require-shims --strict
```

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

Pass `--home` when running through `sudo`; otherwise the tool will target
`/var/root` for user-specific paths.

Use `--no-load` when packaging or staging files without immediately bootstrapping
the system LaunchDaemon:

```sh
sudo xcode-storage daemon install --root "$XCODE_STORAGE_ROOT" --home "$HOME" --no-load
```

## Repair

Use `repair --dry-run` first:

```sh
xcode-storage repair --root "$XCODE_STORAGE_ROOT" --home "$HOME" --install-shims --dry-run
```

Then run without `--dry-run` when the plan is correct. Add `--load` to reload
the generated launchd jobs after writing them. Use `--scope user` for
non-privileged user LaunchAgent repair, and run with `sudo --preserve-env` or
an explicit `--root`/`--home` for `--scope system` or `--scope all`.

Recommended split install:

```sh
xcode-storage repair --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope user --install-shims --load
sudo xcode-storage daemon install --root "$XCODE_STORAGE_ROOT" --home "$HOME"
xcode-storage doctor --root "$XCODE_STORAGE_ROOT" --require-shims --strict
```

`repair --scope all` is still supported, but the split install is easier to
reason about because only the system LaunchDaemon/helper step needs sudo.

## Current Status

This repository is an initial product extraction from the shell proof in the
dotfiles repository. It is not yet a Homebrew formula.

## Reliability

Reliability work is CI-only by default. Tests must not require sudo, a specific
external volume, live mount mutation, launchd bootstrap, or destructive
CoreSimulator device changes. Privileged and destructive paths should be covered
with dry-run CLI smoke checks or stubbed Swift tests.

Before merging a storage or release change, run:

```sh
sh -n scripts/*.sh
swift test
scripts/check-no-machine-defaults.sh
scripts/smoke-cli.sh
scripts/check-release-artifact.sh
```

Live machine certification can still be done manually with `doctor --strict`,
but it is intentionally not part of GitHub Actions.

## Release

Prepare releases from GitHub Actions:

```sh
gh workflow run prepare-release.yml
```

The prepare workflow runs tests, updates and commits `CHANGELOG.md`, creates the
next SemVer tag from Conventional Commits, builds the macOS arm64 tarball,
verifies the SHA-256 checksum, and publishes the GitHub Release. The first
release falls back to `v0.1.0` when no older release tag exists.

Existing tags can also be released manually:

```sh
gh workflow run release.yml -f tag=v0.1.0
```

The tag release workflow validates the SemVer tag, builds the artifact, verifies
the checksum, uploads both files, and publishes the GitHub Release with generated
release notes.
