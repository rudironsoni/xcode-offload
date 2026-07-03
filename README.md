# xcode-storage

`xcode-storage` moves Xcode and CoreSimulator state onto external storage while
keeping Apple tools pointed at the paths they already expect.

It is built for Macs where Xcode, simulators, DerivedData, archives, and
CoreSimulator caches are too large for the internal disk. The tool uses mounted
APFS sparsebundles at Apple paths. It does not solve this with symlinks.

Docs: https://rudironsoni.github.io/xcode-storage/

## What it manages

- `~/Library/Developer/CoreSimulator/Devices`
- `~/Library/Developer/Xcode/DerivedData`
- `~/Library/Developer/Xcode/Archives`
- `/Library/Developer/CoreSimulator/Caches`
- `/Library/Developer/CoreSimulator/Images`
- `/Library/Developer/CoreSimulator/Volumes`
- optional `xcrun`, `simctl`, and `xcodebuild` shims for explicit flag routing

The mount manager backs those paths with APFS sparsebundles under a root you
choose:

```sh
export XCODE_STORAGE_ROOT="/Volumes/YourExternalVolume"
```

The tool never guesses a machine-specific external volume.

## Quick start

Install `xcode-storage`, then choose the external storage root explicitly:

```sh
export XCODE_STORAGE_ROOT="/Volumes/YourExternalVolume"
```

Preview the user-level plan:

```sh
xcode-storage repair \
  --root "$XCODE_STORAGE_ROOT" \
  --home "$HOME" \
  --scope user \
  --install-shims \
  --dry-run
```

Install user-owned jobs and shims:

```sh
xcode-storage repair \
  --root "$XCODE_STORAGE_ROOT" \
  --home "$HOME" \
  --scope user \
  --install-shims \
  --load
```

Install the root-owned CoreSimulator cache helper:

```sh
sudo xcode-storage daemon install \
  --root "$XCODE_STORAGE_ROOT" \
  --home "$HOME"
```

Check the result:

```sh
xcode-storage doctor \
  --root "$XCODE_STORAGE_ROOT" \
  --require-shims \
  --strict
```

## APFS mount mode

Use the `mounts` command group when you want Apple tools to see normal Apple
paths backed by APFS sparsebundles:

```sh
xcode-storage mounts install --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope user --load
sudo xcode-storage mounts install --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope system --load
xcode-storage mounts status --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope all
```

`mounts install` refuses symlinked Apple paths and refuses to detach a mount
that belongs to a different backend. If a managed directory already contains
data, the tool moves it under:

```text
$XCODE_STORAGE_ROOT/Xcode/Backups/mounts/<timestamp>/
```

The tool does not delete backups for you.

## Verification

`mounts verify` runs the mount workflow in a disposable scratch root. Use it on
a dedicated machine or external volume when you want proof that the sparsebundle
flow works end to end:

```sh
xcode-storage mounts verify \
  --scratch-root "/Volumes/YourExternalVolume/xcode-storage-verify" \
  --mode user
```

System verification is gated because it can touch privileged launchd state:

```sh
sudo xcode-storage mounts verify \
  --scratch-root "/Volumes/YourExternalVolume/xcode-storage-verify" \
  --mode system \
  --allow-system
```

`--mode e2e` can also recreate a disposable simulator, but only when
`--allow-sim-delete` is set.

## Command groups

```text
xcode-storage doctor
xcode-storage repair
xcode-storage init
xcode-storage mount devices|caches
xcode-storage unmount devices|caches
xcode-storage install-shims
xcode-storage daemon install
xcode-storage launchd install
xcode-storage mounts install|repair|status|verify|uninstall
xcode-storage sim runtimes|devices|recreate
```

See the docs site for command examples, safety notes, launchd behavior, and
troubleshooting.
