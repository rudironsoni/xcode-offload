# xcode-offload

`xcode-offload` moves Xcode and CoreSimulator storage to an external volume without changing the paths Apple tools expect. It is for Macs where Xcode, simulators, DerivedData, archives, and CoreSimulator caches are eating internal disk.

The tool mounts APFS sparsebundles at normal Apple paths. It does not use symlinks for managed paths.

Docs: https://rudironsoni.github.io/xcode-offload/

## What It Manages

- `~/Library/Developer/CoreSimulator/Devices`
- `~/Library/Developer/Xcode/DerivedData`
- `~/Library/Developer/Xcode/Archives`
- `/Library/Developer/CoreSimulator/Caches`
- `/Library/Developer/CoreSimulator/Images`
- `/Library/Developer/CoreSimulator/Volumes`
- `/Applications/Xcodes`
- optional `xcrun`, `simctl`, and `xcodebuild` shims for explicit flag routing

The storage root is your choice:

```sh
export XCODE_OFFLOAD_ROOT="/Volumes/YourExternalVolume"
```

`xcode-offload` never guesses a machine-specific volume.

## Quick Start

Install `xcode-offload`, then set the external storage root:

```sh
export XCODE_OFFLOAD_ROOT="/Volumes/YourExternalVolume"
```

Preview the user-level plan:

```sh
xcode-offload repair \
  --root "$XCODE_OFFLOAD_ROOT" \
  --home "$HOME" \
  --scope user \
  --install-shims \
  --dry-run
```

Install the user LaunchAgent and shims:

```sh
xcode-offload repair \
  --root "$XCODE_OFFLOAD_ROOT" \
  --home "$HOME" \
  --scope user \
  --install-shims \
  --load
```

Install the root-owned CoreSimulator cache helper:

```sh
sudo xcode-offload daemon install \
  --root "$XCODE_OFFLOAD_ROOT" \
  --home "$HOME"
```

Check the result:

```sh
xcode-offload doctor \
  --root "$XCODE_OFFLOAD_ROOT" \
  --require-shims \
  --strict
```

## APFS Mount Mode

Use `mounts` when you want Apple tools to see their normal paths backed by APFS sparsebundles:

```sh
xcode-offload mounts install \
  --root "$XCODE_OFFLOAD_ROOT" \
  --home "$HOME" \
  --scope user \
  --load

sudo xcode-offload mounts install \
  --root "$XCODE_OFFLOAD_ROOT" \
  --home "$HOME" \
  --scope system \
  --load

xcode-offload mounts status \
  --root "$XCODE_OFFLOAD_ROOT" \
  --home "$HOME" \
  --scope all
```

Default command output is concise. It shows the human-readable steps and status that matter during normal use. Add `--verbose` when you need raw commands or the full mount-check list.

`mounts install` rejects symlinked Apple paths. It also refuses to detach a mount that belongs to another backend. If a managed directory already contains data, the tool moves that data under:

```text
$XCODE_OFFLOAD_ROOT/Xcode/Backups/mounts/<timestamp>/
```

It never deletes backups for you.

## Verification

`mounts verify` runs the mount flow in a disposable scratch root:

```sh
xcode-offload mounts verify \
  --scratch-root "/Volumes/YourExternalVolume/xcode-offload-verify" \
  --mode user
```

System verification is gated because it can touch privileged launchd state:

```sh
sudo xcode-offload mounts verify \
  --scratch-root "/Volumes/YourExternalVolume/xcode-offload-verify" \
  --mode system \
  --allow-system
```

`--mode e2e` can also recreate a disposable simulator, but only when `--allow-sim-delete` is set.

## Simulator Recovery

CoreSimulator should see the normal Apple device path:

```text
~/Library/Developer/CoreSimulator/Devices
```

That path should be backed by the managed `DeviceSet.sparsebundle`, not by a symlink and not by a raw physical external APFS volume mounted directly at the device path. Raw external APFS can look correct in `mount`, but CoreSimulator can still fail to create or update simulator state there.

Use the tool to repair the mount and recreate the simulator inside the managed device store:

```sh
xcode-offload mounts repair \
  --root "$XCODE_OFFLOAD_ROOT" \
  --home "$HOME" \
  --scope user \
  --load

xcode-offload sim reset \
  --name Orlix-iPhone-15-Pro-Max \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro-Max \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-5 \
  --verify \
  --screenshot /tmp/orlix-verify.png
```

`sim reset --verify` deletes the simulator with that name, creates a fresh one, boots it, waits for bootstatus, runs a command inside the simulator, and captures a screenshot. That is the proof that the simulator is usable, not just listed.

## Command Groups

```text
xcode-offload doctor
xcode-offload repair
xcode-offload init
xcode-offload mount devices|caches
xcode-offload unmount devices|caches
xcode-offload install-shims
xcode-offload daemon install
xcode-offload launchd install
xcode-offload mounts install|repair|status|verify|uninstall
xcode-offload xcodes install-profile|doctor|env
xcode-offload sim runtimes|devices|recreate|reset|verify|open
```

The docs site has the command reference, runbooks, and troubleshooting notes.
