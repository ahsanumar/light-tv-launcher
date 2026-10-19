# Light TV Launcher

A tiny, dependency-free home screen for Android TV and Google TV, plus reversible ADB scripts
that strip out bloat on slow TVs. No root, no flashing, and everything can be undone.

Most budget smart TVs ship with 2 GB of RAM, and the stock home screen plus vendor extras eat a
large share of it. Light TV Launcher replaces the home screen with one that uses a fraction of
the memory, and the scripts disable vendor bloat one documented package at a time.

The launcher picks its layout from the TV it runs on:

- **Android TV models** get a compact grid of app banners, most-used first.
- **Google TV models** get a Google TV-style layout: a pill top bar (Search, Home/Apps,
  Inputs, Settings, clock), a "Your apps" row of round icons, and all apps as banners.

## Results

Measured after a fresh reboot, each compared with the stock setup:

| | TCL BeyondTV (Android TV) | TCL G07 (Google TV) |
|---|---|---|
| Home screen memory (PSS) | 86 → 18 MB | 136 → 54 MB (plus ~150 MB of Google TV background services gone) |
| Home screen cold start | 1,351 → 600 ms (−56%) | 602 → 484 ms (−20%) |
| Available RAM after boot | no clear change | 781 → 907 MB (+16%) |
| Cold boot | 42.3 → 41.6 s | 28.2 → 22.5 s (−20%) |
| App cold starts | 13–15% faster | unchanged (YouTube 828 → 813 ms) |

## TV support

The launcher is plain Android and should run on any Android TV with Android 9 or newer.
Package lists are per brand and UI type, so that's where support for new TVs comes from.
**Help add yours:** see [CONTRIBUTING.md](CONTRIBUTING.md).

