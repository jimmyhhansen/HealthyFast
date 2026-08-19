import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'debug_log_service.dart';

/// Thrown when the server-side daily usage cap has been hit (per-user or
/// app-wide — see enforceUsageCap in functions/index.js). Callers should
/// catch this specifically to show the real reason, rather than the
/// generic "AI could not process this" message used for other failures.
class CloudAiQuotaExceededException implements Exception {
  CloudAiQuotaExceededException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cloud fallback/upgrade for meal estimates, meal photo scanning and AI
/// program generation —
/// used automatically on phones that can't run Gemini Nano on-device, or
/// on any phone when the user opts into "smarter cloud AI" (a premium
/// feature — see PurchaseProvider). Only ever called after the user has
/// explicitly consented via [resolveCloudAiUsage]/[resolveAiPath] (see
/// cloud_ai_consent_sheet.dart). Sends the same prompts as the on-device
/// path, but processed by Google's Gemini API through a Firebase Cloud
/// Function (see functions/index.js), so no API key ships inside the app.
///
/// Every call requires Firebase Auth (anonymous sign-in is used — see
/// [_ensureSignedIn]) so the server can enforce a per-user daily cap
/// against abuse/runaway cost, on top of an app-wide daily cap.
///
/// Deployed via `firebase deploy --only functions`, authenticated to
/// Vertex AI via the function's own service account (see functions/index.js
/// doc comment) — no API key anywhere. Errors are swallowed for the user
/// (falls back to manual entry the same as "AI unavailable"), but logged
/// with debugPrint — check `flutter logs` / Logcat, or cross-reference
/// with `firebase functions:log` for the server-side half of the story.
class CloudAiService {
  CloudAiService._();

  static final _functions = FirebaseFunctions.instance;

  /// Cloud AI requires a *real* (non-anonymous) Firebase Auth session —
  /// the same Google account used for Cloud Backup. This used to accept
  /// anonymous sign-in, but that's free to mint in unlimited quantity,
  /// which let anyone reset their own per-uid daily cap in
  /// functions/index.js's enforceUsageCap just by re-authenticating.
  ///
  /// Every call site (cloud_ai_consent_sheet.dart's ensureCloudSignIn) is
  /// supposed to establish a real sign-in *before* ever reaching this
  /// class, since only that layer has a BuildContext to show the Google
  /// sign-in flow. This method doesn't establish sign-in — it asserts the
  /// invariant, so a gap in that UI-side gating fails loudly here (and is
  /// caught by [_call]'s catch-all) instead of silently falling back to
  /// anonymous auth, which functions/index.js now rejects anyway.
  static Future<void> _ensureSignedIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      await DebugLogService.log('CloudAI',
          'no real (non-anonymous) sign-in present — refusing to call Cloud AI');
      throw StateError(
          'Cloud AI requires signing in with Google first (Settings → Cloud & AI).');
    }
    await DebugLogService.log('CloudAI', 'using signed-in uid=${user.uid}');
  }

  /// Mirrors MealEstimatorService.estimate — same parse contract.
  static Future<String?> estimateMeal(String description) =>
      _call('meal', {'description': description});

  /// Mirrors MealEstimatorService.extractFoods.
  static Future<String?> extractFoods(String description) =>
      _call('foods', {'description': description});

  /// Mirrors MealEstimatorService.describePhoto — same prompt/output
  /// contract (a short comma-separated food description), but processed by
  /// Gemini's cloud multimodal model. Used when the phone either has no
  /// Gemini Nano at all, or has Nano for text but not for images (some
  /// devices support one and not the other) — see meals_screen.dart
  /// _scanPhoto for how the two on-device outcomes route here. The photo
  /// is base64-encoded client-side; it's already been resized to 1280px
  /// wide / 85% quality by the image picker before this is called, so the
  /// upload stays small.
  ///
  /// Deliberately does NOT catch its own errors the way the other methods'
  /// callers might expect — [_call] already catches and logs client/server
  /// errors, but it *rethrows* [CloudAiQuotaExceededException] on purpose so
  /// callers can show the real reason. Catching broadly here would swallow
  /// that before it reaches _scanPhoto's quota handling.
  static Future<String?> describeMealPhoto(String path) async {
    late final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      await DebugLogService.log(
          'CloudAI', 'describeMealPhoto: could not read file $path: $e');
      rethrow;
    }
    await DebugLogService.log(
        'CloudAI', 'describeMealPhoto: read ${bytes.length} bytes from $path');
    final b64 = base64Encode(bytes);
    await DebugLogService.log(
        'CloudAI', 'describeMealPhoto: base64 payload=${b64.length} chars');
    return _call('mealPhoto', {'imageBase64': b64});
  }

  /// Mirrors TrainingAiService.generateProgram.
  static Future<String?> generateProgram(
          String description, List<String> exerciseNames) =>
      _call('program', {
        'description': description,
        'exerciseNames': exerciseNames,
      });

  static Future<String?> _call(String kind, Map<String, dynamic> args) async {
    final sw = Stopwatch()..start();
    try {
      await _ensureSignedIn();
      // Matches the 120s timeoutSeconds set on generateAiText in
      // functions/index.js. The plugin default (~60s) was shorter than
      // what the newer Gemini model sometimes needs for the "program" kind,
      // so calls could time out client-side even though the function would
      // have finished if given more time — the client gave up right as the
      // symptom "fails, then works on retry" would predict.
      final callable = _functions.httpsCallable(
        'generateAiText',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      await DebugLogService.log('CloudAI', '"$kind" calling generateAiText…');
      final result = await callable.call<Map<String, dynamic>>({
        'kind': kind,
        ...args,
      });
      final text = result.data['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        debugPrint('[CloudAI] "$kind" returned an empty response — check '
            '`firebase functions:log` for what Gemini actually replied.');
        await DebugLogService.log('CloudAI',
            '"$kind" returned empty response after ${sw.elapsedMilliseconds}ms');
        return null;
      }
      await DebugLogService.log('CloudAI',
          '"$kind" succeeded in ${sw.elapsedMilliseconds}ms, response length=${text.length}');
      return text;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        // Daily cap hit (per-user or app-wide, see enforceUsageCap in
        // functions/index.js) — a real, user-facing reason, not a generic
        // failure. Let the caller show it directly instead of the usual
        // "could not process" message.
        await DebugLogService.log(
            'CloudAI', '"$kind" quota exceeded: ${e.message}');
        throw CloudAiQuotaExceededException(
            e.message ?? 'Daily cloud AI limit reached. Try again tomorrow.');
      }
      // Surfaces the server-side HttpsError code/message directly — e.g.
      // "failed-precondition: Gemini API key not configured", or a Gemini
      // API error forwarded from the function.
      debugPrint('[CloudAI] "$kind" failed: ${e.code} — ${e.message}');
      await DebugLogService.log('CloudAI',
          '"$kind" FirebaseFunctionsException after ${sw.elapsedMilliseconds}ms: '
          'code=${e.code} message=${e.message} details=${e.details}');
      return null;
    } catch (e) {
      debugPrint('[CloudAI] "$kind" failed (client-side): $e');
      await DebugLogService.log('CloudAI',
          '"$kind" client-side error after ${sw.elapsedMilliseconds}ms: '
          '${e.runtimeType}: $e');
      return null;
    }
  }
}
