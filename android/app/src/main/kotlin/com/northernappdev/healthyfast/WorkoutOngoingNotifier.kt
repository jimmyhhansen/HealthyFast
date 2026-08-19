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
 * Wear OS Ongoing Activity for an active workout — mirrors
 * [FastingOngoingNotifier] but with its own notification id/channel, so a
 * workout and a fast can run as two independent ongoing activities at the
 * same time without either one clobbering the other's chip/timer.
 */
object WorkoutOngoingNotifier {

    private const val CHANNEL_ID = "workout_ongoing_v1"
    const val NOTIFICATION_ID = 4301

    /** Posts (or updates) the ongoing-activity notification for a workout. */
    fun show(context: Context, startMs: Long, title: String) {
        if (startMs <= 0L) return
        NotificationManagerCompat.from(context)
            .notify(NOTIFICATION_ID, buildNotification(context, startMs, title))
    }

    fun hide(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    /** Builds the notification carrying the OngoingActivity. */
    fun buildNotification(context: Context, startMs: Long, title: String): Notification {
        createChannel(context)

        val open = openAppIntent(context)
        val locusId = LocusIdCompat("ongoing_workout")
        val safeTitle = title.ifBlank { "Workout" }

        val elapsedRealtimeBase =
            SystemClock.elapsedRealtime() - (System.currentTimeMillis() - startMs)

        val status = Status.Builder()
            .addTemplate("Workout #time#")
            .addPart("time", Status.StopwatchPart(elapsedRealtimeBase))
            .build()

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_workout)
            .setContentTitle(safeTitle)
            .setContentText("Workout in progress")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setContentIntent(open)
            .setLocusId(locusId)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setUsesChronometer(true)
            .setWhen(startMs)
            .setShowWhen(true)

        val ongoingActivity = OngoingActivity.Builder(context, NOTIFICATION_ID, builder)
            .setStaticIcon(R.drawable.ic_stat_workout)
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
            1,
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
                "Active workout",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Shows your workout in progress on the watch."
                setShowBadge(false)
            }
            manager.createNotificationChannel(channel)
        }
    }
}
