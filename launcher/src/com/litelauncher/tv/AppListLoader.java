package com.litelauncher.tv;

import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.drawable.Drawable;
import android.provider.Settings;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Builds the list of launchable apps and loads their artwork. */
final class AppListLoader {
    private static final String TV_SETTINGS_PACKAGE = "com.android.tv.settings";

    /**
     * TCL system entries that declare a launcher activity but must not be one tap away:
     * the factory service menu can mis-set panel calibration, and the setup wizards can
     * restart first-run setup.
     */
    private static final Set<String> HIDDEN_PACKAGES = new HashSet<>(Arrays.asList(
            "com.tcl.factory.view",            // factory service menu
            "com.tcl.initsetup",               // TCL first-run setup ("Initial Setup")
            "com.tcl.tv.tclhome_master",       // TCL setup/startup flow ("Initial Setup")
            "com.tcl.tv.tclhome_passive",      // TCL passive home used during setup
            "com.tcl.useragreement",           // terms-of-service screen
            "com.tcl.micmanager",              // mic permission manager; mislabeled "Initial Setup"
            "com.tcl.partnercustomizer"));     // partner config shim, no user UI

    private AppListLoader() {}

    /** Fast (labels only); safe to call on the main thread. Artwork is loaded separately. */
    static List<AppEntry> loadEntries(PackageManager packageManager, String ownPackageName,
                                      SharedPreferences launchCounts, String settingsLabel) {
        List<AppEntry> entries = new ArrayList<>();
        // Pre-seeding "seen" with our own and hidden packages excludes them from both queries
        Set<String> seenPackages = new HashSet<>(HIDDEN_PACKAGES);
        seenPackages.add(ownPackageName);

        addMatchingApps(packageManager, Intent.CATEGORY_LEANBACK_LAUNCHER, true,
                seenPackages, launchCounts, entries);
        // Sideloaded phone apps often only declare LAUNCHER; include them so they stay reachable
        addMatchingApps(packageManager, Intent.CATEGORY_LAUNCHER, false,
                seenPackages, launchCounts, entries);

        if (!seenPackages.contains(TV_SETTINGS_PACKAGE)) {
            addSettingsEntry(packageManager, settingsLabel, launchCounts, entries);
        }

        entries.sort(Comparator
                .comparingInt((AppEntry entry) -> entry.launchCount).reversed()
                .thenComparing(entry -> entry.label, String.CASE_INSENSITIVE_ORDER));
        return entries;
    }

    private static void addMatchingApps(PackageManager packageManager, String category,
                                        boolean isLeanbackCategory, Set<String> seenPackages,
                                        SharedPreferences launchCounts, List<AppEntry> entries) {
        Intent query = new Intent(Intent.ACTION_MAIN).addCategory(category);
        for (ResolveInfo resolveInfo : packageManager.queryIntentActivities(query, 0)) {
            ActivityInfo activityInfo = resolveInfo.activityInfo;
            if (!seenPackages.add(activityInfo.packageName)) {
                continue;
            }
            Intent launchIntent = new Intent(Intent.ACTION_MAIN)
                    .addCategory(category)
                    .setClassName(activityInfo.packageName, activityInfo.name)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            entries.add(new AppEntry(
                    resolveInfo.loadLabel(packageManager).toString(),
                    activityInfo.packageName,
                    launchIntent,
                    activityInfo,
                    isLeanbackCategory,
                    launchCounts.getInt(activityInfo.packageName, 0)));
        }
    }

    private static void addSettingsEntry(PackageManager packageManager, String settingsLabel,
                                         SharedPreferences launchCounts, List<AppEntry> entries) {
        Intent settingsIntent = new Intent(Settings.ACTION_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        ResolveInfo resolveInfo = packageManager.resolveActivity(settingsIntent, 0);
        if (resolveInfo == null) {
            return;
        }
        entries.add(new AppEntry(settingsLabel, resolveInfo.activityInfo.packageName,
                settingsIntent, resolveInfo.activityInfo, false,
                launchCounts.getInt(resolveInfo.activityInfo.packageName, 0)));
    }

    /** Slow (decodes images); call from a background thread. */
    static void loadArtwork(PackageManager packageManager, AppEntry entry) {
        entry.icon = entry.activityInfo.loadIcon(packageManager);
        if (entry.isLeanbackApp) {
            Drawable banner = entry.activityInfo.loadBanner(packageManager);
            if (banner != null) {
                entry.artwork = banner;
                entry.artworkIsBanner = true;
                return;
            }
        }
        entry.artwork = entry.icon;
        entry.artworkIsBanner = false;
    }
}