| TV / platform | Android | Light TV Launcher | Package list | Status |
|---|---|---|---|---|
| TCL Android TV, BeyondTV platform (Realtek RTD2851) | 9–11 | ✅ Works (grid layout) | ✅ `tcl-android-tv.txt` (includes the launcher swap) | **Tested** on Android 11 |
| TCL Google TV, board G07 (Realtek RTD2851A, 2022) | 11 | ✅ Works (Google TV layout) | ✅ `tcl-google-tv.txt` (keeps Google TV), plus `google-tv-home-swap.txt` to replace it | **Tested** on Android 11 |
| Other TCL Android TV / Google TV models | 9+ | 🟡 Should work | 🟡 The TCL lists likely apply; missing packages are skipped | Untested |
| Other Android TV / Google TV brands (Sony, Philips, Hisense, Sharp, Xiaomi, Nvidia Shield, Chromecast with Google TV) | 9+ | 🟡 Should work | ❌ No list yet. [Add one](CONTRIBUTING.md#adding-support-for-a-new-tv) | Untested |
| Amazon Fire TV (Fire OS) | — | ❓ Unknown | ❌ | Untested; Fire OS restricts replacing the home screen |
| Android TV 8.x and older | ≤ 8 | ❌ Not supported (`minSdk` 28) | ❌ | — |
| Roku TV, LG webOS, Samsung Tizen, Vidaa | — | ❌ Not Android | ❌ | — |

Tested on another TV? [Open a New TV support issue](https://github.com/ahsanumar/light-tv-launcher/issues/new/choose)
with the output of `scripts/tv-info.sh`.

## Quick start

Requirements: `adb`, Android SDK build-tools 36 + platform `android-36`, JDK 17 (all available
from Homebrew: `android-platform-tools`, `android-commandlinetools`, `openjdk@17`).
Override paths with `ANDROID_SDK` and `JAVA_HOME`.

On the TV: **Settings → Device Preferences → About → Build**, press OK 7 times, then turn on
**USB debugging** in **Developer options**.

```bash
adb connect <tv-ip>:5555                 # accept the "Allow debugging?" prompt on the TV
scripts/tv-info.sh                       # what TV is this, and is there a package list for it?
scripts/measure.sh before --reboot       # optional baseline (reboots the TV, ~7 min)
scripts/build.sh --install               # build and install Light TV Launcher
scripts/debloat.sh status                # shows which package list it picked
scripts/debloat.sh apply --animations    # disable bloat (+ 0.5x animations)
scripts/measure.sh after --reboot        # optional
scripts/compare.sh before after
```

The scripts use the only connected TV automatically; set `TV_ADDR=<ip>:5555` if several are connected.

On Google TV, the default list keeps the Google TV home screen. To replace it:

```bash
scripts/debloat.sh apply --list scripts/packages/tcl-google-tv.txt \
                         --list scripts/packages/google-tv-home-swap.txt --animations
```

What you lose with the Google TV swap: content rows (YouTube/Netflix rows, Continue watching,
"For you"), profiles, and the Google setup wizard. Reading other apps' content rows needs
`ACCESS_ALL_EPG_DATA`, a `signature|privileged` permission no third-party launcher can hold.
Search (Google Assistant), Settings, Accounts, Inputs and all apps keep working.

## Undo

```bash
scripts/debloat.sh undo              # re-enable everything on this TV (incl. the stock home), restore animations
adb uninstall com.litelauncher.tv     # optional: remove Light TV Launcher
```

Nothing here modifies system partitions. Packages are only disabled for user 0. If the TV ever
lands on a black screen, ADB still works: run `scripts/debloat.sh undo`. A factory reset also
re-enables every disabled package.

## What's here

| Path | What it does |
|---|---|
| `launcher/` | Launcher source: plain Android framework (no AndroidX/Kotlin/Compose), ~44 KB APK |
| `scripts/build.sh` | Builds the APK with `aapt2` + `javac` + `d8` (no Gradle). `--install` installs it and requests the HOME role |
| `scripts/debloat.sh` | `apply` / `undo` / `status`: disables the packages in a list; `--animations` also sets animations to 0.5× |
| `scripts/packages/` | Package lists, named `<brand>-<android-tv\|google-tv>.txt`, plus add-on lists such as `google-tv-home-swap.txt` |
| `scripts/tv-info.sh` | Privacy-safe TV report for issues and new package lists |
| `scripts/measure.sh` | Measures cold boot, free RAM, process count and app cold-start times into `measurements/` |
| `scripts/compare.sh` | Prints a before/after table from two `measurements/` files |

Generated per TV and git-ignored (they list your installed apps, screenshots and timestamps):

| Path | What it holds |
|---|---|
| `measurements/` | Measurement results, process lists, screenshots |
| `DEBLOAT-LOG.md` | Human-readable log of every change, with the exact undo command for each |
| `state/<device>-<hash>.tsv` | Per-TV change log used by `debloat.sh undo`. Keep it, or undo can't run |

## Why the stock launcher has to be disabled

The stock launcher's HOME intent filter declares `priority=2`. When HOME candidates have
different priorities Android picks the highest one and never consults the user's preferred
home, and third-party apps can't declare a priority above 0. So `set-home-activity` and the HOME
role alone aren't enough: `debloat.sh apply` disables the stock launcher, then verifies HOME
resolves to Light TV Launcher and automatically re-enables the stock launcher if not.

Google TV adds a second obstacle: Google's setup app (`setupwraith`) has a `RecoveryActivity`
with HOME `priority=1` that takes over when the launcher is missing. ADB can't disable a single
component of a system app ("Shell cannot change component state"), so the whole setup app is
disabled by `google-tv-home-swap.txt`. Tested: HOME stays on Light TV Launcher across reboots.

## Why not a custom ROM?

On the TVs tested so far the bootloader is locked with verified boot enforced
(`verifiedbootstate=green`), OEM unlock is disallowed, the firmware isn't Treble-enabled (so no
GSI), and the picture/input stack relies on proprietary vendor services. Disabling bloat over
ADB gets most of the benefit with none of the brick risk.

## Launcher controls

- D-pad to move, OK to open, long-press OK for the app's info page (force stop / uninstall)
- HOME while on the home screen jumps back to the first app
- Apps are sorted by how often you open them, then alphabetically
- Vendor factory/service menus, setup wizards and other internal entries are hidden
  (`HIDDEN_PACKAGES` in `AppListLoader.java`)
- Google TV layout: Search opens Google Assistant search, the inputs button opens the TV/HDMI
  app, the gear opens Settings, "Apps" jumps to the all-apps grid. App names show on focus

## Notes

- Some TCL lists disable the firmware updater (`com.tcl.versionUpdateApp`). Re-enable it before
  updating: `adb shell pm enable com.tcl.versionUpdateApp`
- Disabling `com.google.android.katniss` disables voice search and the remote's mic button.
- A factory reset or major firmware update may re-enable disabled packages; just run `apply` again.

## Contributing

New TVs, package lists, bug reports and launcher improvements are welcome. Start with
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
