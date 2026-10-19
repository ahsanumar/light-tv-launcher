# Contributing to Light TV Launcher

Thanks for helping! The most valuable contribution is **support for another TV**: a tested
package list for a brand/model, plus a report of what worked. Launcher improvements and bug
fixes are welcome too.

## Ground rules

- **Reversible only.** Packages are disabled with `pm disable-user --user 0`, never uninstalled.
  No root, no flashing, no changes to system partitions. Every change must be undoable with
  `scripts/debloat.sh undo`.
- **Never leave a TV without a home screen.** Anything that provides HOME goes through the
  `HOME_PROVIDER_PACKAGES` check in `scripts/debloat.sh` (verify + automatic rollback).
- **Privacy.** Don't commit `measurements/`, `state/`, `DEBLOAT-LOG.md` or screenshots that show
  personal content (they're git-ignored). Use `scripts/tv-info.sh` for reports: it leaves out
  serial numbers, network details, accounts and user-installed apps.
- **The launcher stays dependency-free.** Plain Android framework (no AndroidX, Kotlin or
  Compose), `minSdk` 28. That's what keeps it at ~50 MB of RAM instead of hundreds.

## Setup

- `adb` (e.g. Homebrew `android-platform-tools`)
- Android SDK build-tools 36 + platform `android-36` (e.g. Homebrew `android-commandlinetools`)
- JDK 17 (e.g. Homebrew `openjdk@17`)

On the TV: **Settings → Device Preferences → About → Build**, press OK 7 times, then turn on
**USB debugging** (and **Network debugging** if listed) in **Developer options**.

```bash
adb connect <tv-ip>:5555        # accept the "Allow debugging?" prompt on the TV
```

All scripts use the only connected TV automatically; set `TV_ADDR=<ip>:5555` if several are connected.

## Adding support for a new TV

### 1. Report the TV

```bash
scripts/tv-info.sh > my-tv.md
```

Open a **New TV support** issue and paste the report. It shows the chipset, RAM, UI type
(Android TV or Google TV), home screen candidates and priorities, the firmware's system
packages and which ones use the most memory. It also names the package list file the scripts
expect: `scripts/packages/<brand>-<ui>.txt`, where `<brand>` is `ro.product.brand` in
lowercase and `<ui>` is `android-tv` or `google-tv`.

### 2. Write the package list

Copy the closest existing list in `scripts/packages/` and edit it. One package per line, with a
comment saying **what it is and what the user loses**:

```
com.example.promo          # Vendor promo notifications
com.example.voiceagent     # Vendor voice assistant (~40 MB). Lose: vendor voice commands
```

Put features some people use under a commented-out "Optional" section. Never list:

- Live TV / HDMI input services, remote-control and key-mapping services
- Picture/sound settings apps, the system UI, settings providers
- Google Play Services, Google Services Framework, the Play Store
- Anything you can't identify. If unsure, leave it out and ask in the issue.

To replace the stock home screen, keep that in a separate add-on list (see
`google-tv-home-swap.txt`) and add the packages to `HOME_PROVIDER_PACKAGES` in
`scripts/debloat.sh`. Check the priorities in the report: everything with a HOME priority above 0
must be disabled for Light TV Launcher to take over.

### 3. Test it

```bash
scripts/measure.sh before --reboot   # optional but encouraged: baseline numbers
scripts/debloat.sh status            # every package should be found ("enabled")
scripts/debloat.sh apply
adb reboot                           # then reconnect
scripts/debloat.sh status            # still disabled? some firmware re-enables packages at boot
scripts/measure.sh after --reboot    # optional
scripts/compare.sh before after
scripts/debloat.sh undo              # confirm undo restores everything
```

Then check by hand: HOME, Settings, the remote's settings/input buttons, HDMI inputs, voice
search (if kept), and launching a few apps and returning with HOME.

If the firmware re-enables a package after reboot, remove it from the list and say why in a
comment (see `tcl-google-tv.txt`). Same for persistent system apps that run even when disabled.

### 4. Open a pull request

Include the new list, a row in the README's **TV support** table, and your before/after
numbers if you measured them.

## Launcher changes

```bash
scripts/build.sh --install           # build, install, and request the HOME role
```

- Android TV models use the grid (`HomeActivity` + `AppGridAdapter`); Google TV models use
  `GoogleTvHome`. If you change shared code, test both layouts if you can.
- Brand-specific launcher entries that must not be one tap away (factory/service menus, setup
  wizards) go in `HIDDEN_PACKAGES` in `AppListLoader.java`, with a comment.
- The package name stays `com.litelauncher.tv` so existing installs keep their HOME setting.

## Style

- Meaningful names; no single-letter variables except loop indices.
- Handle errors explicitly. Scripts use `set -euo pipefail` and say what failed and how to fix it.
- A one-line comment for any non-obvious decision (especially firmware quirks).

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
