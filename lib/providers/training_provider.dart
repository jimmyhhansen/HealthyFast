import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/custom_programs_service.dart';
import '../services/exercise_guides.dart';
import '../services/training_programs.dart';

/// One set in an in-progress workout session.
class ActiveSet {
  ActiveSet({required this.kg, required this.reps, this.done = false});
  double kg;
  int reps;
  bool done;

  Map<String, dynamic> toJson() => {'kg': kg, 'reps': reps, 'done': done};
  factory ActiveSet.fromJson(Map m) => ActiveSet(
        kg: ((m['kg'] as num?) ?? 20).toDouble(),
        reps: ((m['reps'] as num?) ?? 5).toInt(),
        done: m['done'] == true,
      );
}

/// One exercise in an in-progress session.
class ActiveExercise {
  ActiveExercise({
    required this.name,
    required this.targetSets,
    required this.targetReps,
    required this.sets,
    this.cue = '',
  });
  final String name;
  final int targetSets;
  final int targetReps;
  final String cue;
  final List<ActiveSet> sets;

  bool get succeeded =>
      sets.length >= targetSets &&
      sets.every((s) => s.done) &&
      sets.every((s) => s.reps >= targetReps);

  Map<String, dynamic> toJson() => {
        'n': name,
        'tSets': targetSets,
        'tReps': targetReps,
        'cue': cue,
        'sets': [for (final s in sets) s.toJson()],
      };
  factory ActiveExercise.fromJson(Map m) => ActiveExercise(
        name: m['n'] as String? ?? 'Exercise',
        targetSets: ((m['tSets'] as num?) ?? 3).toInt(),
        targetReps: ((m['tReps'] as num?) ?? 5).toInt(),
        cue: m['cue'] as String? ?? '',
        sets: [
          for (final s in (m['sets'] as List? ?? const []))
            if (s is Map) ActiveSet.fromJson(s),
        ],
      );
}

/// An in-progress workout. Lives in the provider (NOT the screen), so
/// backing out of the session screen never loses it — it stays "in
/// progress" until finished or cancelled, surviving app restarts too.
class ActiveWorkoutSession {
  ActiveWorkoutSession({
    required this.dayTitle,
    required this.startedAt,
    required this.exercises,
    this.programId,
    this.dayIdxInSplit,
    this.intensity = 'moderate',
  });

  final String dayTitle;
  final DateTime startedAt;
  final String? programId;
  final int? dayIdxInSplit;
  String intensity;
  final List<ActiveExercise> exercises;

  Map<String, dynamic> toJson() => {
        'title': dayTitle,
        'startedMs': startedAt.millisecondsSinceEpoch,
        'programId': programId,
        'dayIdx': dayIdxInSplit,
        'intensity': intensity,
        'exercises': [for (final e in exercises) e.toJson()],
      };
  factory ActiveWorkoutSession.fromJson(Map m) => ActiveWorkoutSession(
        dayTitle: m['title'] as String? ?? 'Workout',
        startedAt: DateTime.fromMillisecondsSinceEpoch(
            ((m['startedMs'] as num?) ?? 0).toInt()),
        programId: m['programId'] as String?,
        dayIdxInSplit: (m['dayIdx'] as num?)?.toInt(),
        intensity: m['intensity'] as String? ?? 'moderate',
        exercises: [
          for (final e in (m['exercises'] as List? ?? const []))
            if (e is Map) ActiveExercise.fromJson(e),
        ],
      );
}

/// Program state: which program the user runs, where they are in the
/// rotation, current working weights and failure counts (for deloads).
/// Progression: +increment on a fully completed exercise, deload −10%
/// (rounded to 2.5 kg) after three failed attempts — the StrongLifts
/// rules, applied to all bundled programs.
class TrainingProvider extends ChangeNotifier {
  static const _kState = 'training_state';
  static const _kActiveSession = 'active_session';

  ActiveWorkoutSession? _active;

  /// The in-progress workout, if any — survives navigation and restarts.
  ActiveWorkoutSession? get activeSession => _active;

  /// Starts (and persists) a session from a program day, prefilled with
  /// the current progression weights.
  Future<ActiveWorkoutSession> startSession(ProgramDay day) async {
    final session = ActiveWorkoutSession(
      dayTitle: day.title,
      startedAt: DateTime.now(),
      programId: _programId,
      dayIdxInSplit:
          program == null ? null : _dayIdx % program!.days.length,
      exercises: [
        for (final e in day.exercises)
          ActiveExercise(
            name: e.name,
            targetSets: e.sets,
            targetReps: e.reps,
            cue: e.cue,
            sets: [
              for (var i = 0; i < e.sets; i++)
                ActiveSet(kg: weightFor(e, i), reps: repsFor(e, i)),
            ],
          ),
      ],
    );
    _active = session;
    notifyListeners();
    await persistSession();
    return session;
  }

