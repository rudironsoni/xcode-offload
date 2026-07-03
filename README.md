# xcode-storage

`xcode-storage` moves Xcode and CoreSimulator data to external storage without
changing the paths Apple tools expect.

It is for Macs where Xcode, simulators, DerivedData, archives, and
CoreSimulator caches are eating the internal disk. The tool mounts APFS
sparsebundles at the normal Apple paths. It does not use symlinks for those
paths.

Docs: https://rudironsoni.github.io/xcode-storage/

## What it manages

- `~/Library/Developer/CoreSimulator/Devices`
- `~/Library/Developer/Xcode/DerivedData`
- `~/Library/Developer/Xcode/Archives`
- `/Library/Developer/CoreSimulator/Caches`
- `/Library/Developer/CoreSimulator/Images`
- `/Library/Developer/CoreSimulator/Volumes`
- optional `xcrun`, `simctl`, and `xcodebuild` shims for explicit flag routing

The storage root is your choice:

```sh
export XCODE_STORAGE_ROOT="/Volumes/YourExternalVolume"
```

`xcode-storage` never guesses a machine-specific volume.

## Quick start

Install `xcode-storage`, then set the external storage root:

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

Install the user LaunchAgent and shims:

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

Use `mounts` when you want Apple tools to see their normal paths backed by APFS
sparsebundles:

```sh
xcode-storage mounts install --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope user --load
sudo xcode-storage mounts install --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope system --load
xcode-storage mounts status --root "$XCODE_STORAGE_ROOT" --home "$HOME" --scope all
```

`mounts install` rejects symlinked Apple paths. It also refuses to detach a
mount that belongs to another backend. If a managed directory already contains
data, the tool moves that data under:

```text
$XCODE_STORAGE_ROOT/Xcode/Backups/mounts/<timestamp>/
```

It never deletes backups for you.

## Verification

`mounts verify` runs the mount flow in a disposable scratch root:

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

The docs site has the command reference, runbooks, and troubleshooting notes.
