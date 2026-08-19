package com.northernappdev.healthyfast

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.LocusIdCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status

/**
 * Wear OS Ongoing Activity for an active fast — a plain ongoing notification,
 * no foreground service.
 *
 * The OngoingActivity API only requires an ongoing notification; the FGS in
 * Google's codelab exists because that app does real background work. Here
 * the elapsed time is a self-updating chronometer (StopwatchPart), so there
 * is no work to keep alive. Avoiding the FGS also avoids the
 * FOREGROUND_SERVICE_SPECIAL_USE permission and its Play declaration.
 *
 * NOTE: this path was long broken by a status-template typo ("Fasting #time"
 * — placeholders need both hashes: "#time#") which threw before notify() was
 * ever called. If testing still shows no watch-face chip on target devices,
 * [FastingForegroundService] is a ready fallback: re-add its manifest entry +
 * FGS permissions and switch MainActivity to start the service instead.
 */
object FastingOngoingNotifier {

    private const val CHANNEL_ID = "fasting_ongoing_v2"
    const val NOTIFICATION_ID = 4201

    /** Posts (or updates) the ongoing-activity notification for a fast. */
    fun show(context: Context, startMs: Long, goalHours: Int) {
        if (startMs <= 0L) return
        NotificationManagerCompat.from(context)
            .notify(NOTIFICATION_ID, buildNotification(context, startMs, goalHours))
    }

    fun hide(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    /** Builds the notification carrying the OngoingActivity. */
    fun buildNotification(context: Context, startMs: Long, goalHours: Int): Notification {
        createChannel(context)

        val open = openAppIntent(context)
        val locusId = LocusIdCompat("ongoing_fast")

        // The watch-face chip and Recents item use a Chronometer, which must
        // be relative to SystemClock.elapsedRealtime().
        val elapsedRealtimeBase =
            SystemClock.elapsedRealtime() - (System.currentTimeMillis() - startMs)

        val status = Status.Builder()
            // The template shown in the launcher's "Recents" section.
            // Shortened from "Fasting #time#" to ensure it fits without cutoff
            // on all watch shapes and font sizes (Requirement WO-V4).
            .addTemplate("Fast #time#")
            .addPart("time", Status.StopwatchPart(elapsedRealtimeBase))
            .build()

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            // Must be a monochrome vector: the watch-face ongoing-activity
            // chip silently drops full-colour launcher icons.
            .setSmallIcon(R.drawable.ic_stat_fasting)
            .setContentTitle(context.getString(R.string.app_name))
            // Concise text for the notification stream.
            .setContentText("Fast: ${goalHours}h goal")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setContentIntent(open)
            .setLocusId(locusId)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            // Self-updating elapsed-time chronometer, counting up from the start.
            .setUsesChronometer(true)
            .setWhen(startMs)
            .setShowWhen(true)

        val ongoingActivity = OngoingActivity.Builder(context, NOTIFICATION_ID, builder)
            .setStaticIcon(R.drawable.ic_stat_fasting)
            .setTouchIntent(open)
            .setStatus(status)
            .setLocusId(locusId)
            .build()
        ongoingActivity.apply(context)

        return builder.build()
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun createChannel(context: Context) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Active fast",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows your fast in progress on the watch."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }
}
