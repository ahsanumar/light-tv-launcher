#!/usr/bin/env bash
# Reversibly debloat the TV and (optionally) speed up UI animations. No root needed.
#
# Usage: scripts/debloat.sh apply [--list FILE]... [--animations]
#        scripts/debloat.sh undo
#        scripts/debloat.sh status [--list FILE]...
#
#   apply         disable the packages in the package list(s)
#   --list FILE   package list to use (repeatable). Default: scripts/packages/<brand>-<ui>.txt,
#                 where <brand> is the TV's ro.product.brand (lowercase) and <ui> is
#                 google-tv or android-tv (e.g. tcl-google-tv.txt). See CONTRIBUTING.md to add one.
#   --animations  also set animation scales to 0.5x (snappier, but visibly changes the UI feel)
#   undo          re-enable everything this script changed on this TV and restore settings
#   status        show the current state of every listed package
#
# Changes are recorded per TV in state/<device>-<hash>.tsv (machine-readable, used by `undo`)
# and DEBLOAT-LOG.md (human-readable, with the exact command to undo each change by hand).
#
# Env: TV_ADDR (optional when exactly one TV is connected to adb)
set -euo pipefail

ANIMATION_SCALE="0.5"
ANIMATION_SETTINGS=(window_animation_scale transition_animation_scale animator_duration_scale)
LITE_LAUNCHER_HOME="com.litelauncher.tv/.HomeActivity"
GOOGLE_TV_LAUNCHER_PACKAGE="com.google.android.apps.tv.launcherx"
# Packages that provide or feed the stock HOME screen. They are only disabled when Light TV Launcher
# is installed, and HOME is verified afterwards (auto rollback), so the TV never loses its home.
# setupwraith is here because its RecoveryActivity claims HOME (priority 1) on Google TV.
HOME_PROVIDER_PACKAGES=(com.google.android.tvlauncher com.google.android.tvrecommendations
  "$GOOGLE_TV_LAUNCHER_PACKAGE" com.google.android.tungsten.setupwraith)

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
human_log="$project_dir/DEBLOAT-LOG.md"
package_lists=()
should_set_animations=false
state_file=""
device_id=""

# shellcheck source=lib/tv.sh
source "$(dirname "$0")/lib/tv.sh"
now() { date '+%Y-%m-%d %H:%M:%S'; }


# Identify the TV by model + a hash of its serial, so state files from different TVs never mix
# (the IP isn't stable, and the raw serial number shouldn't end up in file names)
resolve_device() {
  local device_name serial_number
  device_name="$(tv_shell getprop ro.product.device)"
  serial_number="$(tv_shell getprop ro.boot.serialno)"
  [[ -n "$device_name" && -n "$serial_number" ]] || { echo "ERROR: could not read device id from TV" >&2; exit 1; }
  device_id="$device_name-$(printf %s "$serial_number" | shasum | cut -c1-8)"
  state_file="$project_dir/state/$device_id.tsv"
  mkdir -p "$(dirname "$state_file")"
}