  /// Saves the session's current state so process death loses nothing.
  Future<void> persistSession() async {
    final prefs = await SharedPreferences.getInstance();
    final s = _active;
    if (s == null) {
      await prefs.remove(_kActiveSession);
    } else {
      await prefs.setString(_kActiveSession, jsonEncode(s.toJson()));
    }
  }

  Future<void> cancelSession() async {
    _active = null;
    notifyListeners();
    await persistSession();
  }

  /// Called after the workout is saved to history.
  Future<void> clearSession() => cancelSession();

  /// Updates the active session from a remote source (sync).
  Future<void> syncActiveSession(Map? m) async {
    if (m == null) {
      _active = null;
    } else {
      try {
        _active = ActiveWorkoutSession.fromJson(m);
      } catch (_) {
        _active = null;
      }
    }
    notifyListeners();
    await persistSession();
  }

  // Default to the first bundled program (Full-body Basics) on a fresh
  // install; init() overwrites this with the last-used program when a saved
  // state exists.
  String? _programId = TrainingPrograms.all.first.id;
  int _dayIdx = 0;
  Map<String, List<double>> _weights = {};
  Map<String, List<int>> _reps = {};
  Map<String, int> _fails = {};
  bool _rememberGlobally = true;
  List<Program> _custom = [];

  String? get programId => _programId;
  int get dayIdx => _dayIdx;
  bool get rememberGlobally => _rememberGlobally;

  /// Bundled + user-created programs.
  List<Program> get availablePrograms =>
      [...TrainingPrograms.all, ..._custom];

  Program? get program {
    if (_programId == null) return null;
    for (final p in availablePrograms) {
      if (p.id == _programId) return p;
    }
    return null;
  }

  /// Reloads user-created programs (after editing in Settings).
  Future<void> refreshCustomPrograms() async {
    _custom = await CustomProgramsService.load();
    notifyListeners();
  }

  ProgramDay? get nextDay {
    final p = program;
    if (p == null || p.days.isEmpty) return null;
    return p.days[_dayIdx % p.days.length];
  }

  double weightFor(ProgramExercise e, int setIndex) {
    final list = _weights[e.name];
    if (list != null && list.length > setIndex) {
      return list[setIndex];
    }
    // Fallback to the first set's weight, then the program's start weight.
    return list?.firstOrNull ?? e.startKg;
  }

  int repsFor(ProgramExercise e, int setIndex) {
    final list = _reps[e.name];
    if (list != null && list.length > setIndex) {
      return list[setIndex];
    }
    // Fallback to the first set's reps, then the program's target reps.
    return list?.firstOrNull ?? e.reps;
  }

