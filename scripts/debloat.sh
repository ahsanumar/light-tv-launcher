#!/usr/bin/env bash
# Reversibly debloat the TV and speed up UI animations. No root needed.
#
# Usage: scripts/debloat.sh apply    disable packages in debloat-packages.txt + set animations to 0.5x
#        scripts/debloat.sh undo     re-enable everything this script disabled + restore animation settings
#        scripts/debloat.sh status   show the current state of every listed package
#
# Every change is appended to state/debloat-applied.tsv (machine-readable, used by `undo`)
# and DEBLOAT-LOG.md (human-readable, with the exact command to undo each change by hand).
#
# Env: TV_ADDR (default 192.168.0.101:5555)
set -euo pipefail

TV_ADDR="${TV_ADDR:-192.168.0.101:5555}"
ANIMATION_SCALE="0.5"
ANIMATION_SETTINGS=(window_animation_scale transition_animation_scale animator_duration_scale)
LITE_LAUNCHER_HOME="com.litelauncher.tv/.HomeActivity"
# Disabling these without a replacement home screen leaves the TV on a black screen
STOCK_LAUNCHER_PACKAGES=(com.google.android.tvlauncher com.google.android.tvrecommendations)

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
package_list="$project_dir/scripts/debloat-packages.txt"
state_file="$project_dir/state/debloat-applied.tsv"
human_log="$project_dir/DEBLOAT-LOG.md"
mkdir -p "$(dirname "$state_file")"

# </dev/null: adb shell otherwise swallows the stdin of the `while read` loops below
tv_shell() { adb -s "$TV_ADDR" shell "$@" </dev/null | tr -d '\r'; }
now() { date '+%Y-%m-%d %H:%M:%S'; }

ensure_connected() {
  if ! adb -s "$TV_ADDR" get-state >/dev/null 2>&1; then
    adb connect "$TV_ADDR" >/dev/null 2>&1 || true
    adb -s "$TV_ADDR" get-state >/dev/null 2>&1 || { echo "ERROR: cannot reach TV at $TV_ADDR" >&2; exit 1; }
  fi
}

listed_packages() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$package_list" | awk '{print $1}'; }

package_state() {
  local package_name="$1"
  if ! tv_shell pm list packages | grep -qx "package:$package_name"; then echo "not-installed"
  elif tv_shell pm list packages -d | grep -qx "package:$package_name"; then echo "disabled"
  else echo "enabled"
  fi
}

is_stock_launcher_package() {
  local package_name="$1" stock_package
  for stock_package in "${STOCK_LAUNCHER_PACKAGES[@]}"; do
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

# Called after the stock launcher is disabled: if HOME doesn't land on Lite Launcher,
# put the stock launcher back immediately rather than leave the TV without a home screen
verify_home_or_roll_back() {
  local disabled_stock_packages=("$@") home_activity package_name
  home_activity="$(current_home)"
  if [[ "$home_activity" == "$LITE_LAUNCHER_HOME" ]]; then
    tv_shell input keyevent KEYCODE_HOME
    echo "OK    HOME now opens Lite Launcher"
    return 0
  fi
  echo "ERROR: HOME resolves to '$home_activity' after disabling the stock launcher; rolling back" >&2
  for package_name in "${disabled_stock_packages[@]}"; do
    tv_shell pm enable "$package_name" >/dev/null
    printf '%s\tpackage-rolled-back\t%s\tenabled\n' "$(now)" "$package_name" >> "$state_file"
    echo "| Rolled back \`$package_name\` (HOME did not resolve to Lite Launcher) | — |" >> "$human_log"
    echo "ON    $package_name (rolled back)"
  done
  return 1
}

apply_changes() {
  local changed_count=0 skipped_count=0
  local disabled_stock_packages=()
  {
    echo ""
    echo "## Apply — $(now)"
    echo ""
    echo "| Change | Undo command |"
    echo "|---|---|"
  } >> "$human_log"

  while read -r package_name; do
    if is_stock_launcher_package "$package_name" && ! lite_launcher_installed; then
      echo "SKIP  $package_name (Lite Launcher not installed — run scripts/build.sh --install first)"
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
      is_stock_launcher_package "$package_name" && disabled_stock_packages+=("$package_name")
    else
      echo "FAIL  $package_name (pm disable-user did not report disabled-user)" >&2
    fi
  done < <(listed_packages)

  if (( ${#disabled_stock_packages[@]} > 0 )); then
    verify_home_or_roll_back "${disabled_stock_packages[@]}" || true
  fi

  local setting_name previous_value
  for setting_name in "${ANIMATION_SETTINGS[@]}"; do
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
    echo "## Undo — $(now)"
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

ensure_connected
case "${1:-}" in
  apply)  apply_changes ;;
  undo)   undo_changes ;;
  status) show_status ;;
  *) echo "Usage: $0 apply|undo|status" >&2; exit 2 ;;
esac
