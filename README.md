# TCL TV Lite Launcher

A tiny, dependency-free Android TV home screen plus a reversible debloat script for a
TCL BeyondTV (Realtek RTD2851, 2 GB RAM, Android 11). The goal is more free RAM and
snappier navigation on slow TV hardware, without rooting or flashing anything.

Measured on the TCL BeyondTV after a fresh reboot: home screen cold start 1,351 → 600 ms
(−56%), home screen memory 86 → 18 MB, app launches 13–15% faster.

## TV support

The launcher itself is plain Android and should run on any Android TV with Android 9 or
newer. The debloat package list and the stock-launcher swap were written for TCL firmware,
so they are the part most likely to need changes on other TVs.

| TV / platform | Android | Lite Launcher | `debloat.sh` | Status |
|---|---|---|---|---|
| TCL BeyondTV platform (Realtek RTD2851; `ro.product.model` reports `BeyondTV`) | 9–11 | ✅ Works | ✅ Works | **Tested** on Android 11 |
| Other TCL Android TV models (non-Google TV UI) | 9–11 | 🟡 Should work | 🟡 Partly. Missing packages are skipped; TCL package names vary by firmware | Untested |
| TCL Google TV models (newer UI) | 10+ | 🟡 Should work | ❌ Stock launcher is a different package (`com.google.android.apps.tv.launcherx`), so HOME won't switch | Untested |
| Other Android TV brands (Sony, Philips, Hisense, Sharp, Xiaomi, Nvidia Shield, Chromecast with Google TV) | 9+ | 🟡 Should work | ❌ Package list is TCL-specific; build your own list | Untested |
| Amazon Fire TV (Fire OS) | — | ❓ Unknown | ❌ | Untested; Fire OS restricts replacing the home screen |
| Android TV 8.x and older | ≤ 8 | ❌ Not supported (`minSdk` 28) | ❌ | — |
| Roku TV, LG webOS, Samsung Tizen, Vidaa | — | ❌ Not Android | ❌ | — |

Tested on another TV? Open an issue or PR with the model, Android version and what worked.

To check your TV over ADB:

```bash
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
```

The last command shows your current home screen. If it isn't `com.google.android.tvlauncher`,
add your stock launcher's package to `STOCK_LAUNCHER_PACKAGES` in `scripts/debloat.sh` and to
`scripts/debloat-packages.txt`.

## Why not a custom ROM?

The TV's bootloader is locked with verified boot enforced (`verifiedbootstate=green`), OEM
unlock is disallowed, the firmware isn't Treble-enabled (so no GSI), and the picture/input
stack relies on proprietary TCL/Realtek services. No custom ROM exists for this platform.
Disabling bloat over ADB gets most of the benefit with none of the brick risk.

## What's here

| Path | What it does |
|---|---|
| `launcher/` | Lite Launcher source: plain Android framework (no AndroidX/Kotlin/Compose), ~28 KB APK |
| `scripts/build.sh` | Builds the APK with `aapt2` + `javac` + `d8` (no Gradle). `--install` installs it and requests the HOME role |
| `scripts/debloat.sh` | `apply` / `undo` / `status` — disables packages in `debloat-packages.txt`, sets animations to 0.5× |
| `scripts/debloat-packages.txt` | The package list, one line per package with what you lose. Comment a line out to keep it |
| `scripts/measure.sh` | Measures cold boot, free RAM, process count and app cold-start times into `measurements/` |
| `scripts/compare.sh` | Prints a before/after table from two `measurements/` files |

Generated per TV and git-ignored (they list your installed apps, screenshots and timestamps):

| Path | What it holds |
|---|---|
| `measurements/` | Measurement results, process lists, screenshots |
| `DEBLOAT-LOG.md` | Human-readable log of every change, with the exact undo command for each |
| `state/debloat-applied.tsv` | Machine-readable change log used by `debloat.sh undo` — keep it, or undo can't run |

## Requirements

- `adb` (Homebrew `android-platform-tools`), TV reachable at `192.168.0.101:5555` with network debugging authorized
- Android SDK build-tools 36 + platform `android-36` (Homebrew `android-commandlinetools`)
- JDK 17 (Homebrew `openjdk@17`)

Override paths/addresses with `TV_ADDR`, `ANDROID_SDK`, `JAVA_HOME`.

## Usage

```bash
adb connect 192.168.0.101:5555
scripts/measure.sh before --reboot      # baseline (reboots the TV, ~7 min)
scripts/build.sh --install              # build, install, set Lite Launcher as home
scripts/debloat.sh apply                # disable bloat + 0.5x animations
scripts/measure.sh after --reboot       # compare with measurements/before.txt
```

## Undo

```bash
scripts/debloat.sh undo                                     # re-enable everything, restore animations
adb shell cmd package set-home-activity com.google.android.tvlauncher/.MainActivity
adb uninstall com.litelauncher.tv                           # optional: remove Lite Launcher
```

Nothing here modifies system partitions — packages are only disabled for user 0. If the TV ever
lands on a black screen, ADB still works: run `scripts/debloat.sh undo`. A factory reset also
re-enables every disabled package.

## Why the stock launcher has to be disabled

The stock launcher's HOME intent filter declares `priority=2`. When HOME candidates have
different priorities Android picks the highest one and never consults the user's preferred
home, and third-party apps can't declare a priority above 0. So `set-home-activity` / the HOME
role alone aren't enough: `debloat.sh apply` disables `com.google.android.tvlauncher`, then
verifies HOME resolves to Lite Launcher and automatically re-enables the stock launcher if not.

## Launcher controls

- D-pad to move, OK to open, long-press OK for the app's info page (force stop / uninstall)
- HOME while on the home screen jumps back to the first tile
- Tiles are sorted by how often you open them, then alphabetically (re-sorted when apps change)
- TCL's factory service menu, setup wizards and other internal entries are hidden
  (`HIDDEN_PACKAGES` in `AppListLoader.java`)

## Notes

- Disabling `com.tcl.versionUpdateApp` stops TCL firmware updates. Re-enable it before updating:
  `adb shell pm enable com.tcl.versionUpdateApp`
- Disabling `com.google.android.katniss` disables voice search and the remote's mic button.
- A factory reset or major firmware update may re-enable disabled packages; just run `apply` again.
