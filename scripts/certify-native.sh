#!/bin/sh
set -eu

mode="user"
keep_artifacts=0
runtime="${XCODE_STORAGE_VERIFY_RUNTIME:-${XCODE_STORAGE_CERT_RUNTIME:-}}"
device_type="${XCODE_STORAGE_VERIFY_DEVICE_TYPE:-${XCODE_STORAGE_CERT_DEVICE_TYPE:-}}"

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

scratch_root="${XCODE_STORAGE_VERIFY_ROOT:-${XCODE_STORAGE_CERT_ROOT:-}}"
if [ -z "$scratch_root" ]; then
  echo "missing XCODE_STORAGE_VERIFY_ROOT" >&2
  exit 64
fi

bin="${XCODE_STORAGE_BIN:-.build/debug/xcode-storage}"
if [ ! -x "$bin" ]; then
  swift build >/dev/null
fi

set -- "$bin" mounts verify --scratch-root "$scratch_root" --mode "$mode"

if [ -n "${XCODE_STORAGE_VERIFY_HOME:-${XCODE_STORAGE_CERT_HOME:-}}" ]; then
  set -- "$@" --home "${XCODE_STORAGE_VERIFY_HOME:-${XCODE_STORAGE_CERT_HOME:-}}"
fi

if [ -n "$runtime" ]; then
  set -- "$@" --runtime "$runtime"
fi

if [ -n "$device_type" ]; then
  set -- "$@" --device-type "$device_type"
fi

case "$keep_artifacts:${XCODE_STORAGE_VERIFY_KEEP_ARTIFACTS:-${XCODE_STORAGE_CERT_KEEP_ARTIFACTS:-0}}" in
  1:*|*:1|*:true|*:TRUE|*:yes|*:YES)
    set -- "$@" --keep-artifacts
    ;;
esac

case "${XCODE_STORAGE_VERIFY_ALLOW_SYSTEM:-${XCODE_STORAGE_CERT_ALLOW_SYSTEM:-0}}" in
  1|true|TRUE|yes|YES)
    set -- "$@" --allow-system
    ;;
esac

case "${XCODE_STORAGE_VERIFY_ALLOW_SIM_DELETE:-${XCODE_STORAGE_CERT_ALLOW_SIM_DELETE:-0}}" in
  1|true|TRUE|yes|YES)
    set -- "$@" --allow-sim-delete
    ;;
esac

exec "$@"
