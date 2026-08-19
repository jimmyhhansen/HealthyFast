package com.northernappdev.healthyfast

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Bridges the ML Kit GenAI Prompt API (on-device Gemini Nano) to Flutter.
 * Estimates nutrition values from a free-text meal description — no cloud,
 * no API key, data never leaves the device.
 */
class MealEstimator {

    companion object {
        private const val TAG = "MealEstimator"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val model by lazy { Generation.getClient() }

    fun dispose() = scope.cancel()

    /** Returns "available" | "downloadable" | "downloading" | "unavailable". */
    fun checkStatus(result: MethodChannel.Result) {
        scope.launch {
            try {
                val raw = model.checkStatus()
                Log.d(TAG, "Gemini Nano FeatureStatus = $raw")
                val status = when (raw) {
                    FeatureStatus.AVAILABLE -> "available"
                    FeatureStatus.DOWNLOADABLE -> "downloadable"
                    FeatureStatus.DOWNLOADING -> "downloading"
                    else -> "unavailable"
                }
                result.success(status)
            } catch (e: Exception) {
                Log.e(TAG, "checkStatus failed", e)
                result.success("unavailable")
            }
        }
    }

    /** Downloads Gemini Nano; returns true when the download completes. */
    fun download(result: MethodChannel.Result) {
        scope.launch {
            try {
                var replied = false
                model.download().collect { status ->
                    when (status) {
                        is DownloadStatus.DownloadCompleted -> {
                            if (!replied) { replied = true; result.success(true) }
                        }
                        is DownloadStatus.DownloadFailed -> {
                            if (!replied) { replied = true; result.success(false) }
                        }
                        else -> { /* started / progress */ }
                    }
                }
                if (!replied) result.success(false)
            } catch (e: Exception) {
                result.error("DOWNLOAD_ERROR", e.message, null)
            }
        }
    }

    /** Runs Gemini Nano on the meal description; returns the raw model text. */
    fun estimate(description: String, result: MethodChannel.Result) {
        val prompt = """
            You are a nutrition expert. Estimate the nutritional content of this meal.
            The description may be in Norwegian or English.

            Meal: "$description"

            Respond with ONLY a JSON object, no other text, in exactly this format:
            {"calories": <kcal as integer>, "protein": <grams as integer>, "carbs": <grams as integer>, "fat": <grams as integer>}
        """.trimIndent()

        scope.launch {
            try {
                val response = model.generateContent(
                    generateContentRequest(TextPart(prompt)) {
                        temperature = 0.1f
                        topK = 16
                        maxOutputTokens = 128
                    }
                )
                val text = response.candidates.firstOrNull()?.text ?: ""
                result.success(text)
            } catch (e: Exception) {
                result.error("ESTIMATE_ERROR", e.message, null)
            }
        }
    }

    /**
     * Extracts individual foods with gram estimates from a meal
     * description, for lookup in the Norwegian food composition table
     * (Matvaretabellen). Returns the raw model text (a JSON array).
     */
    fun extractFoods(description: String, result: MethodChannel.Result) {
        val prompt = """
            Break this meal into individual foods with estimated weights.
            The description may be in Norwegian or English.

            Meal: "$description"

            Respond with ONLY a JSON array, no other text, in exactly this
            format, using simple Norwegian food names:
            [{"n": "<food name in Norwegian>", "g": <weight in grams as integer>}]
        """.trimIndent()

        scope.launch {
            try {
                val response = model.generateContent(
                    generateContentRequest(TextPart(prompt)) {
                        temperature = 0.1f
                        topK = 16
                        maxOutputTokens = 256
                    }
                )
                result.success(response.candidates.firstOrNull()?.text ?: "")
            } catch (e: Exception) {
                result.error("EXTRACT_ERROR", e.message, null)
            }
        }
    }

    /**
     * Generates a strength-training program from a free-text description
     * (e.g. "3 days a week, focus on legs and back, I have dumbbells").
     * [exerciseNames] is the curated, guide-backed vocabulary the model must
     * pick from — keeps the output matchable against ExerciseGuides instead
     * of inventing exercises we have no guide/instructions for.
     */
    fun generateProgram(
        description: String,
        exerciseNames: List<String>,
        result: MethodChannel.Result
    ) {
        val vocab = exerciseNames.joinToString(", ")
        val prompt = """
            You are a strength training coach. Design a workout program from
            this request. The request may be in Norwegian or English; reply
            in the same language for "programName" and day "title" values.

            Request: "$description"

            Rules:
            - Only use exercise names from this exact list (copy them
              verbatim, do not translate or invent new ones):
              $vocab
            - 2 to 6 exercises per day, 3 to 8 sets, 5 to 15 reps.
            - Pick a sensible number of days per week from the request (if
              unclear, use 3).
            - Balance muscle groups across the week; do not repeat the same
              exercise twice in one day.

            Respond with ONLY a JSON object, no other text, in exactly this
            format:
            {"programName": "<short name>", "daysPerWeek": "<e.g. 3 days/week>",
             "days": [{"title": "<e.g. Day 1 - Legs>",
                       "exercises": [{"name": "<from the list>", "sets": <int>, "reps": <int>}]}]}
        """.trimIndent()

        scope.launch {
            try {
                val response = model.generateContent(
                    generateContentRequest(TextPart(prompt)) {
                        temperature = 0.2f
                        topK = 16
                        maxOutputTokens = 2048
                    }
                )
                val text = response.candidates.firstOrNull()?.text ?: ""
                Log.d(TAG, "generateProgram raw output (${text.length} chars): $text")
                result.success(text)
            } catch (e: Exception) {
                Log.e(TAG, "generateProgram failed", e)
                result.error("GENERATE_ERROR", e.message, null)
            }
        }
    }

    /**
     * SPIKE: Describes the food in a photo (multimodal Gemini Nano) so the
     * text can be reviewed by the user and then go through the normal
     * estimate flow. On-device only — the photo never leaves the phone.
     * Fails with IMAGE_ERROR on devices without multimodal Nano support.
     */
    fun describeImage(path: String, result: MethodChannel.Result) {
        scope.launch {
            try {
                // Efficiently decode and downscale on a background thread.
                val bitmap = kotlinx.coroutines.withContext(Dispatchers.IO) {
                    decodeAndDownscale(path, 768)
                }
                if (bitmap == null) {
                    result.error("IMAGE_ERROR", "Could not decode image", null)
                    return@launch
                }
                val prompt = """
                    List the foods and drinks visible in this photo with
                    approximate portion sizes, as one short comma-separated
                    description suitable for a nutrition log.
                    Respond with ONLY the description text.
                """.trimIndent()
                val response = model.generateContent(
                    generateContentRequest(ImagePart(bitmap), TextPart(prompt)) {
                        temperature = 0.2f
                        topK = 16
                        maxOutputTokens = 96
                    }
                )
                result.success(response.candidates.firstOrNull()?.text ?: "")
            } catch (e: Exception) {
                Log.e(TAG, "describeImage failed", e)
                result.error("IMAGE_ERROR", e.message, null)
            }
        }
    }

    /**
     * Efficiently decodes and downscales an image from [path] so that its
     * largest side is approximately [maxSide] pixels. Uses inSampleSize to
     * avoid loading the full-resolution bitmap into memory.
     */
    private fun decodeAndDownscale(path: String, maxSide: Int): Bitmap? {
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(path, options)

        val largest = maxOf(options.outWidth, options.outHeight)
        if (largest <= 0) return null

        // Calculate inSampleSize: the power-of-two scaling factor.
        var inSampleSize = 1
        if (largest > maxSide) {
            val halfLargest = largest / 2
            while (halfLargest / inSampleSize >= maxSide) {
                inSampleSize *= 2
            }
        }

        val decodeOptions = BitmapFactory.Options().apply {
            this.inSampleSize = inSampleSize
        }
        val sampled = BitmapFactory.decodeFile(path, decodeOptions) ?: return null

        // sampled is now at most 2x the target size. Perfect it with
        // createScaledBitmap for the exact fit Gemini Nano expects.
        val currentLargest = maxOf(sampled.width, sampled.height)
        if (currentLargest <= maxSide) return sampled

        val scale = maxSide.toFloat() / currentLargest
        return Bitmap.createScaledBitmap(
            sampled,
            (sampled.width * scale).toInt(),
            (sampled.height * scale).toInt(),
            true
        ).also {
            if (it != sampled) sampled.recycle()
        }
    }
}
