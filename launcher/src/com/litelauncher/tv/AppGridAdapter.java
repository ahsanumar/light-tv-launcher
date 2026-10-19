package com.litelauncher.tv;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.BaseAdapter;
import android.widget.ImageView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

/** Binds {@link AppEntry} tiles to the home GridView and owns the focus highlight. */
final class AppGridAdapter extends BaseAdapter {
    private static final float FOCUSED_SCALE = 1.08f;
    private static final long FOCUS_ANIMATION_MS = 120;

    private final LayoutInflater layoutInflater;
    private final int iconPaddingPx;
    private List<AppEntry> entries = new ArrayList<>();
    private int selectedPosition = -1;

    AppGridAdapter(LayoutInflater layoutInflater) {
        this.layoutInflater = layoutInflater;
        float density = layoutInflater.getContext().getResources().getDisplayMetrics().density;
        this.iconPaddingPx = Math.round(20 * density);
    }

    void setEntries(List<AppEntry> newEntries) {
        entries = newEntries;
        // Keep selectedPosition: GridView keeps its selected index across a data change and
        // won't fire onItemSelected again, so resetting here would leave nothing highlighted
        notifyDataSetChanged();
    }

    @Override public int getCount() { return entries.size(); }
    @Override public AppEntry getItem(int position) { return entries.get(position); }
    @Override public long getItemId(int position) { return position; }

    @Override
    public View getView(int position, View convertView, ViewGroup parent) {
        View tileView = convertView != null
                ? convertView
                : layoutInflater.inflate(R.layout.item_app, parent, false);
        TileViews tileViews = tileView.getTag() instanceof TileViews
                ? (TileViews) tileView.getTag()
                : new TileViews(tileView);
        tileView.setTag(tileViews);

        AppEntry entry = entries.get(position);
        tileViews.label.setText(entry.label);
        tileViews.banner.setContentDescription(entry.label);
        if (entry.artwork == null) {
            tileViews.banner.setImageDrawable(null);
        } else if (entry.artworkIsBanner) {
            tileViews.banner.setScaleType(ImageView.ScaleType.CENTER_CROP);
            tileViews.banner.setPadding(0, 0, 0, 0);
            tileViews.banner.setImageDrawable(entry.artwork);
        } else {
            tileViews.banner.setScaleType(ImageView.ScaleType.FIT_CENTER);
            tileViews.banner.setPadding(iconPaddingPx, iconPaddingPx, iconPaddingPx, iconPaddingPx);
            tileViews.banner.setImageDrawable(entry.artwork);
        }

        // GridView recycles views, so a recycled tile may still carry the old highlight
        applyHighlight(tileView, tileViews, position == selectedPosition, false);
        return tileView;
    }

    /**
     * Re-applies the highlight to every on-screen tile by position. Tracking a single "selected
     * View" doesn't work: GridView also calls getView() for an off-screen tile when measuring
     * row height, so the tracked View can be one that is never drawn.
     */
    void onTileSelected(AdapterView<?> grid, int position) {
        selectedPosition = position;
        int firstVisiblePosition = grid.getFirstVisiblePosition();
        for (int childIndex = 0; childIndex < grid.getChildCount(); childIndex++) {
            View tileView = grid.getChildAt(childIndex);
            if (tileView.getTag() instanceof TileViews) {
                boolean isSelected = firstVisiblePosition + childIndex == selectedPosition;
                applyHighlight(tileView, (TileViews) tileView.getTag(), isSelected, true);
            }
        }
    }

    private static void applyHighlight(View tileView, TileViews tileViews, boolean highlighted,
                                       boolean animate) {
        float targetScale = highlighted ? FOCUSED_SCALE : 1f;
        if (animate) {
            tileView.animate().scaleX(targetScale).scaleY(targetScale)
                    .setDuration(FOCUS_ANIMATION_MS).start();
        } else {
            tileView.animate().cancel();
            tileView.setScaleX(targetScale);
            tileView.setScaleY(targetScale);
        }
        tileViews.banner.setBackgroundResource(highlighted
                ? R.drawable.card_background_focused_fill
                : R.drawable.card_background);
        tileViews.banner.setForeground(highlighted
                ? tileView.getContext().getDrawable(R.drawable.focus_ring)
                : null);
        tileViews.label.setTextColor(tileView.getContext().getColor(highlighted
                ? R.color.text_primary
                : R.color.text_secondary));
    }

    private static final class TileViews {
        final ImageView banner;
        final TextView label;

        TileViews(View tileView) {
            banner = tileView.findViewById(R.id.app_banner);
            label = tileView.findViewById(R.id.app_label);
            // android:clipToOutline in XML is API 31+; set it in code for rounded corners on API 28-30
            banner.setClipToOutline(true);
        }
    }
}
