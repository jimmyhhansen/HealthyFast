import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Drives the Wear OS Ongoing Activity for an active fast.
///
/// When a fast is running the native watch build posts an ongoing
/// notification that carries an [OngoingActivity]; Wear then surfaces it on
/// the watch face, in Recents, and (via the Tile) in the tile carousel —
/// satisfying the "ongoing activity" quality guideline.
///
/// The indicator is always shown while a fast is running (the Wear quality
/// guidelines require it, so it is intentionally not user-configurable).
/// All methods are no-ops on the phone (the native side checks FEATURE_WATCH).
class OngoingActivityService {
  OngoingActivityService._();

  static const _channel = MethodChannel('healthyfast/wear');

  /// Starts or updates the ongoing activity for an active fast.
  static Future<void> start({
    required int startMs,
    required int goalHours,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startOngoing', {
        'startMs': startMs,
        'goalHours': goalHours,
      });
    } catch (_) {
      // Phone build, or the service isn't available — safe to ignore.
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopOngoing');
    } catch (_) {
      // Phone build, or nothing running — safe to ignore.
    }
  }

  /// Starts or updates the ongoing activity for an active workout.
  ///
  /// Independent of [start]/[stop] for fasting — a workout and a fast can
  /// be tracked at the same time, each with its own chip/timer, because the
  /// native side uses a separate notification id/foreground service.
  static Future<void> startWorkout({
    required int startMs,
    required String title,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startOngoingWorkout', {
        'startMs': startMs,
        'title': title,
      });
    } catch (_) {
      // Phone build, or the service isn't available — safe to ignore.
    }
  }

  static Future<void> stopWorkout() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopOngoingWorkout');
    } catch (_) {
      // Phone build, or nothing running — safe to ignore.
    }
  }

  /// Triggers a refresh of the Wear OS Tile.
  static Future<void> refreshTiles() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('refreshTiles');
    } catch (_) {
      // Phone build, or Tile not available — safe to ignore.
    }
  }
}
