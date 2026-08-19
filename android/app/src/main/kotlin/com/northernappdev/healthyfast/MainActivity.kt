package com.northernappdev.healthyfast

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import androidx.activity.enableEdgeToEdge
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.lifecycle.lifecycleScope
import androidx.wear.remote.interactions.RemoteActivityHelper
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import com.google.android.gms.wearable.Wearable
import com.samsung.wearable_rotary.WearableRotaryPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.Period
import java.time.ZoneId

class MainActivity : FlutterFragmentActivity() {

    private var mealEstimator: MealEstimator? = null
    private var navChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15+ (SDK 35+) makes apps edge-to-edge by default. Calling
        // this ensures consistent behavior. Gated on non-watch
        // because Wear OS has its own inset management.
        if (!isWatch()) {
            enableEdgeToEdge()
        }
        super.onCreate(savedInstanceState)
    }

    override fun onGenericMotionEvent(event: MotionEvent?): Boolean {
        return when {
            WearableRotaryPlugin.onGenericMotionEvent(event) -> true
            else -> super.onGenericMotionEvent(event)
        }
    }

    override fun onDestroy() {
        mealEstimator?.dispose()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverNavIntent()
    }

    override fun onResume() {
        super.onResume()
        deliverNavIntent()
    }

    private fun deliverNavIntent() {
        val open = intent?.getStringExtra("open") ?: return
        intent?.removeExtra("open")
        val ch = navChannel ?: return
        Handler(Looper.getMainLooper()).postDelayed({
            ch.invokeMethod("open", open)
        }, 300)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        navChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "healthyfast/nav"
        )

        // Meal Estimator Channel (Gemini Nano)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "healthyfast/meal"
        ).setMethodCallHandler { call, result ->
            val estimator = mealEstimator ?: MealEstimator().also { mealEstimator = it }
            when (call.method) {
                "checkNanoStatus" -> estimator.checkStatus(result)
                "downloadNano" -> estimator.download(result)
                "estimateMeal" -> {
                    val description = call.argument<String>("description")
                    if (description.isNullOrBlank()) {
                        result.error("BAD_ARGS", "description is required", null)
                    } else {
                        estimator.estimate(description, result)
                    }
                }
                "extractFoods" -> {
                    val description = call.argument<String>("description")
                    if (description.isNullOrBlank()) {
                        result.error("BAD_ARGS", "description is required", null)
                    } else {
                        estimator.extractFoods(description, result)
                    }
                }
                "describeImage" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("BAD_ARGS", "path is required", null)
                    } else {
                        estimator.describeImage(path, result)
                    }
                }
                "generateProgram" -> {
                    val description = call.argument<String>("description")
                    val exerciseNames = call.argument<List<String>>("exerciseNames")
                    if (description.isNullOrBlank() || exerciseNames.isNullOrEmpty()) {
                        result.error("BAD_ARGS", "description and exerciseNames are required", null)
                    } else {
                        estimator.generateProgram(description, exerciseNames, result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Wear OS Channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "healthyfast/wear"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "installOnWatch" -> {
                    Wearable.getNodeClient(this).connectedNodes
                        .addOnSuccessListener { nodes ->
                            if (nodes.isEmpty()) {
                                result.success(0)
                            } else {
                                val helper = RemoteActivityHelper(this)
                                val intent = Intent(Intent.ACTION_VIEW)
                                    .addCategory(Intent.CATEGORY_BROWSABLE)
                                    .setData(Uri.parse("market://details?id=$packageName"))
                                for (node in nodes) {
                                    helper.startRemoteActivity(intent, node.id)
                                }
                                result.success(nodes.size)
                            }
                        }
                        .addOnFailureListener { e ->
                            result.error("WEAR_ERROR", e.message, null)
                        }
                }
                "refreshComplications" -> {
                    try {
                        listOf(
                            ElapsedFastComplicationService::class.java,
                            RemainingFastComplicationService::class.java
                        ).forEach { cls ->
                            ComplicationDataSourceUpdateRequester
                                .create(this, ComponentName(this, cls))
                                .requestUpdateAll()
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("COMPLICATION_ERROR", e.message, null)
                    }
                }
                "startOngoing" -> {
                    if (!isWatch()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        val startMs = (call.argument<Number>("startMs"))?.toLong() ?: -1L
                        val goalHours = (call.argument<Number>("goalHours"))?.toInt() ?: 16
                        FastingForegroundService.start(this, startMs, goalHours)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ONGOING_ERROR", e.message, null)
                    }
                }
                "stopOngoing" -> {
                    try {
                        FastingForegroundService.stop(this)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ONGOING_ERROR", e.message, null)
                    }
                }
                "startOngoingWorkout" -> {
                    if (!isWatch()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        val startMs = (call.argument<Number>("startMs"))?.toLong() ?: -1L
                        val title = call.argument<String>("title") ?: "Workout"
                        WorkoutForegroundService.start(this, startMs, title)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ONGOING_ERROR", e.message, null)
                    }
                }
                "stopOngoingWorkout" -> {
                    try {
                        WorkoutForegroundService.stop(this)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("ONGOING_ERROR", e.message, null)
                    }
                }
                "refreshTiles" -> {
                    if (isWatch()) {
                        try {
                            val updater = androidx.wear.tiles.TileService.getUpdater(this)
                            updater.requestUpdate(FastingTileService::class.java)
                        } catch (e: Exception) {
                            // Ignore
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Health Connect Channel (Deduplicated Steps)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "healthyfast/health"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDailySteps" -> {
                    val startMs = (call.argument<Number>("startMs"))?.toLong() ?: return@setMethodCallHandler
                    val endMs = (call.argument<Number>("endMs"))?.toLong() ?: return@setMethodCallHandler

                    Log.d("HEALTHYFAST", "getDailySteps: startMs=$startMs, endMs=$endMs")

                    val sdkStatus = HealthConnectClient.getSdkStatus(this)
                    if (sdkStatus != HealthConnectClient.SDK_AVAILABLE) {
                        Log.w("HEALTHYFAST", "Health Connect SDK not available: status=$sdkStatus")
                        result.success(emptyMap<String, Long>())
                        return@setMethodCallHandler
                    }

                    val client = HealthConnectClient.getOrCreate(this)
                    lifecycleScope.launch {
                        try {
                            val start = Instant.ofEpochMilli(startMs).atZone(ZoneId.systemDefault()).toLocalDateTime()
                            val end = Instant.ofEpochMilli(endMs).atZone(ZoneId.systemDefault()).toLocalDateTime()
                            
                            Log.d("HEALTHYFAST", "Querying steps from $start to $end")

                            val response = client.aggregateGroupByPeriod(
                                AggregateGroupByPeriodRequest(
                                    metrics = setOf(StepsRecord.COUNT_TOTAL),
                                    timeRangeFilter = TimeRangeFilter.between(start, end),
                                    timeRangeSlicer = Period.ofDays(1)
                                )
                            )

                            // aggregateGroupByPeriod returns a bucket for every day in
                            // the range, defaulting to 0 when Health Connect has no
                            // step records that day (e.g. before the user started
                            // tracking, or before Health Connect sync was set up).
                            // Those phantom zero-days aren't real "0 steps" days, so
                            // they're dropped here rather than passed to Dart — the
                            // Insights average should only count days that actually
                            // have step data.
                            val results = mutableMapOf<String, Long>()
                            for (bucket in response) {
                                val steps = bucket.result[StepsRecord.COUNT_TOTAL] ?: 0L
                                if (steps <= 0L) continue
                                val dateStr = bucket.startTime.toLocalDate().toString()
                                results[dateStr] = steps
                                Log.d("HEALTHYFAST", "Bucket: $dateStr = $steps steps")
                            }
                            result.success(results)
                        } catch (e: Exception) {
                            Log.e("HEALTHYFAST", "Error fetching steps: ${e.message}", e)
                            result.error("HEALTH_ERROR", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isWatch(): Boolean =
        packageManager.hasSystemFeature(PackageManager.FEATURE_WATCH)
}
