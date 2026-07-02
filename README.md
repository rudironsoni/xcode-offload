# xcode-storage

`xcode-storage` is a macOS CLI for moving Xcode build state and CoreSimulator
state onto external storage without losing the normal Apple command surface.

The first target is the workflow proven on Rudi's machine:

- external Xcode root under `/Volumes/1TB/Xcode`
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

## Commands

```sh
xcode-storage doctor [--root PATH] [--require-shims] [--skip-simctl] [--json]
xcode-storage init [--root PATH] [--dry-run] [--no-create-images]
xcode-storage mount devices|caches [--root PATH] [--dry-run]
xcode-storage unmount devices|caches [--root PATH] [--dry-run]
xcode-storage install-shims [--root PATH] [--shim-dir PATH] [--tool-path PATH] [--dry-run]
xcode-storage sim runtimes
xcode-storage sim devices [--all]
xcode-storage sim recreate --name NAME --device-type TYPE --runtime RUNTIME [--boot] [--boot-timeout SECONDS]
```

## Safety Rules

- `doctor` is read-mostly and exits non-zero when required state is missing.
- `init --dry-run` prints the directory and sparsebundle creation plan.
- `mount --dry-run`, `unmount --dry-run`, and `install-shims --dry-run` print
  planned actions without changing the system.
- Shims are opt-in through `install-shims`.
- Backup deletion is not implemented as an implicit repair action.
- Simulator first boot defaults to a long timeout because recent iOS runtimes can
  spend many minutes in first-boot data migration.

## Current Status

This repository is an initial product extraction from the shell proof in the
dotfiles repository. It is not yet a Homebrew formula and it does not yet install
LaunchAgents or LaunchDaemons.
