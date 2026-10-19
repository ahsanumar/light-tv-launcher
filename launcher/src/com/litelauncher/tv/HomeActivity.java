package com.litelauncher.tv;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;
import android.view.View;
import android.widget.AdapterView;
import android.widget.GridView;
import android.widget.Toast;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** The home screen: a clock and a grid of installed apps, most-used first. */
public final class HomeActivity extends Activity {
    private static final String TAG = "LiteLauncher";
    private static final String LAUNCH_COUNTS_PREFS = "launch_counts";
    /** 5 columns x 3 rows are visible at 1080p; refresh once those are ready, then once at the end. */
    private static final int FIRST_SCREEN_TILE_COUNT = 15;

    private final ExecutorService artworkExecutor = Executors.newSingleThreadExecutor();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private GridView appGrid;
    private AppGridAdapter appGridAdapter;
    private SharedPreferences launchCounts;
    private int reloadGeneration = 0;

    private final BroadcastReceiver packageChangeReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            reloadApps();
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_home);

        launchCounts = getSharedPreferences(LAUNCH_COUNTS_PREFS, MODE_PRIVATE);
        appGridAdapter = new AppGridAdapter(getLayoutInflater());
        appGrid = findViewById(R.id.app_grid);
        appGrid.setAdapter(appGridAdapter);
        appGrid.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            @Override
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
                appGridAdapter.onTileSelected(parent, position);
            }

            @Override
            public void onNothingSelected(AdapterView<?> parent) {
                appGridAdapter.onTileSelected(parent, -1);
            }
        });
        appGrid.setOnItemClickListener((parent, view, position, id) ->
                launchApp(appGridAdapter.getItem(position)));
        appGrid.setOnItemLongClickListener((parent, view, position, id) -> {
            openAppInfo(appGridAdapter.getItem(position));
            return true;
        });

        // PACKAGE_CHANGED also fires when the debloat script enables/disables a package
        IntentFilter packageFilter = new IntentFilter();
        packageFilter.addAction(Intent.ACTION_PACKAGE_ADDED);
        packageFilter.addAction(Intent.ACTION_PACKAGE_REMOVED);
        packageFilter.addAction(Intent.ACTION_PACKAGE_CHANGED);
        packageFilter.addAction(Intent.ACTION_PACKAGE_REPLACED);
        packageFilter.addDataScheme("package");
        registerReceiver(packageChangeReceiver, packageFilter);

        reloadApps();
        appGrid.requestFocus();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        // HOME pressed while already home: jump back to the first tile
        appGrid.setSelection(0);
        appGrid.requestFocus();
    }

    @SuppressWarnings("deprecation") // TV runs API 30; the replacement (OnBackInvokedCallback) is API 33+
    @Override
    public void onBackPressed() {
        // The home screen is the bottom of the stack; there is nothing to go back to
    }

    @Override
    protected void onDestroy() {
        unregisterReceiver(packageChangeReceiver);
        artworkExecutor.shutdownNow();
        super.onDestroy();
    }

    private void reloadApps() {
        PackageManager packageManager = getPackageManager();
        List<AppEntry> entries = AppListLoader.loadEntries(packageManager, getPackageName(),
                launchCounts, getString(R.string.settings_label));
        appGridAdapter.setEntries(entries);

        final int generation = ++reloadGeneration;
        artworkExecutor.execute(() -> {
            for (int index = 0; index < entries.size(); index++) {
                AppListLoader.loadArtwork(packageManager, entries.get(index));
                boolean isLastEntry = index == entries.size() - 1;
                if (index == FIRST_SCREEN_TILE_COUNT - 1 || isLastEntry) {
                    mainHandler.post(() -> {
                        // Skip results from a reload that has since been superseded
                        if (generation == reloadGeneration && !isDestroyed()) {
                            appGridAdapter.notifyDataSetChanged();
                        }
                    });
                }
            }
        });
    }

    private void launchApp(AppEntry entry) {
        try {
            startActivity(entry.launchIntent);
            launchCounts.edit()
                    .putInt(entry.packageName, launchCounts.getInt(entry.packageName, 0) + 1)
                    .apply();
        } catch (ActivityNotFoundException | SecurityException launchError) {
            Log.w(TAG, "Failed to launch " + entry.packageName, launchError);
            Toast.makeText(this, getString(R.string.launch_failed, entry.label),
                    Toast.LENGTH_SHORT).show();
        }
    }

    private void openAppInfo(AppEntry entry) {
        Intent appInfoIntent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", entry.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            startActivity(appInfoIntent);
        } catch (ActivityNotFoundException appInfoError) {
            Log.w(TAG, "No app info screen for " + entry.packageName, appInfoError);
            Toast.makeText(this, getString(R.string.launch_failed, entry.label),
                    Toast.LENGTH_SHORT).show();
        }
    }
}
