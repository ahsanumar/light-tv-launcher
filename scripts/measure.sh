#!/usr/bin/env bash
# Measure TV performance: cold boot time, free RAM, and app cold-start times.
#
# Usage: scripts/measure.sh <label> [--reboot]
#   <label>    name for this run, e.g. "before" or "after"; results go to measurements/<label>.txt
#   --reboot   reboot the TV first and record cold boot time (recommended for fair comparisons)
#
# Env: TV_ADDR (optional when exactly one TV is connected to adb)
set -euo pipefail

SETTLE_SECONDS="${SETTLE_SECONDS:-180}"   # background services keep starting for a few minutes after boot
LAUNCH_RUNS=3
LAUNCH_PACKAGES=(com.android.tv.settings com.google.android.youtube.tv org.courville.nova)

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
label="${1:?usage: measure.sh <label> [--reboot]}"
should_reboot="${2:-}"
output_file="$project_dir/measurements/$label.txt"
mkdir -p "$project_dir/measurements"

# shellcheck source=lib/tv.sh
source "$(dirname "$0")/lib/tv.sh"
log() { echo "[$(date +%H:%M:%S)] $*" >&2; }
record() { echo "$1=$2" | tee -a "$output_file"; }

median() { sort -n | awk '{values[NR]=$1} END {if (NR==0) {print "NA"} else {print values[int((NR+1)/2)]}}'; }

wait_for_boot() {
  local deadline=$((SECONDS + 300))
  while (( SECONDS < deadline )); do
    adb connect "$TV_ADDR" >/dev/null 2>&1 || true
    if [[ "$(adb -s "$TV_ADDR" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "ERROR: TV did not finish booting within 300s" >&2
  exit 1
}

resolve_tv_addr

: > "$output_file"
record label "$label"
record timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$should_reboot" == "--reboot" ]]; then
  log "Rebooting TV"
  adb -s "$TV_ADDR" reboot
  sleep 15  # give adbd time to go down so we don't read the pre-reboot boot_completed flag
  wait_for_boot
  # Kernel uptime when boot_completed is first seen = cold boot duration (±2s poll interval)
  boot_seconds="$(tv_shell cat /proc/uptime | awk '{print $1}')"
  record boot_completed_seconds "$boot_seconds"
fi

log "Waiting ${SETTLE_SECONDS}s for background services to settle"
sleep "$SETTLE_SECONDS"

log "Sampling memory"
available_samples=()
free_samples=()
for sample_index in 1 2 3; do
  meminfo="$(tv_shell cat /proc/meminfo)"
  available_samples+=("$(awk '/^MemAvailable:/ {print int($2/1024)}' <<<"$meminfo")")
  free_samples+=("$(awk '/^MemFree:/ {print int($2/1024)}' <<<"$meminfo")")
  sleep 10
done
record mem_available_mb "$(printf '%s\n' "${available_samples[@]}" | median)"
record mem_free_mb "$(printf '%s\n' "${free_samples[@]}" | median)"
record process_count "$(tv_shell ps -A | tail -n +2 | wc -l | tr -d ' ')"
# App processes run as u0_aNNN; everything else is native daemons / system
record app_process_count "$(tv_shell ps -A -o USER | grep -c '^u0_a' || true)"

measure_launch() {
  local package_name="$1" component="$2" is_home="${3:-}"
  local launch_samples=()
  for run_index in $(seq 1 "$LAUNCH_RUNS"); do
    if [[ "$is_home" == "home" ]]; then
      # Android instantly restarts a killed home screen while it's in front, so put another app on top first
      tv_shell am start -n com.android.tv.settings/.MainSettings >/dev/null
      sleep 3
    fi
    tv_shell am force-stop "$package_name"
    sleep 3
    local total_time
    total_time="$(tv_shell am start -W -n "$component" | awk -F': ' '/TotalTime/ {print $2}')"
    [[ -n "$total_time" ]] && launch_samples+=("$total_time")
    sleep 4
  done
  # Close the app so leftover screens (e.g. permission prompts) don't affect the next measurement
  [[ "$is_home" == "home" ]] || tv_shell am force-stop "$package_name"
  tv_shell input keyevent KEYCODE_HOME
  sleep 3
  if (( ${#launch_samples[@]} == 0 )); then echo "NA"; else printf '%s\n' "${launch_samples[@]}" | median; fi
}

log "Measuring home screen cold start"
home_component="$(tv_shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1)"
record home_component "$home_component"
record home_cold_start_ms "$(measure_launch "${home_component%%/*}" "$home_component" home)"

for package_name in "${LAUNCH_PACKAGES[@]}"; do
  component="$(tv_shell cmd package resolve-activity --brief -c android.intent.category.LEANBACK_LAUNCHER "$package_name" | tail -1)"
  if [[ "$component" != */* ]]; then
    log "Skipping $package_name (no launchable activity found)"
    continue
  fi
  log "Measuring cold start of $package_name"
  record "launch_ms.$package_name" "$(measure_launch "$package_name" "$component")"
done

# PSS of the home screen alone: the most direct measure of what the launcher swap saves.
# (Per-package dumpsys is fast; a full `dumpsys meminfo` times out after 10s on this TV.)
home_pss_kb="$(tv_shell dumpsys meminfo "${home_component%%/*}" | awk '/TOTAL PSS:/ {print $3; exit}')"
record home_pss_kb "${home_pss_kb:-NA}"

log "Top memory users"
# RSS overcounts shared zygote pages, but it's instant and fine for spotting the biggest processes
tv_shell ps -A -o RSS,USER,NAME | sort -rn | head -30 > "$project_dir/measurements/$label.top-processes.txt"

log "Done -> $output_file"
