package com.northernappdev.healthyfast

import android.content.Context
import androidx.concurrent.futures.ResolvableFuture
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.material.CircularProgressIndicator
import androidx.wear.protolayout.material.ProgressIndicatorColors
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture

/**
 * Wear OS Tile that references the active fast (the ongoing activity).
 *
 * Reads the current fast straight from the Flutter app's SharedPreferences
 * and shows the elapsed time, goal, and a progress ring. Tapping the tile
 * opens the app.
 */
class FastingTileService : TileService() {

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest
    ): ListenableFuture<TileBuilders.Tile> {
        val deviceConfiguration = requestParams.deviceConfiguration
        val deviceParams = DeviceParametersBuilders.DeviceParameters.Builder()
            .setScreenWidthDp(deviceConfiguration.screenWidthDp)
            .setScreenHeightDp(deviceConfiguration.screenHeightDp)
            .setScreenDensity(deviceConfiguration.screenDensity)
            .setScreenShape(deviceConfiguration.screenShape)
            .setDevicePlatform(DeviceParametersBuilders.DEVICE_PLATFORM_WEAR_OS)
            .build()

        val timeline = TimelineBuilders.Timeline.Builder()
            .addTimelineEntry(
                TimelineBuilders.TimelineEntry.Builder()
                    .setLayout(
                        LayoutElementBuilders.Layout.Builder()
                            .setRoot(buildLayout(deviceParams))
                            .build()
                    )
                    .build()
            )
            .build()

        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setTileTimeline(timeline)
            // Recompute on each refresh to update the chronometer-like display.
            .setFreshnessIntervalMillis(60_000L)
            .build()
        return ResolvableFuture.create<TileBuilders.Tile>().apply { set(tile) }
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest
    ): ListenableFuture<ResourceBuilders.Resources> =
        ResolvableFuture.create<ResourceBuilders.Resources>().apply {
            set(
                ResourceBuilders.Resources.Builder()
                    .setVersion(RESOURCES_VERSION)
                    .build()
            )
        }

    private fun buildLayout(deviceParams: DeviceParametersBuilders.DeviceParameters): LayoutElementBuilders.LayoutElement {
        val state = getFastingState()
        
        val clickable = ModifiersBuilders.Clickable.Builder()
            .setId("open_app")
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(
                        ActionBuilders.AndroidActivity.Builder()
                            .setPackageName(packageName)
                            .setClassName("com.northernappdev.healthyfast.MainActivity")
                            .build()
                    )
                    .build()
            )
            .build()

        // Custom full-screen layout (no EdgeContentLayout): the stadium card
        // is bezel-friendly by shape, so it can use far more of the screen.
        // The whole column is vertically centred, which keeps the top label
        // and bottom goal well inside the round display.
        val screenW = deviceParams.screenWidthDp.toFloat()
        val sideInset = screenW * 0.06f

        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)

        if (state.isFasting) {
            column
                .addContent(
                    Text.Builder(this, state.zoneName)
                        .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                        .setColor(argb(state.zoneColor))
                        .setMaxLines(1)
                        .build()
                )
                .addContent(spacer(8f))
                .addContent(
                    metricCard(
                        bigText = state.elapsedShort,
                        pillText = state.remainingShort,
                        pillColor = GREEN,
                        progress = state.progress,
                        ringColor = state.zoneColor,
                        ringEmoji = state.zoneEmoji,
                    )
                )
                .addContent(spacer(10f))
                .addContent(
                    flexText("Goal", 12f, 0xFF9E9E9E.toInt(), bold = false)
                )
                .addContent(
                    flexText("${state.goalHours}h", 15f, GREEN, bold = true)
                )
        } else {
            column
                .addContent(
                    Text.Builder(this, "HealthyFast")
                        .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                        .setColor(argb(0xFF9E9E9E.toInt()))
                        .setMaxLines(1)
                        .build()
                )
                .addContent(spacer(8f))
                .addContent(
                    metricCard(
                        bigText = state.protocolLabel,
                        pillText = "Ready to fast",
                        pillColor = 0xFF9E9E9E.toInt(),
                        progress = 0f,
                        ringColor = 0xFF9E9E9E.toInt(),
                        ringEmoji = "",
                    )
                )
                .addContent(spacer(10f))
                .addContent(
                    flexText("Tap to start", 12f, 0xFF9E9E9E.toInt(), bold = false)
                )
        }

        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(clickable)
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(dp(sideInset))
                            .setEnd(dp(sideInset))
                            .build()
                    )
                    .build()
            )
            .addContent(column.build())
            .build()
    }

    private fun spacer(heightDp: Float): LayoutElementBuilders.Spacer =
        LayoutElementBuilders.Spacer.Builder().setHeight(dp(heightDp)).build()

    /**
     * Dampens the system font scale on the tile: sp sizes still grow with
     * the user's setting, but only 40% of the increase applies. Max font
     * then renders ~20% bigger instead of ~50%, so the layout always has
     * room for the ring.
     */
    private fun dampedSp(base: Float): Float {
        val fs = resources.configuration.fontScale
        if (fs <= 1f) return base
        return base * (1f + (fs - 1f) * 0.4f) / fs
    }

    /**
     * Text in Roboto Flex — the Material 3 Expressive font used across
     * Pixel Watch 4 tiles. Older renderers ignore the preference and fall
     * back to the default font.
     */
    private fun flexText(
        text: String,
        sizeSp: Float,
        color: Int,
        bold: Boolean,
    ): LayoutElementBuilders.Text =
        LayoutElementBuilders.Text.Builder()
            .setText(text)
            .setMaxLines(1)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setSize(sp(dampedSp(sizeSp)))
                    .setColor(argb(color))
                    .setWeight(
                        if (bold) {
                            LayoutElementBuilders.FONT_WEIGHT_BOLD
                        } else {
                            LayoutElementBuilders.FONT_WEIGHT_NORMAL
                        }
                    )
                    .build()
            )
            .build()

    /**
     * The big rounded card from the Health "Steps" tile: main number with a
     * filled status pill under it on the left, circular progress badge on
     * the right. Wraps its content, so it grows with large system fonts.
     */
    private fun metricCard(
        bigText: String,
        pillText: String,
        pillColor: Int,
        progress: Float,
        ringColor: Int,
        ringEmoji: String,
    ): LayoutElementBuilders.LayoutElement {
        val left = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(flexText(bigText, 22f, 0xFFFFFFFF.toInt(), bold = true))
            .addContent(spacer(5f))
            .addContent(filledPill(pillText, pillColor))
            .build()

        val ring = LayoutElementBuilders.Box.Builder()
            .setWidth(dp(44f))
            .setHeight(dp(44f))
            .addContent(
                CircularProgressIndicator.Builder()
                    .setProgress(progress)
                    .setStrokeWidth(dp(5f))
                    .setCircularProgressIndicatorColors(
                        ProgressIndicatorColors(argb(ringColor), argb(0x1AFFFFFF))
                    )
                    .build()
            )
            .addContent(
                flexText(ringEmoji, 14f, 0xFFFFFFFF.toInt(), bold = false)
            )
            .build()

        // Expandable spacer pins the ring to the card's right edge, so it
        // always has its full 44 dp — the text side gets what is left.
        val row = LayoutElementBuilders.Row.Builder()
            .setWidth(expand())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .addContent(left)
            .addContent(
                LayoutElementBuilders.Spacer.Builder().setWidth(expand()).build()
            )
            .addContent(ring)
            .build()

        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(0x26FFFFFF))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(dp(36f))
                                    .build()
                            )
                            .build()
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(dp(20f))
                            .setEnd(dp(14f))
                            .setTop(dp(14f))
                            .setBottom(dp(14f))
                            .build()
                    )
                    .build()
            )
            .addContent(row)
            .build()
    }

    /**
     * Small filled status pill, like "4k over" on the Steps tile — solid
     * colour background with dark text.
     */
    private fun filledPill(
        text: String,
        bgColor: Int,
    ): LayoutElementBuilders.LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(bgColor))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(dp(14f))
                                    .build()
                            )
                            .build()
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(dp(10f))
                            .setEnd(dp(10f))
                            .setTop(dp(3f))
                            .setBottom(dp(3f))
                            .build()
                    )
                    .build()
            )
            .addContent(flexText(text, 12f, 0xFF1B2B20.toInt(), bold = false))
            .build()


    private data class FastingState(
        val isFasting: Boolean,
        val elapsedShort: String,
        val goalHours: Int,
        val protocolLabel: String,
        val progress: Float,
        val remainingShort: String,
        val zoneName: String,
        val zoneEmoji: String,
        val zoneColor: Int
    )

    private fun getFastingState(): FastingState {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val start = prefs.getLong("flutter.fast_start_ms", -1L)

        val idx = prefs.getLong("flutter.protocol_idx", 0L).toInt()
        val goalHours = if (idx == -1) {
            prefs.getLong("flutter.custom_hours", 48L).toInt()
        } else {
            intArrayOf(16, 18, 20, 24, 36).getOrElse(idx) { 16 }
        }
        // Same labels as FastingProtocol.presets in the Flutter app.
        val protocolLabel = if (idx == -1) {
            "${goalHours}h"
        } else {
            arrayOf("16:8", "18:6", "20:4", "24h", "36h").getOrElse(idx) { "16:8" }
        }

        if (start <= 0L) {
            return FastingState(false, "", goalHours, protocolLabel, 0f, "", "", "", 0)
        }

        val elapsedMs = (System.currentTimeMillis() - start).coerceAtLeast(0)
        val h = (elapsedMs / 3600000).toInt()
        val m = ((elapsedMs % 3600000) / 60000).toInt()

        // Hours + minutes is enough here; seconds would be stale anyway
        // with the tile's 60 s freshness interval.
        val elapsedShort = if (h > 0) "${h}h ${m}m" else "${m}m"
        val progress = (elapsedMs.toFloat() / (goalHours * 3600000f)).coerceAtMost(1f)

        val leftMs = goalHours * 3_600_000L - elapsedMs
        val remainingShort = if (leftMs <= 0) {
            "Goal reached"
        } else {
            val lh = (leftMs / 3600000).toInt()
            val lm = ((leftMs % 3600000) / 60000).toInt()
            if (lh > 0) "${lh}h ${lm}m left" else "${lm}m left"
        }
        
        // Match zones from fasting_zone.dart
        val hours = elapsedMs / 3600000.0
        val (zoneName, zoneEmoji, zoneColor) = when {
            hours < 4 -> Triple("Fed State", "", 0xFF9E9E9E.toInt())
            hours < 8 -> Triple("Early Fast", "", 0xFFFFC107.toInt())
            hours < 14 -> Triple("Glycogen Burning", "", 0xFFFF7043.toInt())
            hours < 18 -> Triple("Metabolic Switch", "", 0xFF29B6F6.toInt())
            hours < 24 -> Triple("Fat Burning", "", 0xFF26A69A.toInt())
            hours < 36 -> Triple("Autophagy", "", 0xFF9C27B0.toInt())
            else -> Triple("Deep Renewal", "", 0xFF3F51B5.toInt())
        }

        return FastingState(
            true, elapsedShort, goalHours, protocolLabel,
            progress, remainingShort, zoneName, zoneEmoji, zoneColor
        )
    }

    companion object {
        private const val RESOURCES_VERSION = "2"

        /** Fitbit/Health-style green for the remaining pill.
            (val, not const: .toInt() is not a compile-time constant.) */
        private val GREEN = 0xFF81C995.toInt()
    }
}
