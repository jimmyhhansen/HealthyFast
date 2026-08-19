package com.northernappdev.healthyfast

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.data.ColorRamp
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.CountUpTimeReference
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.data.TimeDifferenceStyle
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import java.time.Instant
import kotlin.math.ceil

/**
 * Watch face complications for HealthyFast.
 *
 * Reads the active fast directly from the Flutter app's SharedPreferences
 * (keys are prefixed "flutter." by the shared_preferences plugin).
 *
 * "Remaining" is shown in whole hours only (never days), so it needs
 * periodic refreshes: UPDATE_PERIOD_SECONDS in the manifest plus a push
 * from the app when a fast starts/stops. "Elapsed" uses a self-updating
 * TimeDifference text.
 */
abstract class BaseFastingComplicationService : ComplicationDataSourceService() {

    protected fun fastStartMs(): Long? {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val v = prefs.getLong("flutter.fast_start_ms", -1L)
        return if (v > 0) v else null
    }

    protected fun goalHours(): Int {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val idx = prefs.getLong("flutter.protocol_idx", 0L).toInt()
        return if (idx == -1) {
            prefs.getLong("flutter.custom_hours", 48L).toInt()
        } else {
            intArrayOf(16, 18, 20, 24, 36).getOrElse(idx) { 16 }
        }
    }

    /** Hours left until the goal, rounded up. Never negative. */
    protected fun hoursLeft(startMs: Long): Int {
        val goalEnd = startMs + goalHours() * 3_600_000L
        val leftMs = goalEnd - System.currentTimeMillis()
        return if (leftMs <= 0) 0 else ceil(leftMs / 3_600_000.0).toInt()
    }

    /** "13h" while running, "Done" once the goal is reached. */
    protected fun hoursLeftLabel(startMs: Long): String {
        val h = hoursLeft(startMs)
        return if (h == 0) "Done" else "${h}h"
    }

    /**
     * Zone colours (fasting_zone.dart) that occur between hour 0 and the
     * goal, as an interpolated ramp for the RANGED_VALUE progress ring.
     * Whether the ring honours the ramp is up to the watch face; faces
     * that don't will tint it with their theme colour instead.
     */
    protected fun zoneRamp(): ColorRamp {
        val stops = listOf(
            0 to 0xFF9E9E9E.toInt(),   // Fed State
            4 to 0xFFFFC107.toInt(),   // Early Fast
            8 to 0xFFFF7043.toInt(),   // Glycogen Burning
            14 to 0xFF29B6F6.toInt(),  // Metabolic Switch
            18 to 0xFF26A69A.toInt(),  // Fat Burning
            24 to 0xFF9C27B0.toInt(),  // Autophagy
            36 to 0xFF3F51B5.toInt(),  // Deep Renewal
        )
        val goal = goalHours()
        val colors = stops.filter { it.first < goal }.map { it.second }
        val arr = when {
            colors.size >= 2 -> colors.toIntArray()
            colors.size == 1 -> intArrayOf(colors[0], colors[0])
            else -> intArrayOf(0xFF9E9E9E.toInt(), 0xFF9E9E9E.toInt())
        }
        // ColorRamp supports at most 7 colours — exactly our zone count.
        return ColorRamp(arr, true)
    }

    /** PendingIntent that opens the app when the complication is tapped. */
    protected fun openAppIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    protected fun shortText(text: ComplicationText, title: String): ShortTextComplicationData =
        ShortTextComplicationData.Builder(
            text,
            PlainComplicationText.Builder(title).build()
        )
            .setTitle(PlainComplicationText.Builder(title).build())
            .setTapAction(openAppIntent())
            .build()

    protected fun plain(s: String): ComplicationText =
        PlainComplicationText.Builder(s).build()
}

/**
 * Shows how long the current fast has been running (counts up). As
 * RANGED_VALUE it also draws a progress ring around the text with the
 * fasting zone colours as a ramp — the text self-updates, the ring
 * value refreshes on the manifest's update period.
 */
class ElapsedFastComplicationService : BaseFastingComplicationService() {

    private fun elapsedText(start: Long): ComplicationText =
        TimeDifferenceComplicationText.Builder(
            TimeDifferenceStyle.SHORT_DUAL_UNIT,
            CountUpTimeReference(Instant.ofEpochMilli(start))
        ).build()

    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener
    ) {
        val start = fastStartMs()
        val data = when (request.complicationType) {
            ComplicationType.SHORT_TEXT -> {
                if (start == null) shortText(plain("--"), "Fast")
                else shortText(elapsedText(start), "Fast")
            }
            ComplicationType.RANGED_VALUE -> rangedValue(start)
            else -> null
        }
        listener.onComplicationData(data)
    }

    private fun rangedValue(start: Long?): RangedValueComplicationData {
        val goal = goalHours().toFloat()
        val elapsedH = if (start == null) 0f else {
            ((System.currentTimeMillis() - start) / 3_600_000.0)
                .toFloat().coerceIn(0f, goal)
        }
        val text = if (start == null) plain("--") else elapsedText(start)
        return RangedValueComplicationData.Builder(
            elapsedH,
            0f,
            goal,
            plain("Fasting for ${elapsedH.toInt()} of $goal hours")
        )
            .setText(text)
            .setTitle(plain("Fast"))
            .setColorRamp(zoneRamp())
            .setTapAction(openAppIntent())
            .build()
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? = when (type) {
        ComplicationType.SHORT_TEXT -> shortText(plain("16h 30m"), "Fast")
        ComplicationType.RANGED_VALUE ->
            RangedValueComplicationData.Builder(12f, 0f, 16f, plain("12 hours elapsed"))
                .setText(plain("12h 30m"))
                .setTitle(plain("Fast"))
                .setColorRamp(zoneRamp())
                .build()
        else -> null
    }
}

/**
 * Shows whole hours remaining until the fast goal — never days ("29h",
 * not "1d 5h"). As RANGED_VALUE it also draws a progress ring around the
 * text, with the fasting zone colours as a ramp (like the phone app's ring).
 */
class RemainingFastComplicationService : BaseFastingComplicationService() {

    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener
    ) {
        val start = fastStartMs()
        val data = when (request.complicationType) {
            ComplicationType.SHORT_TEXT -> {
                if (start == null) shortText(plain("--"), "Left")
                else shortText(plain(hoursLeftLabel(start)), "Left")
            }
            ComplicationType.RANGED_VALUE -> rangedValue(start)
            else -> null
        }
        listener.onComplicationData(data)
    }

    private fun rangedValue(start: Long?): RangedValueComplicationData {
        val goal = goalHours().toFloat()
        val elapsedH = if (start == null) 0f else {
            ((System.currentTimeMillis() - start) / 3_600_000.0)
                .toFloat().coerceIn(0f, goal)
        }
        val label = if (start == null) "--" else hoursLeftLabel(start)
        return RangedValueComplicationData.Builder(
            elapsedH,
            0f,
            goal,
            plain("$label left of a ${goal.toInt()} hour fast")
        )
            .setText(plain(label))
            .setTitle(plain("Left"))
            .setColorRamp(zoneRamp())
            .setTapAction(openAppIntent())
            .build()
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? = when (type) {
        ComplicationType.SHORT_TEXT -> shortText(plain("4h"), "Left")
        ComplicationType.RANGED_VALUE ->
            RangedValueComplicationData.Builder(12f, 0f, 16f, plain("4 hours left"))
                .setText(plain("4h"))
                .setTitle(plain("Left"))
                .setColorRamp(zoneRamp())
                .build()
        else -> null
    }
}
