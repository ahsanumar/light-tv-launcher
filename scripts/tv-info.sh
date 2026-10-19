#!/usr/bin/env bash
# Print a privacy-safe Markdown report about the connected TV, for adding support for a new
# brand/model. Paste the output into a "New TV support" issue or a pull request.
#
# Included: brand/model, chipset, Android version, RAM, display, home screen candidates, the
#           firmware's system packages, and which system processes use the most memory.
# Excluded on purpose: serial numbers, MAC/IP addresses, Wi-Fi names, accounts, and apps you
#           installed yourself (only firmware/system packages are listed).
#
# Usage: scripts/tv-info.sh > my-tv.md
# Env: TV_ADDR (optional when exactly one TV is connected to adb)
set -euo pipefail

# shellcheck source=lib/tv.sh
source "$(dirname "$0")/lib/tv.sh"
resolve_tv_addr

prop() { tv_shell getprop "$1"; }

google_tv_launcher="com.google.android.apps.tv.launcherx"
system_packages="$(tv_shell pm list packages -s | sed 's/^package://' | sort)"
if grep -qx "$google_tv_launcher" <<<"$system_packages"; then ui_type="google-tv"; else ui_type="android-tv"; fi
brand_name="$(prop ro.product.brand | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')"

echo "## TV report"
echo ""
echo "| Property | Value |"
echo "|---|---|"
echo "| Brand / manufacturer | $(prop ro.product.brand) / $(prop ro.product.manufacturer) |"
echo "| Model / device / board | $(prop ro.product.model) / $(prop ro.product.device) / $(prop ro.product.board) |"
echo "| Chipset (platform) | $(prop ro.board.platform) |"
echo "| Android | $(prop ro.build.version.release) (SDK $(prop ro.build.version.sdk)), security patch $(prop ro.build.version.security_patch) |"
echo "| Build | $(prop ro.build.display.id), type $(prop ro.build.type) |"
echo "| CPU ABIs | $(prop ro.product.cpu.abilist) |"
echo "| CPU cores / max freq | $(tv_shell 'grep -c ^processor /proc/cpuinfo') / $(tv_shell 'cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo ?') kHz |"
echo "| RAM | $(tv_shell "awk '/MemTotal/ {printf \"%d MB\", \$2/1024}' /proc/meminfo") |"
echo "| Display | $(tv_shell wm size | tail -1 | sed 's/.*: //'), density $(tv_shell wm density | tail -1 | sed 's/.*: //') |"
echo "| Verified boot / bootloader locked | $(prop ro.boot.verifiedbootstate) / $(prop ro.boot.flash.locked) |"
echo "| UI type | $ui_type |"
echo "| Expected package list | \`scripts/packages/$brand_name-$ui_type.txt\` |"
echo ""

echo "### Home screen candidates (priority order)"
echo ""
echo '```'
# --brief prints each candidate as a "priority=N ..." line followed by its component line
tv_shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME \
  | grep -E "priority=|/" | sed -E 's/^ +//; s/ preferredOrder.*//' | paste -d' ' - -
echo '```'
echo ""

echo "### Top system processes by memory (RSS, MB)"
echo ""
echo '```'
# Only processes whose package is a firmware/system package, so personal apps never appear
tv_shell ps -A -o RSS,NAME | tail -n +2 | sort -rn | while read -r rss_kb process_name; do
  package_name="${process_name%%:*}"
  if grep -qx "$package_name" <<<"$system_packages"; then
    printf '%6d  %s\n' "$((rss_kb / 1024))" "$process_name"
  fi
done | head -25
echo '```'
echo ""

echo "<details><summary>System packages ($(wc -l <<<"$system_packages" | tr -d ' ')), disabled ones marked</summary>"
echo ""
echo '```'
disabled_packages="$(tv_shell pm list packages -s -d | sed 's/^package://')"
while read -r package_name; do
  if grep -qx "$package_name" <<<"$disabled_packages"; then
    echo "$package_name  [disabled]"
  else
    echo "$package_name"
  fi
done <<<"$system_packages"
echo '```'
echo ""
echo "</details>"
