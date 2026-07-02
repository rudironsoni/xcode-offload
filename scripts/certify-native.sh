#!/bin/sh
set -eu

mode="user"
keep_artifacts="${XCODE_STORAGE_CERT_KEEP_ARTIFACTS:-0}"
runtime="${XCODE_STORAGE_CERT_RUNTIME:-}"
device_type="${XCODE_STORAGE_CERT_DEVICE_TYPE:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      mode="${2:?missing value for --mode}"
      shift 2
      ;;
    --runtime)
      runtime="${2:?missing value for --runtime}"
      shift 2
      ;;
    --device-type)
      device_type="${2:?missing value for --device-type}"
      shift 2
      ;;
    --keep-artifacts)
      keep_artifacts=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

cert_root="${XCODE_STORAGE_CERT_ROOT:-}"
if [ -z "$cert_root" ]; then
  echo "missing XCODE_STORAGE_CERT_ROOT" >&2
  exit 64
fi

case "$cert_root" in
  /|/Users|/Users/|/System|/System/|/Library|/Library/|/Volumes|/Volumes/)
    echo "refusing unsafe certification root: $cert_root" >&2
    exit 78
    ;;
esac

case "$mode" in
  user|system|e2e) ;;
  *)
    echo "expected --mode user, system, or e2e" >&2
    exit 64
    ;;
esac

run_id="$(date -u +%Y%m%d-%H%M%S)-$$"
root="$cert_root/xcode-storage-cert-$run_id"
log="$root/certification.log"
bin="${XCODE_STORAGE_BIN:-.build/debug/xcode-storage}"
cert_home="${XCODE_STORAGE_CERT_HOME:-}"
if [ -z "$cert_home" ]; then
  if [ -n "${SUDO_USER:-}" ]; then
    cert_home="/Users/$SUDO_USER"
  else
    cert_home="$HOME"
  fi
fi

mkdir -p "$root"
touch "$log"

log_step() {
  printf '==> %s\n' "$*" | tee -a "$log"
}

run() {
  log_step "$*"
  status_file="$root/.last-command-status"
  set +e
  (
    "$@"
    printf '%s\n' "$?" > "$status_file"
  ) 2>&1 | tee -a "$log"
  tee_status="$?"
  status="$(cat "$status_file" 2>/dev/null || printf '%s\n' "$tee_status")"
  rm -f "$status_file"
  set -e
  return "$status"
}

enabled() {
  case "$1" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  status=$?
  if enabled "$keep_artifacts"; then
    log_step "keeping certification artifacts at $root"
    exit "$status"
  fi
  log_step "cleaning certification artifacts at $root"
  rm -rf "$root"
  exit "$status"
}
trap cleanup EXIT INT TERM

if [ ! -x "$bin" ]; then
  run swift build
fi

log_step "certification mode: $mode"
log_step "certification root: $root"

case "$mode" in
  user)
    run "$bin" native install --root "$root" --home "$root/home" --scope user --dry-run
    run "$bin" native install --root "$root" --home "$root/home" --scope user
    run "$bin" native status --root "$root" --home "$root/home" --scope user --json
    run "$bin" native uninstall --root "$root" --home "$root/home" --scope user
    ;;
  system)
    if ! enabled "${XCODE_STORAGE_CERT_ALLOW_SYSTEM:-0}"; then
      echo "system certification requires XCODE_STORAGE_CERT_ALLOW_SYSTEM=1" >&2
      exit 77
    fi
    if [ "$(id -u)" != "0" ]; then
      echo "system certification requires root" >&2
      exit 77
    fi
    run "$bin" native install --root "$root" --home "$cert_home" --scope system --dry-run
    run "$bin" native install --root "$root" --home "$cert_home" --scope system --load
    run "$bin" native status --root "$root" --home "$cert_home" --scope system --json
    run "$bin" native uninstall --root "$root" --home "$cert_home" --scope system --unload
    ;;
  e2e)
    if ! enabled "${XCODE_STORAGE_CERT_ALLOW_SIM_DELETE:-0}"; then
      echo "e2e certification requires XCODE_STORAGE_CERT_ALLOW_SIM_DELETE=1" >&2
      exit 77
    fi
    run "$bin" native install --root "$root" --home "$HOME" --scope user --load
    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" /usr/bin/xcrun simctl list runtimes
    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" /usr/bin/xcrun simctl list devices available
    run env PATH="/usr/bin:/bin:/usr/sbin:/sbin" /usr/bin/xcodebuild -version
    if [ -n "$runtime" ] && [ -n "$device_type" ]; then
      name="xcode-storage-cert-$run_id"
      run "$bin" sim recreate --name "$name" --device-type "$device_type" --runtime "$runtime" --boot
      run /usr/bin/xcrun simctl delete "$name"
    fi
    run "$bin" native uninstall --root "$root" --home "$HOME" --scope user --unload
    ;;
esac

log_step "native certification passed"
