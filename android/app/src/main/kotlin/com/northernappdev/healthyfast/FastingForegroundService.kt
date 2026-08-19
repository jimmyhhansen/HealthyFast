package com.northernappdev.healthyfast

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat

/**
 * Foreground service that carries the fasting Ongoing Activity notification
 * on Wear OS (registered in the watch manifest only).
 *
 * The service does no work — the notification's chronometer is self-updating —
 * but the watch-face ongoing-activity chip is only rendered reliably for
 * notifications that belong to a foreground service, and the service keeps
 * the indicator alive even if the app process is killed while fasting.
 *
 * If the process is restarted by the system (START_STICKY with a null
 * intent), the fast is re-read from the Flutter app's SharedPreferences —
 * the same "flutter."-keys the complications and the Tile use.
 */
class FastingForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        var startMs = intent?.getLongExtra(EXTRA_START_MS, -1L) ?: -1L
        var goalHours = intent?.getIntExtra(EXTRA_GOAL_HOURS, -1) ?: -1

        // Restarted by the system without an intent: restore from prefs.
        if (startMs <= 0L) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            startMs = prefs.getLong("flutter.fast_start_ms", -1L)
            if (goalHours <= 0) {
                val idx = prefs.getLong("flutter.protocol_idx", 0L).toInt()
                goalHours = if (idx == -1) {
                    prefs.getLong("flutter.custom_hours", 48L).toInt()
                } else {
                    intArrayOf(16, 18, 20, 24, 36).getOrElse(idx) { 16 }
                }
            }
        }
        if (startMs <= 0L) {
            stopSelf()
            return START_NOT_STICKY
        }

        val notification =
            FastingOngoingNotifier.buildNotification(this, startMs, goalHours)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                FastingOngoingNotifier.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(FastingOngoingNotifier.NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    companion object {
        private const val EXTRA_START_MS = "startMs"
        private const val EXTRA_GOAL_HOURS = "goalHours"

        fun start(context: Context, startMs: Long, goalHours: Int) {
            val intent = Intent(context, FastingForegroundService::class.java)
                .putExtra(EXTRA_START_MS, startMs)
                .putExtra(EXTRA_GOAL_HOURS, goalHours)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(
                Intent(context, FastingForegroundService::class.java)
            )
        }
    }
}
