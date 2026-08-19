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

/**
 * Wear OS "Log meal" tile. Shows today's calorie intake against the
 * estimated daily burn in a pill, with a big + button that opens voice
 * logging in the app. The spoken meal is sent to the phone, which
 * estimates and logs it (see WatchSyncService).
 *
 * The estimate runs on the phone's on-device AI, so when the phone can't
 * do it (unsupported device / not set up) the tile says so instead of the
 * + button. Values are read from SharedPreferences, kept fresh by the
 * phone via the data layer.
 */
class MealLogTileService : TileService() {

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

    private fun buildLayout(
        deviceParams: DeviceParametersBuilders.DeviceParameters
    ): LayoutElementBuilders.LayoutElement {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val kcal = prefs.getLong("flutter.today_kcal", 0L).toInt()
        val burn = prefs.getLong("flutter.daily_burn", 0L).toInt()
        val nanoAvailable = prefs.getBoolean("flutter.nano_available", false)

        val screenW = deviceParams.screenWidthDp.toFloat()
        val sideInset = screenW * 0.06f

        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(flexText("Log meal", 15f, 0xFFFFFFFF.toInt(), bold = true))
            .addContent(spacer(8f))
            .addContent(centered(intakePill(kcal, burn)))
            .addContent(spacer(12f))

        if (nanoAvailable) {
            column.addContent(centered(plusButton(openVoiceClickable())))
        } else {
            column.addContent(
                centered(
                    flexText("Enable meal AI on your phone", 12f,
                        0xFF9E9E9E.toInt(), bold = false)
                )
            )
        }

        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    // Tapping anywhere but the + opens the app normally.
                    .setClickable(openAppClickable())
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

    /**
     * Forces horizontal centering for a Column child by wrapping it in a
     * full-width Box with explicit center alignment — more reliable across
     * ProtoLayout renderers than Column.setHorizontalAlignment alone,
     * which doesn't consistently apply to children carrying their own
     * Clickable/Background modifiers (e.g. the + button).
     */
    private fun centered(
        child: LayoutElementBuilders.LayoutElement
    ): LayoutElementBuilders.LayoutElement =
        LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(child)
            .build()

    /** Green intake pill: "1450 / 2210 kcal", or just intake if no burn. */
    private fun intakePill(kcal: Int, burn: Int): LayoutElementBuilders.LayoutElement {
        val label = if (burn > 0) "$kcal / $burn kcal" else "$kcal kcal"
        val over = burn > 0 && kcal > burn
        val bg = if (over) 0xFFF2B8B5.toInt() else GREEN
        return LayoutElementBuilders.Box.Builder()
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(argb(bg))
                            .setCorner(
                                ModifiersBuilders.Corner.Builder()
                                    .setRadius(dp(20f))
                                    .build()
                            )
                            .build()
                    )
                    .setPadding(
                        ModifiersBuilders.Padding.Builder()
                            .setStart(dp(16f))
                            .setEnd(dp(16f))
                            .setTop(dp(6f))
                            .setBottom(dp(6f))
                            .build()
                    )
                    .build()
            )
            .addContent(flexText(label, 15f, 0xFF1B2B20.toInt(), bold = true))
            .build()
    }

    /** Big circular + button. */
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

    private fun openAppClickable(): ModifiersBuilders.Clickable =
        launchClickable("open_app", null)

    private fun openVoiceClickable(): ModifiersBuilders.Clickable =
        launchClickable("log_meal_voice", "log_meal_voice")

    /** Launches MainActivity, optionally with an "open" extra Flutter reads. */
    private fun launchClickable(id: String, openExtra: String?): ModifiersBuilders.Clickable {
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
            .setId(id)
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(activity.build())
                    .build()
            )
            .build()
    }

    companion object {
        private const val RESOURCES_VERSION = "1"

        /** Fitbit/Health-style green. */
        private val GREEN = 0xFF81C995.toInt()
    }
}
