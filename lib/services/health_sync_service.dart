import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fast_record.dart';

/// Syncs completed fasts to Google Health Connect.
///
/// Health Connect has no native "fasting" record type, so each completed
/// fast is written as a zero-calorie Nutrition record spanning the fast
/// window, with a descriptive name (e.g. "Fast completed — 16:8, 16h 32m").
class HealthSyncService {
  HealthSyncService._();

  static final Health _health = Health();
  static const String _prefKey = 'health_sync_enabled';
  static bool _configured = false;
  static const _healthChannel = MethodChannel('healthyfast/health');

  static Future<void> _ensureConfigured() async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Requests Health Connect permission to write nutrition records and to
  /// read/write weight. Returns true if granted and sync is now enabled.
  static Future<bool> enable() async {
    try {
      await _ensureConfigured();
      final granted = await _health.requestAuthorization(
        [
          HealthDataType.NUTRITION,
          HealthDataType.WEIGHT,
          HealthDataType.WEIGHT,
        ],
        permissions: [
          HealthDataAccess.WRITE,
          HealthDataAccess.READ,
          HealthDataAccess.WRITE,
        ],
      );
      if (granted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_prefKey, true);
      }
      return granted;
    } catch (e) {
      debugPrint('HealthSyncService.enable failed: $e');
      return false;
    }
  }

  static Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
  }

  /// Requests Health Connect nutrition write permission without touching
  /// the fast-sync preference. Used by meal logging.
  static Future<bool> ensureNutritionPermission() async {
    try {
      await _ensureConfigured();
      final has = await _health.hasPermissions(
        [HealthDataType.NUTRITION],
        permissions: [HealthDataAccess.WRITE],
      );
      if (has == true) return true;
      return await _health.requestAuthorization(
        [HealthDataType.NUTRITION],
        permissions: [HealthDataAccess.WRITE],
      );
    } catch (e) {
      debugPrint('HealthSyncService.ensureNutritionPermission failed: $e');
      return false;
    }
  }

  /// Writes a meal with nutrition values to Health Connect.
  /// Returns true on success.
  static Future<bool> logMeal({
    required String name,
    required MealType mealType,
    required DateTime time,
    required double calories,
    double? protein,
    double? carbs,
    double? fat,
  }) async {
    try {
      await _ensureConfigured();
      return await _health.writeMeal(
        mealType: mealType,
        startTime: time.subtract(const Duration(minutes: 15)),
        endTime: time,
        caloriesConsumed: calories,
        protein: protein,
        carbohydrates: carbs,
        fatTotal: fat,
        name: name,
        recordingMethod: RecordingMethod.manual,
      );
    } catch (e) {
      debugPrint('HealthSyncService.logMeal failed: $e');
      return false;
    }
  }

  static Future<bool> _hasNutritionWrite() async {
    try {
      await _ensureConfigured();
      return (await _health.hasPermissions(
            [HealthDataType.NUTRITION],
            permissions: [HealthDataAccess.WRITE],
          )) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the Health Connect nutrition record we wrote for a meal, so a
  /// meal deleted in the app isn't re-imported from Health Connect. Matches
  /// the exact window [logMeal] writes ([time-15min, time]). Health Connect
  /// only lets an app delete records it owns, so meals written by other apps
  /// are never touched. No-op (no prompt) when we lack nutrition permission.
  static Future<void> deleteMeal({required DateTime time}) async {
    if (!await _hasNutritionWrite()) return;
    try {
      await _health.delete(
        type: HealthDataType.NUTRITION,
        startTime: time.subtract(const Duration(minutes: 15)),
        endTime: time,
      );
    } catch (e) {
      debugPrint('HealthSyncService.deleteMeal failed: $e');
    }
  }

  /// Sleep stage types to read. Health Connect (Android) exposes a single
  /// SLEEP_SESSION record; HealthKit (iOS) has no such type — it reports
  /// stage-level samples instead, so we read the stages that make up a
  /// night's sleep. These don't overlap in time within one data source
  /// (a night is either plain "asleep" samples from simple tracking, or
  /// Core/Deep/REM samples from staged tracking, never both at once), so
  /// summing them in [readSleepMinutesPerDay] doesn't double-count.
  static List<HealthDataType> get _sleepTypes =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? const [
              HealthDataType.SLEEP_ASLEEP,
              HealthDataType.SLEEP_DEEP,
              HealthDataType.SLEEP_REM,
            ]
          : const [HealthDataType.SLEEP_SESSION];

  static List<HealthDataType> get _readTypes => [
        HealthDataType.NUTRITION,
        HealthDataType.WEIGHT,
        HealthDataType.WORKOUT,
        HealthDataType.STEPS,
        ..._sleepTypes,
      ];

  /// Requests READ access for meals, weight, workouts, steps and sleep —
  /// used by the manual "fetch from Health" import. Returns true when
  /// granted.
  static Future<bool> ensureReadPermissions() async {
    try {
      await _ensureConfigured();
      final perms = [for (final _ in _readTypes) HealthDataAccess.READ];
      final has =
          await _health.hasPermissions(_readTypes, permissions: perms);
      if (has == true) return true;
      return await _health.requestAuthorization(_readTypes,
          permissions: perms);
    } catch (e) {
      debugPrint('HealthSyncService.ensureReadPermissions failed: $e');
      return false;
    }
  }

  /// Steps per day since [since] (aggregated per day).
  static Future<Map<DateTime, int>> readStepsPerDay({
    required DateTime since,
  }) async {
    try {
      await _ensureConfigured();

      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final result = await _healthChannel.invokeMapMethod<String, int>(
            'getDailySteps',
            {
              'startMs': since.millisecondsSinceEpoch,
              'endMs': DateTime.now().millisecondsSinceEpoch,
            },
          );
          if (result != null) {
            return result.map((key, value) {
              final parts = key.split('-');
              final date = DateTime(int.parse(parts[0]), int.parse(parts[1]),
                  int.parse(parts[2]));
              return MapEntry(date, value);
            });
          }
        } catch (e) {
          debugPrint('HealthSyncService.readStepsPerDay native failed: $e');
          // Fallback to legacy summing if native aggregation fails
        }
      }

      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.STEPS],
        startTime: since,
        endTime: DateTime.now(),
      );
      final map = <DateTime, int>{};
      for (final p in points) {
        final v = p.value;
        if (v is! NumericHealthValue) continue;
        final day =
            DateTime(p.dateFrom.year, p.dateFrom.month, p.dateFrom.day);
        map[day] = (map[day] ?? 0) + v.numericValue.round();
      }
      return map;
    } catch (e) {
      debugPrint('HealthSyncService.readStepsPerDay failed: $e');
      return const {};
    }
  }

  /// Sleep minutes per day since [since]. A session counts toward the
  /// day it ENDS on (the night's sleep belongs to the morning after).
  static Future<Map<DateTime, int>> readSleepMinutesPerDay({
    required DateTime since,
  }) async {
    try {
      await _ensureConfigured();
      final points = await _health.getHealthDataFromTypes(
        types: _sleepTypes,
        startTime: since,
        endTime: DateTime.now(),
      );
      final map = <DateTime, int>{};
      for (final p in points) {
        final day = DateTime(p.dateTo.year, p.dateTo.month, p.dateTo.day);
        map[day] =
            (map[day] ?? 0) + p.dateTo.difference(p.dateFrom).inMinutes;
      }
      return map;
    } catch (e) {
      debugPrint('HealthSyncService.readSleepMinutesPerDay failed: $e');
      return const {};
    }
  }

  /// Reads meals from Health Connect since [since]. Returns raw points;
  /// the provider filters and dedupes.
  static Future<List<HealthDataPoint>> readMeals({
    required DateTime since,
  }) async {
    try {
      await _ensureConfigured();
      return await _health.getHealthDataFromTypes(
        types: [HealthDataType.NUTRITION],
        startTime: since,
        endTime: DateTime.now(),
      );
    } catch (e) {
      debugPrint('HealthSyncService.readMeals failed: $e');
      return const [];
    }
  }

  /// Writes a strength workout summary to Health Connect. Set/rep details
  /// stay in the app (the HC plugin doesn't carry them). No-op when sync
  /// is disabled.
  /// Health Connect activity types the app exposes for logging.
  /// Keys are HealthWorkoutActivityType.name values.
  static const workoutTypes = <String, String>{
    'STRENGTH_TRAINING': 'Strength training',
    'RUNNING': 'Running',
    'WALKING': 'Walking',
    'BIKING': 'Biking',
    'SWIMMING_POOL': 'Swimming',
    'HIGH_INTENSITY_INTERVAL_TRAINING': 'HIIT',
    'YOGA': 'Yoga',
    'PILATES': 'Pilates',
    'ROWING': 'Rowing',
    'ELLIPTICAL': 'Elliptical',
    'HIKING': 'Hiking',
    'OTHER': 'Other',
  };

  static HealthWorkoutActivityType _activityFor(String? name) {
    for (final t in HealthWorkoutActivityType.values) {
      if (t.name == name) return t;
    }
    return HealthWorkoutActivityType.STRENGTH_TRAINING;
  }

  static Future<bool> logWorkout({
    required String title,
    required DateTime start,
    required DateTime end,
    String? activityType,
  }) async {
    try {
      if (!await isEnabled()) return false;
      await _ensureConfigured();
      final has = await _health.hasPermissions(
        [HealthDataType.WORKOUT],
        permissions: [HealthDataAccess.WRITE],
      );
      if (has != true) {
        final ok = await _health.requestAuthorization(
          [HealthDataType.WORKOUT],
          permissions: [HealthDataAccess.WRITE],
        );
        if (!ok) return false;
      }
      return await _health.writeWorkoutData(
        activityType: _activityFor(activityType),
        start: start,
        end: end,
        title: title,
      );
    } catch (e) {
      debugPrint('HealthSyncService.logWorkout failed: $e');
      return false;
    }
  }

  /// Deletes the Health Connect workout record we wrote for a workout, so a
  /// workout deleted in the app isn't re-imported from Health Connect. Only
  /// removes records this app owns.
  static Future<void> deleteWorkout({
    required DateTime start,
    required DateTime end,
  }) async {
    if (!await isEnabled()) return;
    try {
      await _ensureConfigured();
      await _health.delete(
        type: HealthDataType.WORKOUT,
        startTime: start,
        endTime: end,
      );
    } catch (e) {
      debugPrint('HealthSyncService.deleteWorkout failed: $e');
    }
  }

  /// Reads workouts from Health Connect since [since]. Returns
  /// (start, end, title, activityTypeName); empty when permission is
  /// missing.
  static Future<List<(DateTime, DateTime, String, String)>> readWorkouts({
    required DateTime since,
  }) async {
    try {
      await _ensureConfigured();
      // No hasPermissions pre-check (returns null for READ on Android
      // even when granted — see readWeights).
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: since,
        endTime: DateTime.now(),
      );
      return [
        for (final p in points)
          if (p.value is WorkoutHealthValue)
            (
              p.dateFrom,
              p.dateTo,
              _workoutTitle(p.value as WorkoutHealthValue),
              (p.value as WorkoutHealthValue).workoutActivityType.name,
            ),
      ];
    } catch (e) {
      debugPrint('HealthSyncService.readWorkouts failed: $e');
      return const [];
    }
  }

  static String _workoutTitle(WorkoutHealthValue v) {
    final raw = v.workoutActivityType.name.replaceAll('_', ' ').toLowerCase();
    return raw.isEmpty
        ? 'Workout'
        : raw[0].toUpperCase() + raw.substring(1);
  }

  /// Requests read+write access to weight without touching the fast-sync
  /// preference.
  static Future<bool> ensureWeightPermission() async {
    try {
      await _ensureConfigured();
      final has = await _health.hasPermissions(
        [HealthDataType.WEIGHT, HealthDataType.WEIGHT],
        permissions: [HealthDataAccess.READ, HealthDataAccess.WRITE],
      );
      if (has == true) return true;
      return await _health.requestAuthorization(
        [HealthDataType.WEIGHT, HealthDataType.WEIGHT],
        permissions: [HealthDataAccess.READ, HealthDataAccess.WRITE],
      );
    } catch (e) {
      debugPrint('HealthSyncService.ensureWeightPermission failed: $e');
      return false;
    }
  }

  /// Writes a weight to Health Connect. No-op when sync is disabled.
  static Future<bool> logWeight({
    required double kg,
    required DateTime time,
  }) async {
    try {
      if (!await isEnabled()) return false;
      await _ensureConfigured();
      return await _health.writeHealthData(
        value: kg,
        type: HealthDataType.WEIGHT,
        startTime: time,
        endTime: time,
        recordingMethod: RecordingMethod.manual,
      );
    } catch (e) {
      debugPrint('HealthSyncService.logWeight failed: $e');
      return false;
    }
  }

  /// Deletes a weight record from Health Connect. Only removes records this
  /// app owns.
  static Future<void> deleteWeight({required DateTime time}) async {
    if (!await isEnabled()) return;
    try {
      await _ensureConfigured();
      await _health.delete(
        type: HealthDataType.WEIGHT,
        startTime: time,
        endTime: time,
      );
    } catch (e) {
      debugPrint('HealthSyncService.deleteWeight failed: $e');
    }
  }

  /// Reads weights from Health Connect since [since]. Returns (time, kg)
  /// pairs; empty when read permission is missing. Not gated on the
  /// auto-sync toggle: the manual "Fetch from Health" button must work
  /// regardless — the permission check below is the real gate.
  static Future<List<(DateTime, double)>> readWeights({
    required DateTime since,
  }) async {
    try {
      await _ensureConfigured();
      // NOTE: no hasPermissions pre-check — on Android it returns null
      // for READ permissions even when granted, which silently skipped
      // the read. Just attempt it; unauthorized reads come back empty.
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: since,
        endTime: DateTime.now(),
      );
      return [
        for (final p in points)
          if (p.value is NumericHealthValue)
            (
              p.dateFrom,
              (p.value as NumericHealthValue).numericValue.toDouble()
            ),
      ];
    } catch (e) {
      debugPrint('HealthSyncService.readWeights failed: $e');
      return const [];
    }
  }

  /// Writes a completed fast to Health Connect. No-op when sync is disabled.
  /// Returns true on success.
  static Future<bool> syncFast(FastRecord record) async {
    try {
      if (!await isEnabled()) return false;
      await _ensureConfigured();
      return await _health.writeMeal(
        mealType: MealType.UNKNOWN,
        startTime: record.startTime,
        endTime: record.endTime,
        caloriesConsumed: 0,
        name:
            'Fast completed — ${record.protocol}, ${record.formattedDuration}',
        recordingMethod: RecordingMethod.manual,
      );
    } catch (e) {
      debugPrint('HealthSyncService.syncFast failed: $e');
      return false;
    }
  }
}
