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
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import org.json.JSONObject

/**
 * Wear OS "Train" tile: the next program workout and this week's count,
 * with a + button that opens on-watch workout logging. Data is pushed
 * from the phone via the data layer into SharedPreferences.
 */
class TrainTileService : TileService() {

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest
    ): ListenableFuture<TileBuilders.Tile> {
        val cfg = requestParams.deviceConfiguration
        val deviceParams = DeviceParametersBuilders.DeviceParameters.Builder()
            .setScreenWidthDp(cfg.screenWidthDp)
            .setScreenHeightDp(cfg.screenHeightDp)
            .setScreenDensity(cfg.screenDensity)
            .setScreenShape(cfg.screenShape)
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
            .setFreshnessIntervalMillis(300_000L)
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

    private fun buildLayout(
        deviceParams: DeviceParametersBuilders.DeviceParameters
    ): LayoutElementBuilders.LayoutElement {
        val prefs =
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val nextJson = prefs.getString("flutter.next_workout_json", null)
        val weekDone = prefs.getLong("flutter.week_workouts_done", 0L).toInt()
        val inProgress = prefs.getString("flutter.workout_in_progress", null)

        var nextTitle: String? = null
        if (!nextJson.isNullOrEmpty()) {
            try {
                nextTitle = JSONObject(nextJson).optString("title", "")
                    .ifEmpty { null }
            } catch (_: Exception) {}
        }

        val screenW = deviceParams.screenWidthDp.toFloat()
        val sideInset = screenW * 0.06f

        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(flexText("Workout", 15f, 0xFFFFFFFF.toInt(), bold = true))
            .addContent(spacer(6f))

        if (!inProgress.isNullOrEmpty()) {
            // A session is running on the watch right now.
            column
                .addContent(
                    flexText("In session: $inProgress", 13f, GREEN,
                        bold = true)
                )
                .addContent(spacer(10f))
                .addContent(centered(plusButton(clickable("log_workout"))))
        } else if (nextTitle != null) {
            column
                .addContent(
                    flexText("Next: $nextTitle", 13f, 0xFFFFFFFF.toInt(),
                        bold = false)
                )
                .addContent(spacer(4f))
                .addContent(
                    pill("$weekDone this week", GREEN)
                )
                .addContent(spacer(12f))
                .addContent(centered(plusButton(clickable("log_workout"))))
        } else {
            // No program yet — the watch app can now pick one locally,
            // so the + opens the workout flow's program picker.
            column
                .addContent(
                    centered(
                        flexText("Pick a program", 12f,
                            0xFF9E9E9E.toInt(), bold = false)
                    )
                )
                .addContent(spacer(10f))
                .addContent(centered(plusButton(clickable("log_workout"))))
        }

        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(clickable(null))
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

    private fun spacer(h: Float) =
        LayoutElementBuilders.Spacer.Builder().setHeight(dp(h)).build()

    private fun centered(
        child: LayoutElementBuilders.LayoutElement
    ): LayoutElementBuilders.LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(child)
            .build()

    private fun pill(text: String, bg: Int): LayoutElementBuilders.LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(bg))
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

    private fun plusButton(
        clickable: ModifiersBuilders.Clickable
    ): LayoutElementBuilders.LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setWidth(dp(56f))
            .setHeight(dp(56f))
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(clickable)
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(GREEN))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(dp(28f))
                                    .build()
                            )
                            .build()
                    )
                    .build()
            )
            .addContent(flexText("+", 28f, 0xFF1B2B20.toInt(), bold = true))
            .build()

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
                    .setSize(sp(sizeSp))
                    .setColor(argb(color))
                    .setWeight(
                        if (bold) LayoutElementBuilders.FONT_WEIGHT_BOLD
                        else LayoutElementBuilders.FONT_WEIGHT_NORMAL
                    )
                    .setPreferredFontFamilies("roboto-flex")
                    .build()
            )
            .build()

    /** Launches MainActivity, optionally with an "open" extra. */
    private fun clickable(openExtra: String?): ModifiersBuilders.Clickable {
        val activity = ActionBuilders.AndroidActivity.Builder()
            .setPackageName(packageName)
            .setClassName("com.northernappdev.healthyfast.MainActivity")
        if (openExtra != null) {
            activity.addKeyToExtraMapping(
                "open",
                ActionBuilders.AndroidStringExtra.Builder()
                    .setValue(openExtra)
                    .build()
            )
        }
        return ModifiersBuilders.Clickable.Builder()
            .setId(openExtra ?: "open_app")
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(activity.build())
                    .build()
            )
            .build()
    }

    companion object {
        private const val RESOURCES_VERSION = "1"
        private val GREEN = 0xFF81C995.toInt()
    }
}
