package com.northernappdev.healthyfast

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat

/**
 * Foreground service that carries the workout Ongoing Activity notification
 * on Wear OS (registered in the watch manifest only). Mirrors
 * [FastingForegroundService] exactly, but is a separate service/notification
 * id so a workout and a fast can be tracked at the same time — starting one
 * never stops or touches the other's timer.
 *
 * If the process is restarted by the system (START_STICKY with a null
 * intent), the workout is re-read from the Flutter app's SharedPreferences —
 * the same "flutter."-keys the Workout tile uses.
 */
class WorkoutForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        var startMs = intent?.getLongExtra(EXTRA_START_MS, -1L) ?: -1L
        var title = intent?.getStringExtra(EXTRA_TITLE)

        // Restarted by the system without an intent: restore from prefs.
        if (startMs <= 0L || title.isNullOrBlank()) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            if (startMs <= 0L) {
                startMs = prefs.getLong("flutter.workout_start_ms", -1L)
            }
            if (title.isNullOrBlank()) {
                title = prefs.getString("flutter.workout_in_progress", null)
            }
        }
        if (startMs <= 0L) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notification =
            WorkoutOngoingNotifier.buildNotification(this, startMs, title ?: "Workout")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                WorkoutOngoingNotifier.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(WorkoutOngoingNotifier.NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        // Belt-and-braces: make sure the chip disappears even if stopService()
        // raced with a system-restart onStartCommand().
        WorkoutOngoingNotifier.hide(this)
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_START_MS = "startMs"
        private const val EXTRA_TITLE = "title"

        fun start(context: Context, startMs: Long, title: String) {
            val intent = Intent(context, WorkoutForegroundService::class.java)
                .putExtra(EXTRA_START_MS, startMs)
                .putExtra(EXTRA_TITLE, title)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(
                Intent(context, WorkoutForegroundService::class.java)
            )
        }
    }
}
