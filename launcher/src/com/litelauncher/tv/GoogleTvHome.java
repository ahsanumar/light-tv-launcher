package com.litelauncher.tv;

import android.app.Activity;
import android.app.SearchManager;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.drawable.Drawable;
import android.provider.Settings;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Space;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;
import java.util.List;

/**
 * Google TV-style home layout: a top bar (search, Home/Apps, inputs, settings, clock),
 * a "Your apps" row of round icons ordered by use, then every app as a banner grid.
 * Plain framework views; with ~20 apps there is nothing to gain from view recycling.
 */
final class GoogleTvHome {
    interface Actions {
        void launchApp(AppEntry entry);
        void openAppInfo(AppEntry entry);
    }

    private static final String TAG = "LiteLauncher";
    private static final String TCL_TV_INPUTS_PACKAGE = "com.tcl.tv";
    private static final int YOUR_APPS_LIMIT = 10;
    private static final int GRID_COLUMNS = 5;
    private static final float FOCUSED_SCALE = 1.1f;
    private static final long FOCUS_ANIMATION_MS = 150;

    private final Activity activity;
    private final Actions actions;
    private final LayoutInflater layoutInflater;
    private final ScrollView scrollView;
    private final LinearLayout yourAppsRow;
    private final LinearLayout allAppsGrid;
    private final int gridSpacingPx;
    private final int iconPaddingPx;
    private final List<Tile> tiles = new ArrayList<>();

    GoogleTvHome(Activity activity, Actions actions) {
        this.activity = activity;
        this.actions = actions;
        this.layoutInflater = activity.getLayoutInflater();
        this.scrollView = activity.findViewById(R.id.gtv_scroll);
        this.yourAppsRow = activity.findViewById(R.id.gtv_your_apps_row);
        this.allAppsGrid = activity.findViewById(R.id.gtv_all_apps_grid);
        float density = activity.getResources().getDisplayMetrics().density;
        this.gridSpacingPx = Math.round(20 * density);
        this.iconPaddingPx = Math.round(22 * density);
        setUpTopBar();
    }

    private void setUpTopBar() {
        activity.findViewById(R.id.gtv_search_button).setOnClickListener(view -> startFirstAvailable(
                new Intent(SearchManager.INTENT_ACTION_GLOBAL_SEARCH),
                new Intent(Intent.ACTION_ASSIST)));

        View inputsButton = activity.findViewById(R.id.gtv_inputs_button);
        Intent inputsIntent = activity.getPackageManager()
                .getLeanbackLaunchIntentForPackage(TCL_TV_INPUTS_PACKAGE);
        if (inputsIntent == null) {
            inputsButton.setVisibility(View.GONE);
        } else {
            inputsButton.setOnClickListener(view -> startFirstAvailable(inputsIntent));
        }

        activity.findViewById(R.id.gtv_settings_button).setOnClickListener(view ->
                startFirstAvailable(new Intent(Settings.ACTION_SETTINGS)));

        activity.findViewById(R.id.gtv_apps_tab).setOnClickListener(view -> focusFirstBanner());
    }

    /** @param entriesByUsage entries sorted most-used first (as {@link AppListLoader} returns them) */
    void render(List<AppEntry> entriesByUsage) {
        tiles.clear();
        yourAppsRow.removeAllViews();
        allAppsGrid.removeAllViews();

        int yourAppsCount = Math.min(entriesByUsage.size(), YOUR_APPS_LIMIT);
        for (int index = 0; index < yourAppsCount; index++) {
            addRoundTile(entriesByUsage.get(index));
        }

        List<AppEntry> alphabeticalEntries = new ArrayList<>(entriesByUsage);
        alphabeticalEntries.sort((first, second) ->
                String.CASE_INSENSITIVE_ORDER.compare(first.label, second.label));
        LinearLayout currentRow = null;
        for (int index = 0; index < alphabeticalEntries.size(); index++) {
            int column = index % GRID_COLUMNS;
            if (column == 0) {
                currentRow = newGridRow();
            }
            addBannerTile(currentRow, alphabeticalEntries.get(index), column);
        }
        padLastRow(currentRow, alphabeticalEntries.size());
        refreshArtwork();
    }

    /** Re-binds images after the background artwork loader has filled them in. */
    void refreshArtwork() {
        for (Tile tile : tiles) {
            tile.bindArtwork(iconPaddingPx);
        }
    }

    void focusFirstApp() {
        scrollView.scrollTo(0, 0);
        if (yourAppsRow.getChildCount() > 0) {
            yourAppsRow.getChildAt(0).requestFocus();
        }
    }

    private void focusFirstBanner() {
        if (allAppsGrid.getChildCount() == 0) {
            return;
        }
        LinearLayout firstRow = (LinearLayout) allAppsGrid.getChildAt(0);
        if (firstRow.getChildCount() > 0) {
            firstRow.getChildAt(0).requestFocus();
        }
    }

    private void addRoundTile(AppEntry entry) {
        View tileView = layoutInflater.inflate(R.layout.item_gtv_round, yourAppsRow, false);
        ImageView iconView = tileView.findViewById(R.id.gtv_round_icon);
        TextView labelView = tileView.findViewById(R.id.gtv_round_label);
        bindTile(tileView, iconView, labelView, entry, R.drawable.gtv_round_focus_ring);
        tiles.add(new Tile(entry, iconView, true));
        yourAppsRow.addView(tileView);
    }