resolve_package_lists() {
  if (( ${#package_lists[@]} == 0 )); then
    local brand_name ui_type default_list
    brand_name="$(tv_shell getprop ro.product.brand | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')"
    if tv_shell pm list packages | grep -qx "package:$GOOGLE_TV_LAUNCHER_PACKAGE"; then
      ui_type="google-tv"
    else
      ui_type="android-tv"
    fi
    default_list="$project_dir/scripts/packages/$brand_name-$ui_type.txt"
    if [[ ! -f "$default_list" ]]; then
      echo "ERROR: no package list for this TV yet (looked for scripts/packages/$brand_name-$ui_type.txt)." >&2
      echo "Available lists:" >&2
      ls "$project_dir/scripts/packages/" | sed 's/^/  /' >&2
      echo "Pass one with --list, or add a list for your TV: see CONTRIBUTING.md" >&2
      exit 1
    fi
    package_lists=("$default_list")
  fi
  local list_file
  for list_file in "${package_lists[@]}"; do
    [[ -f "$list_file" ]] || { echo "ERROR: package list not found: $list_file" >&2; exit 1; }
    echo "TV: $device_id ($TV_ADDR)   list: ${list_file#"$project_dir"/}"
  done
  echo ""
}

listed_packages() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "${package_lists[@]}" | awk '{print $1}'; }

package_state() {
  local package_name="$1"
  if ! tv_shell pm list packages | grep -qx "package:$package_name"; then echo "not-installed"
  elif tv_shell pm list packages -d | grep -qx "package:$package_name"; then echo "disabled"
  else echo "enabled"
  fi
}

is_home_provider_package() {
  local package_name="$1" stock_package
  for stock_package in "${HOME_PROVIDER_PACKAGES[@]}"; do
    [[ "$package_name" == "$stock_package" ]] && return 0
  done
  return 1
}

current_home() {
  tv_shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -1
}

lite_launcher_installed() {
  tv_shell pm list packages -e | grep -qx "package:${LITE_LAUNCHER_HOME%%/*}"
}

# Called after the stock launcher is disabled: if HOME doesn't land on Light TV Launcher,
# put the stock launcher back immediately rather than leave the TV without a home screen
verify_home_or_roll_back() {
  local disabled_home_providers=("$@") home_activity package_name
  home_activity="$(current_home)"
  if [[ "$home_activity" == "$LITE_LAUNCHER_HOME" ]]; then
    tv_shell input keyevent KEYCODE_HOME
    echo "OK    HOME now opens Light TV Launcher"
    return 0
  fi
  echo "ERROR: HOME resolves to '$home_activity' after disabling the stock launcher; rolling back" >&2
  for package_name in "${disabled_home_providers[@]}"; do
    tv_shell pm enable "$package_name" >/dev/null
    printf '%s\tpackage-rolled-back\t%s\tenabled\n' "$(now)" "$package_name" >> "$state_file"
    echo "| Rolled back \`$package_name\` (HOME did not resolve to Light TV Launcher) | — |" >> "$human_log"
    echo "ON    $package_name (rolled back)"
  done
  return 1
}

apply_changes() {
  local changed_count=0 skipped_count=0
  local disabled_home_providers=()
  {
    echo ""
    echo "## Apply — $(now) — $device_id"
    echo ""
    echo "| Change | Undo command |"
    echo "|---|---|"
  } >> "$human_log"

  while read -r package_name; do
    if is_home_provider_package "$package_name" && ! lite_launcher_installed; then
      echo "SKIP  $package_name (Light TV Launcher not installed — run scripts/build.sh --install first)"
      skipped_count=$((skipped_count + 1))
      continue
    fi
    local state
    state="$(package_state "$package_name")"
    if [[ "$state" != "enabled" ]]; then
      echo "SKIP  $package_name ($state)"
      skipped_count=$((skipped_count + 1))
      continue
    fi
    if tv_shell pm disable-user --user 0 "$package_name" | grep -q "new state: disabled-user"; then
      printf '%s\tpackage\t%s\tenabled\n' "$(now)" "$package_name" >> "$state_file"
      echo "| Disabled \`$package_name\` | \`adb shell pm enable $package_name\` |" >> "$human_log"
      echo "OFF   $package_name"
      changed_count=$((changed_count + 1))
      is_home_provider_package "$package_name" && disabled_home_providers+=("$package_name")
    else
      echo "FAIL  $package_name (pm disable-user did not report disabled-user)" >&2
    fi
  done < <(listed_packages)

  if (( ${#disabled_home_providers[@]} > 0 )); then
    verify_home_or_roll_back "${disabled_home_providers[@]}" || true
  fi

  local setting_name previous_value
  for setting_name in "${ANIMATION_SETTINGS[@]}"; do
    [[ "$should_set_animations" == true ]] || break
    previous_value="$(tv_shell settings get global "$setting_name")"
    [[ "$previous_value" == "$ANIMATION_SCALE" ]] && continue
    tv_shell settings put global "$setting_name" "$ANIMATION_SCALE"
    printf '%s\tsetting\t%s\t%s\n' "$(now)" "$setting_name" "$previous_value" >> "$state_file"
    if [[ "$previous_value" == "null" ]]; then
      echo "| \`$setting_name\` null → $ANIMATION_SCALE | \`adb shell settings delete global $setting_name\` |" >> "$human_log"
    else
      echo "| \`$setting_name\` $previous_value → $ANIMATION_SCALE | \`adb shell settings put global $setting_name $previous_value\` |" >> "$human_log"
    fi
    echo "SET   $setting_name: $previous_value -> $ANIMATION_SCALE"
    changed_count=$((changed_count + 1))
  done

  echo ""
  echo "Changed $changed_count, skipped $skipped_count. Undo with: scripts/debloat.sh undo"
}

undo_changes() {
  if [[ ! -s "$state_file" ]]; then
    echo "Nothing to undo ($state_file is empty)"
    return 0
  fi
  {
    echo ""
    echo "## Undo — $(now) — $device_id"
    echo ""
  } >> "$human_log"

  # Reverse order so the earliest recorded value of a setting is the one restored last
  local restored_count=0 failed_count=0
  while IFS=$'\t' read -r _timestamp change_kind change_name previous_value; do
    case "$change_kind" in
      package-rolled-back)
        ;;  # already re-enabled at apply time
      package)
        if tv_shell pm enable "$change_name" | grep -q "new state: enabled"; then
          echo "ON    $change_name"; echo "- Re-enabled \`$change_name\`" >> "$human_log"
          restored_count=$((restored_count + 1))
        else
          echo "FAIL  could not re-enable $change_name" >&2; failed_count=$((failed_count + 1))
        fi
        ;;
      setting)
        if [[ "$previous_value" == "null" ]]; then
          tv_shell settings delete global "$change_name" >/dev/null
        else
          tv_shell settings put global "$change_name" "$previous_value"
        fi
        echo "SET   $change_name -> $previous_value"; echo "- Restored \`$change_name\` to $previous_value" >> "$human_log"
        restored_count=$((restored_count + 1))
        ;;
      *)
        echo "WARN  unknown change kind '$change_kind' in $state_file" >&2
        ;;
    esac
  done < <(tail -r "$state_file")

  if (( failed_count == 0 )); then
    mv "$state_file" "$state_file.undone-$(date +%Y%m%d-%H%M%S)"
  fi
  echo ""
  echo "Restored $restored_count, failed $failed_count."
}

show_status() {
  printf '%-42s %s\n' PACKAGE STATE
  while read -r package_name; do
    printf '%-42s %s\n' "$package_name" "$(package_state "$package_name")"
  done < <(listed_packages)
  echo ""
  echo "Default home: $(current_home)"
  local setting_name
  for setting_name in "${ANIMATION_SETTINGS[@]}"; do
    echo "$setting_name = $(tv_shell settings get global "$setting_name")"
  done
}

command_name="${1:-}"
shift || true
while (( $# > 0 )); do
  case "$1" in
    --list)       package_lists+=("${2:?--list needs a file}"); shift 2 ;;
    --animations) should_set_animations=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

resolve_tv_addr
resolve_device
case "$command_name" in
  apply)  resolve_package_lists; apply_changes ;;
  undo)   undo_changes ;;
  status) resolve_package_lists; show_status ;;
  *) echo "Usage: $0 apply [--list FILE]... [--animations] | undo | status [--list FILE]..." >&2; exit 2 ;;
esac
