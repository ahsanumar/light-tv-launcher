package com.litelauncher.tv;

import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.drawable.Drawable;

/** One launchable tile on the home grid. */
final class AppEntry {
    final String label;
    final String packageName;
    final Intent launchIntent;
    final ActivityInfo activityInfo;
    /** Leanback (TV-native) apps ship a 16:9 banner; phone-style apps only have a square icon. */
    final boolean isLeanbackApp;
    final int launchCount;

    /** Written once by the artwork loader thread, read on the main thread after a Handler post. */
    Drawable artwork;
    boolean artworkIsBanner;

    AppEntry(String label, String packageName, Intent launchIntent, ActivityInfo activityInfo,
             boolean isLeanbackApp, int launchCount) {
        this.label = label;
        this.packageName = packageName;
        this.launchIntent = launchIntent;
        this.activityInfo = activityInfo;
        this.isLeanbackApp = isLeanbackApp;
        this.launchCount = launchCount;
    }
}