    private LinearLayout newGridRow() {
        LinearLayout row = new LinearLayout(activity);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setClipChildren(false);
        LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT);
        rowParams.bottomMargin = gridSpacingPx;
        allAppsGrid.addView(row, rowParams);
        return row;
    }

    private void addBannerTile(LinearLayout row, AppEntry entry, int column) {
        View tileView = layoutInflater.inflate(R.layout.item_gtv_banner, row, false);
        ImageView bannerView = tileView.findViewById(R.id.gtv_banner_image);
        TextView labelView = tileView.findViewById(R.id.gtv_banner_label);
        bindTile(tileView, bannerView, labelView, entry, R.drawable.gtv_banner_focus_ring);
        if (column < GRID_COLUMNS - 1) {
            ((LinearLayout.LayoutParams) tileView.getLayoutParams()).setMarginEnd(gridSpacingPx);
        }
        tiles.add(new Tile(entry, bannerView, false));
        row.addView(tileView);
    }

    /** Fills a partial last row with empty cells so its tiles keep the same width as full rows. */
    private void padLastRow(LinearLayout lastRow, int entryCount) {
        int remainder = entryCount % GRID_COLUMNS;
        if (lastRow == null || remainder == 0) {
            return;
        }
        for (int column = remainder; column < GRID_COLUMNS; column++) {
            LinearLayout.LayoutParams spacerParams = new LinearLayout.LayoutParams(0, 1, 1f);
            if (column < GRID_COLUMNS - 1) {
                spacerParams.setMarginEnd(gridSpacingPx);
            }
            lastRow.addView(new Space(activity), spacerParams);
        }
    }

    private void bindTile(View tileView, ImageView imageView, TextView labelView, AppEntry entry,
                          int focusRingResource) {
        labelView.setText(entry.label);
        tileView.setContentDescription(entry.label);
        // Clip artwork to the circle / rounded card. The android:clipToOutline XML attribute
        // only exists from API 31, so on this Android 11 TV it must be set in code.
        imageView.setClipToOutline(true);
        tileView.setOnClickListener(view -> actions.launchApp(entry));
        tileView.setOnLongClickListener(view -> {
            actions.openAppInfo(entry);
            return true;
        });
        tileView.setOnFocusChangeListener((view, hasFocus) -> {
            float targetScale = hasFocus ? FOCUSED_SCALE : 1f;
            view.animate().scaleX(targetScale).scaleY(targetScale)
                    .setDuration(FOCUS_ANIMATION_MS).start();
            imageView.setForeground(hasFocus ? activity.getDrawable(focusRingResource) : null);
            labelView.setVisibility(hasFocus ? View.VISIBLE : View.INVISIBLE);
        });
    }

    private void startFirstAvailable(Intent... candidateIntents) {
        for (Intent candidateIntent : candidateIntents) {
            candidateIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            try {
                activity.startActivity(candidateIntent);
                return;
            } catch (ActivityNotFoundException | SecurityException launchError) {
                Log.w(TAG, "No handler for " + candidateIntent, launchError);
            }
        }
        Toast.makeText(activity, R.string.action_unavailable, Toast.LENGTH_SHORT).show();
    }

    private static final class Tile {
        final AppEntry entry;
        final ImageView imageView;
        final boolean isRound;

        Tile(AppEntry entry, ImageView imageView, boolean isRound) {
            this.entry = entry;
            this.imageView = imageView;
            this.isRound = isRound;
        }

        void bindArtwork(int iconPaddingPx) {
            boolean showBanner = !isRound && entry.artworkIsBanner && entry.artwork != null;
            if (showBanner) {
                imageView.setScaleType(ImageView.ScaleType.CENTER_CROP);
                imageView.setPadding(0, 0, 0, 0);
                imageView.setImageDrawable(independentCopy(entry.artwork));
            } else if (!isRound) {
                // Banner slot for an app without a banner: centred icon on the dark card
                imageView.setScaleType(ImageView.ScaleType.FIT_CENTER);
                imageView.setPadding(iconPaddingPx, iconPaddingPx, iconPaddingPx, iconPaddingPx);
                imageView.setImageDrawable(independentCopy(entry.icon));
            } else {
                // Full-bleed icon clipped to the circle, like Google TV's "Your apps" row
                imageView.setScaleType(ImageView.ScaleType.CENTER_CROP);
                imageView.setPadding(0, 0, 0, 0);
                imageView.setImageDrawable(independentCopy(entry.icon));
            }
        }

        /**
         * The same app appears in both the round row and the banner grid. A Drawable has a single
         * set of bounds, so sharing one instance between two views makes each draw at the other's
         * size. newDrawable() gives a separate instance that still shares the decoded bitmap.
         */
        private static Drawable independentCopy(Drawable source) {
            if (source == null) {
                return null;
            }
            Drawable.ConstantState constantState = source.getConstantState();
            return constantState == null ? source : constantState.newDrawable().mutate();
        }
    }
}
