## What this changes

<!-- e.g. "Adds scripts/packages/sony-google-tv.txt for Sony Bravia 2023 (Android 12)" -->

## Tested on

<!-- Brand, model, Android version, UI type (Android TV / Google TV) -->

## Checklist

- [ ] Only reversible changes (`pm disable-user`), no uninstalls or system-partition changes
- [ ] Every listed package has a comment saying what it is and what the user loses
- [ ] `scripts/debloat.sh status` after a reboot shows the packages still disabled
- [ ] `scripts/debloat.sh undo` restores everything
- [ ] HOME, Settings, inputs and app launching still work
- [ ] README **TV support** table updated
- [ ] No personal data (measurements, state files, screenshots with personal content, account names)
