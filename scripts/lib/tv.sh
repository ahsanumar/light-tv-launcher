#!/usr/bin/env bash
# Shared helpers for the scripts in scripts/. Source it; don't run it.

# Sets TV_ADDR to the TV to talk to:
#   - TV_ADDR from the environment if set (e.g. TV_ADDR=192.168.1.50:5555),
#   - otherwise the only device `adb devices` lists,
#   - otherwise exits with an explanation (none or several connected).
resolve_tv_addr() {
  if [[ -n "${TV_ADDR:-}" ]]; then
    if ! adb -s "$TV_ADDR" get-state >/dev/null 2>&1; then
      adb connect "$TV_ADDR" >/dev/null 2>&1 || true
      adb -s "$TV_ADDR" get-state >/dev/null 2>&1 \
        || { echo "ERROR: cannot reach TV at $TV_ADDR (is network/USB debugging on and authorized?)" >&2; exit 1; }
    fi
    return 0
  fi

  local connected_devices=()
  while read -r device_serial device_state _rest; do
    [[ "$device_state" == "device" ]] && connected_devices+=("$device_serial")
  done < <(adb devices | tail -n +2)

  case "${#connected_devices[@]}" in
    1) TV_ADDR="${connected_devices[0]}" ;;
    0) echo "ERROR: no TV connected. Run: adb connect <tv-ip>:5555  (or set TV_ADDR)" >&2; exit 1 ;;
    *) echo "ERROR: several devices connected (${connected_devices[*]}); set TV_ADDR to pick one" >&2; exit 1 ;;
  esac
}

# adb shell with CRs stripped. </dev/null: otherwise adb swallows the stdin of callers' `while read` loops.
tv_shell() { adb -s "$TV_ADDR" shell "$@" </dev/null | tr -d '\r'; }
