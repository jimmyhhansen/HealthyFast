import 'dart:convert';

import 'package:hive/hive.dart';

part 'workout_record.g.dart';

/// A logged strength workout. Set/rep details live in [exercisesJson]
/// (same pattern as MealRecord.foodsJson):
/// [{"n": "Bench press", "sets": [{"kg": 80, "reps": 5}, ...]}]
@HiveType(typeId: 3)
class WorkoutRecord extends HiveObject {
  @HiveField(0)
  late DateTime startTime;

  @HiveField(1)
  late DateTime endTime;

  @HiveField(2)
  late String title;

  @HiveField(3)
  String? exercisesJson;

  @HiveField(4)
  String? programId;

  @HiveField(5)
  int? programDayIdx;

  /// manual | watch | health
  @HiveField(6)
  late String source;

  /// Health Connect activity type name (e.g. "STRENGTH_TRAINING",
  /// "RUNNING"). Null on old records — treated as strength training.
  @HiveField(7)
  String? activityType;

  /// light | moderate | hard — user-reported intensity.
  @HiveField(8)
  String? intensity;

  /// Stable id for cloud sync (Firestore document id). Null on records
  /// created before sync existed — assigned lazily on first sync.
  @HiveField(9)
  String? syncId;

  WorkoutRecord({
    required this.startTime,
    required this.endTime,
    required this.title,
    this.exercisesJson,
    this.programId,
    this.programDayIdx,
    this.source = 'manual',
    this.activityType,
    this.intensity,
    this.syncId,
  });

  Duration get duration => endTime.difference(startTime);

  /// Total lifted volume (kg × reps across all sets), 0 without details.
  double get totalVolumeKg {
    final json = exercisesJson;
    if (json == null) return 0;
    try {
      final list = jsonDecode(json) as List;
      var sum = 0.0;
      for (final e in list) {
        if (e is! Map) continue;
        final sets = e['sets'];
        if (sets is! List) continue;
        for (final s in sets) {
          if (s is! Map) continue;
          sum += ((s['kg'] as num?) ?? 0) * ((s['reps'] as num?) ?? 0);
        }
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  /// Exercise names for compact display.
  List<String> get exerciseNames {
    final json = exercisesJson;
    if (json == null) return const [];
    try {
      final list = jsonDecode(json) as List;
      return [
        for (final e in list)
          if (e is Map && e['n'] is String) e['n'] as String,
      ];
    } catch (_) {
      return const [];
    }
  }
}