  Future<void> init() async {
    try {
      await ExerciseGuides.init();
      _custom = await CustomProgramsService.load();
      final prefs = await SharedPreferences.getInstance();
      // Restore an in-progress session (e.g. after process death) —
      // before the early return below, so it never gets skipped.
      final sessionRaw = prefs.getString(_kActiveSession);
      if (sessionRaw != null && sessionRaw.isNotEmpty) {
        try {
          _active =
              ActiveWorkoutSession.fromJson(jsonDecode(sessionRaw) as Map);
        } catch (_) {}
      }
      final raw = prefs.getString(_kState);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map;
      _programId = m['programId'] as String?;
      _dayIdx = (m['dayIdx'] as num?)?.toInt() ?? 0;
      _rememberGlobally = m['rememberGlobally'] as bool? ?? true;
      _weights = ((m['weights'] as Map?) ?? {}).map((k, v) {
        if (v is List) {
          return MapEntry(
              k as String, v.map((e) => (e as num).toDouble()).toList());
        }
        // Migration: convert old single double to a list
        return MapEntry(k as String, [(v as num).toDouble()]);
      });
      _reps = ((m['reps'] as Map?) ?? {}).map((k, v) {
        if (v is List) {
          return MapEntry(
              k as String, v.map((e) => (e as num).toInt()).toList());
        }
        return MapEntry(k as String, [(v as num).toInt()]);
      });
      _fails = ((m['fails'] as Map?) ?? {})
          .map((k, v) => MapEntry(k as String, (v as num).toInt()));
      notifyListeners();
    } catch (e) {
      debugPrint('[TRAIN] init failed: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kState,
        jsonEncode({
          'programId': _programId,
          'dayIdx': _dayIdx,
          'weights': _weights,
          'reps': _reps,
          'fails': _fails,
          'rememberGlobally': _rememberGlobally,
        }));
  }

  /// Selects a program, optionally starting at a specific day in the
  /// rotation (e.g. jump straight to "Legs").
  Future<void> selectProgram(String id, {int startDayIdx = 0}) async {
    _programId = id;
    _dayIdx = startDayIdx;
    if (!_rememberGlobally) {
      _weights = {};
      _reps = {};
      _fails = {};
    }
    notifyListeners();
    await _save();
  }

  Future<void> setRememberGlobally(bool value) async {
    _rememberGlobally = value;
    notifyListeners();
    await _save();
  }

  /// Jumps the rotation to a specific day without touching weights.
  Future<void> setDayIdx(int idx) async {
    _dayIdx = idx;
    notifyListeners();
    await _save();
  }

  /// Display name for a program id (bundled or custom), or null.
  String? programNameById(String? id) {
    if (id == null) return null;
    for (final p in availablePrograms) {
      if (p.id == id) return p.name;
    }
    return null;
  }

  Future<void> clearProgram() async {
    _programId = null;
    notifyListeners();
    await _save();
  }

  /// Manual weight override.
  Future<void> setWeight(String exercise, double kg, {int setIndex = 0}) async {
    final list = _weights[exercise] ?? [];
    if (list.length <= setIndex) {
      // Grow list if needed
      final newList = List<double>.filled(setIndex + 1, list.firstOrNull ?? kg);
      for (var i = 0; i < list.length; i++) {
        newList[i] = list[i];
      }
      _weights[exercise] = newList;
    }
    _weights[exercise]![setIndex] = kg;
    notifyListeners();
    await _save();
  }

  static double _roundTo2p5(double v) => (v / 2.5).round() * 2.5;

  /// Applies progression after a finished workout. [succeeded] maps
  /// exercise name → whether all planned sets × reps were completed.
  /// [usedKg] is the weight actually lifted per set.
  /// [usedReps] is the reps actually performed per set.
  Future<void> completeWorkout(ProgramDay day, Map<String, bool> succeeded,
      {Map<String, List<double>>? usedKg, Map<String, List<int>>? usedReps}) async {
    final p = program;
    if (p == null) return;
    for (final e in day.exercises) {
      final currentKg = usedKg?[e.name] ?? _weights[e.name] ?? [e.startKg];
      final currentReps = usedReps?[e.name] ?? _reps[e.name] ?? [e.reps];
      
      // We no longer auto-increment. We remember exactly what was lifted
      // (or attempted) last time as the new baseline.
      _weights[e.name] = currentKg;
      _reps[e.name] = currentReps;
      _fails[e.name] = succeeded[e.name] == true ? 0 : (_fails[e.name] ?? 0) + 1;
      
      // Deload logic (optional, keeping it for now if user fails 3 times)
      if (_fails[e.name]! >= 3) {
        _weights[e.name] = currentKg
            .map((w) => _roundTo2p5(w * 0.9).clamp(e.startKg, 999.0))
            .toList();
        _fails[e.name] = 0;
      }
    }
    _dayIdx++;
    notifyListeners();
    await _save();
  }

  /// The FULL program (all days, current weights) as JSON for the watch,
  /// so workouts can be chosen and logged standalone on the wrist.
  String programJson() {
    final p = program;
    if (p == null) return '';
    return jsonEncode({
      'name': p.name,
      'dayIdx': _dayIdx,
      'days': [
        for (final d in p.days)
          {
            'title': d.title,
            'exercises': [
              for (final e in d.exercises)
                {
                  'n': e.name,
                  'sets': e.sets,
                  'reps': repsFor(e, 0),
                  'kg': weightFor(e, 0),
                },
            ],
          },
      ],
    });
  }

  /// Next workout as JSON for the watch (tile + on-watch logging).
  String nextWorkoutJson() {
    final p = program;
    final day = nextDay;
    if (day == null || p == null) return '';
    return jsonEncode({
      'pName': p.name,
      'title': day.title,
      'dayIdx': _dayIdx,
      'exercises': [
        for (final e in day.exercises)
          {
            'n': e.name,
            'sets': e.sets,
            'reps': repsFor(e, 0),
            'kg': weightFor(e, 0),
          },
      ],
    });
  }

  /// All available programs (bundled + custom) for selection on the watch.
  String allProgramsJson() {
    return jsonEncode([for (final p in availablePrograms) p.toJson()]);
  }
}
