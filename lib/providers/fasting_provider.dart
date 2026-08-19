import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fast_record.dart';
import '../models/meal_record.dart';
import '../models/weight_record.dart';
import '../models/workout_record.dart';
import '../models/fasting_zone.dart';
import '../services/health_sync_service.dart';
import '../services/complication_service.dart';
import '../services/meal_estimator_service.dart';
import '../services/ongoing_activity_service.dart';
import '../services/notification_service.dart';

class FastingProtocol {
  const FastingProtocol({
    required this.label,
    required this.hours,
    this.isCustom = false,
  });

  final String label;
  final int hours;
  final bool isCustom;

  static const List<FastingProtocol> presets = [
    FastingProtocol(label: '16:8', hours: 16),
    FastingProtocol(label: '18:6', hours: 18),
    FastingProtocol(label: '20:4', hours: 20),
    FastingProtocol(label: '24h', hours: 24),
    FastingProtocol(label: '36h', hours: 36),
  ];

  static FastingProtocol custom(int totalHours) {
    final days = totalHours ~/ 24;
    final hours = totalHours % 24;
    final String label;
    if (days > 0 && hours > 0) {
      label = '${days}d ${hours}h';
    } else if (days > 0) {
      label = '${days}d';
    } else {
      label = '${hours}h';
    }
    return FastingProtocol(label: label, hours: totalHours, isCustom: true);
  }

  @override
  bool operator ==(Object other) =>
      other is FastingProtocol &&
      other.hours == hours &&
      other.isCustom == isCustom;

  @override
  int get hashCode => Object.hash(hours, isCustom);
}

class FastingProvider extends ChangeNotifier {
  bool _isFasting = false;
  DateTime? _startTime;
  FastingProtocol _protocol = FastingProtocol.presets.first;
  int _customHours = 48;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  List<FastRecord> _history = [];
  List<MealRecord> _meals = [];
  List<WeightRecord> _weights = [];
  List<WorkoutRecord> _workouts = [];

  /// Epoch millis of the last *intentional* fast state change (start/stop/edit)
  /// on this device. Used by sync to do last-writer-wins: a remote "stop" only
  /// wins if its change is newer than ours. Null until the first real change.
  int? _lastChangedMs;

  bool get isFasting => _isFasting;
  int? get lastChangedMs => _lastChangedMs;
  DateTime? get startTime => _startTime;
  FastingProtocol get protocol => _protocol;
  int get customHours => _customHours;
  Duration get elapsed => _elapsed;
  Duration get goal => Duration(hours: _protocol.hours);
  double get progress => _isFasting
      ? (_elapsed.inSeconds / goal.inSeconds).clamp(0.0, 1.0)
      : 0.0;
  List<FastRecord> get history => List.unmodifiable(_history);
  List<MealRecord> get meals => List.unmodifiable(_meals);
  List<WeightRecord> get weights => List.unmodifiable(_weights);
  List<WorkoutRecord> get workouts => List.unmodifiable(_workouts);
  FastingZone get currentZone => zoneForDuration(_elapsed);

  List<WorkoutRecord> workoutsOnDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return _workouts
        .where((w) =>
            w.startTime.isAfter(dayStart) && w.startTime.isBefore(dayEnd))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  /// Deliberately LOW-END MET values per activity type (bottom of the
  /// published ranges in the Compendium of Physical Activities), so the
  /// workout burn estimate never overpromises.
  static const _lowEndMets = <String, double>{
    'STRENGTH_TRAINING': 3.5,
    'RUNNING': 8.0,
    'WALKING': 3.0,
    'BIKING': 6.0,
    'SWIMMING_POOL': 6.0,
    'HIGH_INTENSITY_INTERVAL_TRAINING': 8.0,
    'YOGA': 2.5,
    'PILATES': 3.0,
    'ROWING': 6.0,
    'ELLIPTICAL': 5.0,
    'HIKING': 5.0,
  };

  /// Conservative calorie-burn estimate for the day's workouts:
  /// MET × body weight × hours, nudged by reported intensity. Uses the
  /// day's carry-forward weight (fallback 75 kg).
  int workoutBurnOnDay(DateTime day) {
    final workouts = workoutsOnDay(day);
    if (workouts.isEmpty) return 0;
    final kg = weightOnDay(day) ?? 75;
    var total = 0.0;
    for (final w in workouts) {
      final met = _lowEndMets[w.activityType] ?? 3.0;
      final factor = switch (w.intensity) {
        'light' => 0.8,
        'hard' => 1.15,
        _ => 1.0,
      };
      total += met * kg * (w.duration.inMinutes / 60.0) * factor;
    }
    return total.round();
  }

  /// Per-set (kg, reps) from the most recent workout containing
  /// [exercise] — shown as "previous" in the session logger.
  List<(double, int)> previousSets(String exercise) {
    final sorted = _workouts.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    for (final w in sorted) {
      final json = w.exercisesJson;
      if (json == null) continue;
      try {
        final list = jsonDecode(json) as List;
        for (final e in list.whereType<Map>()) {
          if (e['n'] != exercise) continue;
          final sets = (e['sets'] as List?) ?? const [];
          return [
            for (final s in sets.whereType<Map>())
              (
                ((s['kg'] as num?) ?? 0).toDouble(),
                ((s['reps'] as num?) ?? 0).toInt(),
              ),
          ];
        }
      } catch (_) {}
    }
    return const [];
  }

  /// Workouts completed in the current calendar week (Mon–Sun).
  int get workoutsThisWeek {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return _workouts.where((w) => !w.startTime.isBefore(monday)).length;
  }

  /// Carry-forward weight for a day: the most recent weight logged on or
  /// before that day, or null when nothing is logged yet.
  double? weightOnDay(DateTime day) {
    final cutoff = DateTime(day.year, day.month, day.day)
        .add(const Duration(days: 1));
    WeightRecord? best;
    for (final w in _weights) {
      if (w.time.isBefore(cutoff) &&
          (best == null || w.time.isAfter(best.time))) {
        best = w;
      }
    }
    return best?.kg;
  }

  /// Weight entries actually logged on a given day (not carry-forward).
  List<WeightRecord> weightsOnDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return _weights
        .where((w) => w.time.isAfter(dayStart) && w.time.isBefore(dayEnd))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  /// The newest logged weight overall, or null.
  WeightRecord? get latestWeight {
    WeightRecord? best;
    for (final w in _weights) {
      if (best == null || w.time.isAfter(best.time)) best = w;
    }
    return best;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final startMs = prefs.getInt('fast_start_ms');
    _lastChangedMs = prefs.getInt('fast_changed_ms');
    final protocolIdx = prefs.getInt('protocol_idx') ?? 0;
    _customHours = prefs.getInt('custom_hours') ?? 48;

    if (protocolIdx == -1) {
      _protocol = FastingProtocol.custom(_customHours);
    } else if (protocolIdx >= 0 &&
        protocolIdx < FastingProtocol.presets.length) {
      _protocol = FastingProtocol.presets[protocolIdx];
    }

    if (startMs != null) {
      _startTime = DateTime.fromMillisecondsSinceEpoch(startMs);
      final now = DateTime.now();
      if (_startTime!.isBefore(now)) {
        _isFasting = true;
        _elapsed = now.difference(_startTime!);
        _startTicker();
      } else {
        // Start time is in the future? This shouldn't happen, clear it.
        debugPrint('[FAST] init: start time in the FUTURE ($_startTime) — clearing fast_start_ms');
        await prefs.remove('fast_start_ms');
      }
    }

    final box = Hive.box<FastRecord>('fasts');
    _history = box.values.toList().reversed.toList();
    final mealBox = Hive.box<MealRecord>('meals');
    _meals = mealBox.values.toList().reversed.toList();
    _reloadWeights();
    _reloadWorkouts();
    // Pull weights/workouts logged in other apps via Health Connect.
    unawaited(maybeAutoImportFromHealth());
    
    // Re-schedule notifications on init to ensure they are active
    if (_isFasting && _startTime != null) {
      unawaited(NotificationService.scheduleMilestones(_startTime!, _protocol.hours));
      // Restore the Wear ongoing activity for a fast that survived a restart.
      unawaited(OngoingActivityService.start(
        startMs: _startTime!.millisecondsSinceEpoch,
        goalHours: _protocol.hours,
      ));
    } else {
      // No active fast: clear any milestone alarms left behind. Scheduled
      // notifications are OS alarms that survive process death — if a fast
      // was stopped while this device's app wasn't running (e.g. stopped on
      // the watch), stopFast()'s cancelAll never ran here.
      unawaited(NotificationService.cancelAll());
      // Re-schedule the daily reminder when idle.
      unawaited(NotificationService.scheduleDailyReminder());
    }

    notifyListeners();
  }

  void _reloadMeals() {
    final box = Hive.box<MealRecord>('meals');
    _meals = box.values.toList().reversed.toList();
  }

  void _reloadHistory() {
    final box = Hive.box<FastRecord>('fasts');
    _history = box.values.toList().reversed.toList();
  }

  void _reloadWeights() {
    final box = Hive.box<WeightRecord>('weights');
    _weights = box.values.toList();
  }

  void _reloadWorkouts() {
    final box = Hive.box<WorkoutRecord>('workouts');
    _workouts = box.values.toList();
  }

  // --- Workouts ------------------------------------------------------------

  /// Logs a workout. Mirrors a summary to Health Connect (best-effort)
  /// unless the entry itself came FROM Health Connect.
  Future<void> addWorkout(WorkoutRecord w) async {
    if (!w.endTime.isAfter(w.startTime)) return;
    final box = Hive.box<WorkoutRecord>('workouts');
    await box.add(w);
    _reloadWorkouts();
    notifyListeners();
    if (w.source != 'health') {
      unawaited(HealthSyncService.logWorkout(
        title: w.title,
        start: w.startTime,
        end: w.endTime,
        activityType: w.activityType,
      ));
    }
  }

  Future<void> deleteWorkout(WorkoutRecord w) async {
    // Capture the window before deleting the Hive object, then remove the
    // mirrored Health Connect record so it isn't re-imported next sync.
    final start = w.startTime;
    final end = w.endTime;
    final fromHealth = w.source == 'health';
    await w.delete();
    _reloadWorkouts();
    notifyListeners();
    if (!fromHealth) {
      unawaited(HealthSyncService.deleteWorkout(start: start, end: end));
    }
  }

  Future<void> updateWorkout(
    WorkoutRecord w, {
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? activityType,
    String? intensity,
    String? exercisesJson,
  }) async {
    final oldStart = w.startTime;
    final oldEnd = w.endTime;
    final fromHealth = w.source == 'health';

    w.title = title;
    w.startTime = startTime;
    w.endTime = endTime;
    if (activityType != null) w.activityType = activityType;
    if (intensity != null) w.intensity = intensity;
    if (exercisesJson != null) w.exercisesJson = exercisesJson;

    await w.save();
    _reloadWorkouts();
    notifyListeners();

    if (!fromHealth) {
      // Health Connect uses the time window as part of its identity/key for
      // records, so we replace the old one with the new.
      unawaited(HealthSyncService.deleteWorkout(start: oldStart, end: oldEnd)
          .then((_) => HealthSyncService.logWorkout(
                title: title,
                start: startTime,
                end: endTime,
                activityType: w.activityType,
              )));
    }
  }

  /// Imports workouts logged in other apps from Health Connect (last 30
  /// days). Dedupes on start time ±2 min — which also filters out
  /// workouts we exported ourselves. Returns count added.
  /// Raw workout points from the last Health read — for the diagnostic
  /// note in the import snackbar (see lastWeightReadCount).
  int lastWorkoutReadCount = 0;

  Future<int> importWorkoutsFromHealth({int sinceDays = 30}) async {
    try {
      final imported = await HealthSyncService.readWorkouts(
          since: DateTime.now().subtract(Duration(days: sinceDays)));
      lastWorkoutReadCount = imported.length;
      debugPrint('[TRAIN] Health read returned ${imported.length} workouts');
      var added = 0;
      for (final (start, end, title, activityType) in imported) {
        final exists = _workouts.any((w) =>
            (w.startTime.difference(start)).abs() <
            const Duration(minutes: 2));
        if (exists) continue;
        final box = Hive.box<WorkoutRecord>('workouts');
        await box.add(WorkoutRecord(
          startTime: start,
          endTime: end,
          title: title,
          source: 'health',
          activityType: activityType,
        ));
        added++;
      }
      if (added > 0) {
        _reloadWorkouts();
        notifyListeners();
      }
      return added;
    } catch (e) {
      debugPrint('[TRAIN] Health import failed: $e');
      return 0;
    }
  }

  // --- Weight ------------------------------------------------------------

  /// Logs a weight. Mirrors to Health Connect (best-effort) unless the
  /// entry itself came FROM Health Connect ([fromHealth]).
  Future<void> addWeight(double kg, DateTime time,
      {bool fromHealth = false}) async {
    if (kg <= 0 || kg > 500) return;
    final box = Hive.box<WeightRecord>('weights');
    await box.add(WeightRecord(time: time, kg: kg));
    _reloadWeights();
    notifyListeners();
    if (!fromHealth) {
      unawaited(HealthSyncService.logWeight(kg: kg, time: time));
    }
  }

  Future<void> deleteWeight(WeightRecord w) async {
    final time = w.time;
    await w.delete();
    _reloadWeights();
    notifyListeners();
    unawaited(HealthSyncService.deleteWeight(time: time));
  }

  Future<void> updateWeight(WeightRecord w,
      {required double kg, required DateTime time}) async {
    if (kg <= 0 || kg > 500) return;
    final oldTime = w.time;

    w.kg = kg;
    w.time = time;
    await w.save();
    _reloadWeights();
    notifyListeners();

    unawaited(HealthSyncService.deleteWeight(time: oldTime)
        .then((_) => HealthSyncService.logWeight(kg: kg, time: time)));
  }

  /// Merges records pulled from cloud backup into local data, de-duplicating
  /// on [syncId]. Never removes anything (backup must not wipe local data).
  /// Returns the number of new records added.
  Future<int> mergeCloudRecords({
    List<FastRecord>? fasts,
    List<MealRecord>? meals,
    List<WeightRecord>? weights,
    List<WorkoutRecord>? workouts,
  }) async {
    var added = 0;

    final fastBox = Hive.box<FastRecord>('fasts');
    final haveFast = _history.map((e) => e.syncId).whereType<String>().toSet();
    for (final r in fasts ?? const <FastRecord>[]) {
      if (r.syncId != null && haveFast.contains(r.syncId)) continue;
      await fastBox.add(r);
      added++;
    }

    final mealBox = Hive.box<MealRecord>('meals');
    final haveMeal = _meals.map((e) => e.syncId).whereType<String>().toSet();
    for (final r in meals ?? const <MealRecord>[]) {
      if (r.syncId != null && haveMeal.contains(r.syncId)) continue;
      await mealBox.add(r);
      added++;
    }

    final weightBox = Hive.box<WeightRecord>('weights');
    final haveWeight =
        _weights.map((e) => e.syncId).whereType<String>().toSet();
    for (final r in weights ?? const <WeightRecord>[]) {
      if (r.syncId != null && haveWeight.contains(r.syncId)) continue;
      await weightBox.add(r);
      added++;
    }

    final workoutBox = Hive.box<WorkoutRecord>('workouts');
    final haveWorkout =
        _workouts.map((e) => e.syncId).whereType<String>().toSet();
    for (final r in workouts ?? const <WorkoutRecord>[]) {
      if (r.syncId != null && haveWorkout.contains(r.syncId)) continue;
      await workoutBox.add(r);
      added++;
    }

    if (added > 0) {
      _reloadHistory();
      _reloadMeals();
      _reloadWeights();
      _reloadWorkouts();
      notifyListeners();
    }
    return added;
  }

  /// Imports weights logged in other apps from Health Connect (last 90
  /// days). Dedupes against existing records within ±2 min and ±0.05 kg,
  /// which also filters out entries we exported ourselves. Returns the
  /// number of new weights added.
  /// How many raw weight points the last Health read returned — surfaced
  /// in the import snackbar to distinguish "nothing in Health" from
  /// "everything deduped".
  int lastWeightReadCount = 0;

  DateTime? _lastAutoImport;

  /// Read-only mirrors from Health Connect (steps and sleep are never
  /// written by us). Refreshed by the auto/manual import.
  Map<DateTime, int> stepsPerDay = const {};
  Map<DateTime, int> sleepMinutesPerDay = const {};

  int? stepsOnDay(DateTime day) =>
      stepsPerDay[DateTime(day.year, day.month, day.day)];
  int? sleepMinutesOnDay(DateTime day) =>
      sleepMinutesPerDay[DateTime(day.year, day.month, day.day)];

  Future<void> refreshStepsAndSleep({int sinceDays = 366}) async {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final since = todayMidnight.subtract(Duration(days: sinceDays));

    final steps = await HealthSyncService.readStepsPerDay(since: since);
    final sleep = await HealthSyncService.readSleepMinutesPerDay(since: since);

    // Always update and notify, even if data is empty, to clear old states.
    stepsPerDay = steps;
    sleepMinutesPerDay = sleep;
    notifyListeners();
  }

  /// User-initiated "sync now" for every Health Connect data type the app
  /// reads (weights, workouts, meals, steps, sleep) — used by the Insights
  /// refresh button. Unlike [maybeAutoImportFromHealth] this always runs
  /// (no 15-minute throttle) and lets the caller choose how far back to
  /// look. Returns per-type counts so the UI can summarize what changed.
  Future<({int weights, int workouts, int meals})> refreshAllFromHealth(
      {int sinceDays = 30}) async {
    final weights = await importWeightsFromHealth(sinceDays: sinceDays);
    final workouts = await importWorkoutsFromHealth(sinceDays: sinceDays);
    final meals = await importMealsFromHealth(sinceDays: sinceDays);
    await refreshStepsAndSleep(sinceDays: sinceDays);
    _lastAutoImport = DateTime.now();
    return (weights: weights, workouts: workouts, meals: meals);
  }

  /// Auto-import from Health Connect on app start/resume, throttled to
  /// once per 15 minutes. Health Connect has no push mechanism, so
  /// resume is the earliest we can notice new measurements.
  Future<void> maybeAutoImportFromHealth() async {
    final now = DateTime.now();
    if (_lastAutoImport != null &&
        now.difference(_lastAutoImport!) < const Duration(minutes: 15)) {
      return;
    }
    _lastAutoImport = now;
    await importWeightsFromHealth();
    await importWorkoutsFromHealth();
    await importMealsFromHealth();
    await refreshStepsAndSleep();
  }

  Future<int> importWeightsFromHealth({int sinceDays = 90}) async {
    try {
      final imported = await HealthSyncService.readWeights(
          since: DateTime.now().subtract(Duration(days: sinceDays)));
      lastWeightReadCount = imported.length;
      debugPrint('[WEIGHT] Health read returned ${imported.length} points');
      if (imported.isEmpty) return 0;
      var added = 0;
      for (final (time, kg) in imported) {
        final exists = _weights.any((w) =>
            (w.time.difference(time)).abs() < const Duration(minutes: 2) &&
            (w.kg - kg).abs() < 0.05);
        if (exists) continue;
        final box = Hive.box<WeightRecord>('weights');
        await box.add(WeightRecord(time: time, kg: kg));
        added++;
      }
      if (added > 0) {
        _reloadWeights();
        notifyListeners();
      }
      return added;
    } catch (e) {
      debugPrint('[WEIGHT] Health import failed: $e');
      return 0;
    }
  }

  /// Imports meals logged in other apps from Health Connect (last 30
  /// days). Skips zero-calorie records (our own exported fasts) and
  /// dedupes against existing meals within ±2 min and ±1 kcal — which
  /// also filters out meals we exported ourselves. Returns count added.
  Future<int> importMealsFromHealth({int sinceDays = 30}) async {
    try {
      final points = await HealthSyncService.readMeals(
          since: DateTime.now().subtract(Duration(days: sinceDays)));
      var added = 0;
      for (final p in points) {
        final v = p.value;
        if (v is! NutritionHealthValue) continue;
        final kcal = v.calories?.toDouble() ?? 0;
        if (kcal <= 0) continue; // our fast markers are zero-calorie
        final time = p.dateTo;
        final exists = _meals.any((m) =>
            (m.time.difference(time)).abs() < const Duration(minutes: 2) &&
            (m.calories - kcal).abs() < 1);
        if (exists) continue;
        final box = Hive.box<MealRecord>('meals');
        await box.add(MealRecord(
          time: time,
          name: (v.name?.trim().isNotEmpty ?? false)
              ? v.name!.trim()
              : 'Imported from Health',
          calories: kcal,
          protein: v.protein?.toDouble(),
          carbs: v.carbs?.toDouble(),
          fat: v.fat?.toDouble(),
          mealType: v.mealType ?? 'SNACK',
        ));
        added++;
      }
      if (added > 0) {
        _reloadMeals();
        notifyListeners();
      }
      return added;
    } catch (e) {
      debugPrint('[MEAL] Health import failed: $e');
      return 0;
    }
  }

  // --- Meal CRUD ---------------------------------------------------------

  Future<void> addMeal(MealRecord meal) async {
    final box = Hive.box<MealRecord>('meals');
    await box.add(meal);
    _reloadMeals();
    notifyListeners();
    // Fire-and-forget: extract individual foods for nutrient insights.
    unawaited(_enrichMeal(meal));
  }

  /// Asks the on-device AI to split the description into foods + grams,
  /// enabling micronutrient lookups in Matvaretabellen. Best-effort:
  /// silently does nothing on devices without the model.
  Future<void> _enrichMeal(MealRecord meal) async {
    try {
      if (meal.foodsJson != null) return;
      final foods = await MealEstimatorService.extractFoods(meal.name);
      if (foods == null) return;
      meal.foodsJson =
          jsonEncode([for (final f in foods) {'n': f.$1, 'g': f.$2}]);
      await meal.save();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> updateMeal(
    MealRecord meal, {
    required String name,
    required double calories,
    double? protein,
    double? carbs,
    double? fat,
    required String mealType,
    required DateTime time,
  }) async {
    meal
      ..name = name
      ..calories = calories
      ..protein = protein
      ..carbs = carbs
      ..fat = fat
      ..mealType = mealType
      ..time = time;
    await meal.save();
    _reloadMeals();
    notifyListeners();
  }

  Future<void> deleteMeal(MealRecord meal) async {
    // Capture the time before deleting, then remove the mirrored Health
    // Connect nutrition record so it isn't re-imported next sync.
    final time = meal.time;
    await meal.delete();
    _reloadMeals();
    notifyListeners();
    unawaited(HealthSyncService.deleteMeal(time: time));
  }

  // --- Fast history editing ---------------------------------------------

  /// Adds a completed fast in retrospect (from the Journal's + button).
  Future<void> addFast(FastRecord record) async {
    if (!record.endTime.isAfter(record.startTime)) return;
    final box = Hive.box<FastRecord>('fasts');
    await box.add(record);
    _reloadHistory();
    notifyListeners();
  }

  Future<void> updateFast(
    FastRecord record, {
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    if (endTime.isBefore(startTime)) return;
    record
      ..startTime = startTime
      ..endTime = endTime;
    await record.save();
    _reloadHistory();
    notifyListeners();
  }

  Future<void> deleteFast(FastRecord record) async {
    await record.delete();
    _reloadHistory();
    notifyListeners();
  }

  /// Marks a deliberate local change (start/stop/edit/goal) so sync can do
  /// last-writer-wins against stale state from the paired device.
  Future<void> _touchChanged() async {
    _lastChangedMs = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fast_changed_ms', _lastChangedMs!);
  }

  void setProtocol(FastingProtocol p) {
    if (_isFasting) return;
    _protocol = p;
    _saveProtocol();
    unawaited(_touchChanged());
    notifyListeners();
  }

  /// Sets a custom protocol of [totalHours] (e.g. 2 days + 12 hours = 60).
  void setCustomProtocol(int totalHours) {
    if (_isFasting) return;
    if (totalHours < 1) return;
    _customHours = totalHours;
    _protocol = FastingProtocol.custom(totalHours);
    _saveProtocol();
    unawaited(_touchChanged());
    notifyListeners();
  }

  Future<void> startFast() async {
    if (_isFasting) return;
    _startTime = DateTime.now();
    _isFasting = true;
    _elapsed = Duration.zero;
    _startTicker();
    _lastChangedMs = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fast_start_ms', _startTime!.millisecondsSinceEpoch);
    await prefs.setInt('fast_changed_ms', _lastChangedMs!);
    notifyListeners();
    unawaited(ComplicationService.refresh());
    unawaited(OngoingActivityService.start(
      startMs: _startTime!.millisecondsSinceEpoch,
      goalHours: _protocol.hours,
    ));
    unawaited(OngoingActivityService.refreshTiles());
    unawaited(NotificationService.scheduleMilestones(_startTime!, _protocol.hours));
  }

  /// Adjusts the start time of the ongoing fast (e.g. if the user forgot
  /// to start the timer when they actually began fasting).
  Future<void> editStartTime(DateTime newStart) async {
    if (!_isFasting) return;
    if (newStart.isAfter(DateTime.now())) return;
    _startTime = newStart;
    _elapsed = DateTime.now().difference(newStart);
    _lastChangedMs = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('fast_start_ms', newStart.millisecondsSinceEpoch);
    await prefs.setInt('fast_changed_ms', _lastChangedMs!);
    notifyListeners();
    unawaited(ComplicationService.refresh());
    unawaited(OngoingActivityService.start(
      startMs: newStart.millisecondsSinceEpoch,
      goalHours: _protocol.hours,
    ));
    unawaited(OngoingActivityService.refreshTiles());
    unawaited(NotificationService.scheduleMilestones(newStart, _protocol.hours));
  }

  /// Changes the goal (protocol) of the ongoing fast. The progress ring
  /// recomputes automatically since [progress] derives from [goal].
  Future<void> updateGoalDuringFast(FastingProtocol p) async {
    if (!_isFasting) return;
    _protocol = p;
    if (p.isCustom) _customHours = p.hours;
    await _saveProtocol();
    // A goal change is a deliberate change: without this, a stale context
    // from the paired device would revert the goal on next app start.
    await _touchChanged();
    notifyListeners();
    unawaited(ComplicationService.refresh());
    if (_isFasting && _startTime != null) {
      unawaited(OngoingActivityService.start(
        startMs: _startTime!.millisecondsSinceEpoch,
        goalHours: _protocol.hours,
      ));
      unawaited(OngoingActivityService.refreshTiles());
      unawaited(NotificationService.scheduleMilestones(_startTime!, _protocol.hours));
    }
  }

  Future<void> stopFast() async {
    if (!_isFasting) return;
    _ticker?.cancel();
    final record = FastRecord(
      startTime: _startTime!,
      endTime: DateTime.now(),
      protocol: _protocol.label,
    );
    final box = Hive.box<FastRecord>('fasts');
    await box.add(record);
    _history = box.values.toList().reversed.toList();
    _isFasting = false;
    _startTime = null;
    _elapsed = Duration.zero;
    _lastChangedMs = DateTime.now().millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fast_start_ms');
    await prefs.setInt('fast_changed_ms', _lastChangedMs!);
    notifyListeners();

    // Fire-and-forget sync to Health Connect (no-op when disabled).
    unawaited(HealthSyncService.syncFast(record));
    unawaited(ComplicationService.refresh());
    unawaited(OngoingActivityService.stop());
    unawaited(OngoingActivityService.refreshTiles());
    unawaited(NotificationService.cancelAll());
  }

  /// Applies fast state received from the paired device (phone or watch).
  /// Returns true if anything changed locally.
  Future<bool> syncFromRemote({
    required bool isFasting,
    DateTime? remoteStartTime,
    required int protocolHours,
    required String protocolLabel,
    required bool isCustom,
    int? remoteChangedMs,
  }) async {
    debugPrint('[FAST] syncFromRemote: remoteFasting=$isFasting '
        'remoteStart=$remoteStartTime remoteChangedMs=$remoteChangedMs '
        '| localFasting=$_isFasting localChangedMs=$_lastChangedMs');
    var changed = false;

    final newProtocol = FastingProtocol(
      label: protocolLabel,
      hours: protocolHours,
      isCustom: isCustom,
    );
    if (_protocol != newProtocol) {
      // Last-writer-wins for the protocol too: a stale context re-broadcast
      // at startup (e.g. the goal from BEFORE a custom change) must never
      // overwrite a newer local goal.
      final localChangedMs = _lastChangedMs ?? 0;
      final remoteIsNewer =
          remoteChangedMs != null && remoteChangedMs > localChangedMs;
      if (remoteIsNewer) {
        _protocol = newProtocol;
        if (isCustom) _customHours = protocolHours;
        await _saveProtocol();
        changed = true;
      } else {
        debugPrint('[FAST] syncFromRemote: IGNORING stale remote protocol '
            '${newProtocol.label} (remoteChangedMs=$remoteChangedMs <= '
            'localChangedMs=$localChangedMs)');
        // Nudge listeners so our (newer) state re-broadcasts and the other
        // device catches up.
        notifyListeners();
      }
    }

    if (isFasting && remoteStartTime != null) {
      // Last-writer-wins on the START path too. A persisted ApplicationContext
      // on the watch can re-broadcast an OLD fast after we deliberately stopped.
      // Only adopt a remote fast if its change is at least as new as ours;
      // otherwise our stop is newer and the remote state is stale.
      final localChangedMs = _lastChangedMs ?? 0;
      final remoteIsNewer =
          remoteChangedMs != null && remoteChangedMs >= localChangedMs;
      if (!remoteIsNewer) {
        debugPrint('[FAST] syncFromRemote: IGNORING remote start as stale '
            '(remoteChangedMs=$remoteChangedMs < localChangedMs=$localChangedMs)');
        // Re-broadcast our (newer) state so the other device catches up.
        unawaited(ComplicationService.refresh());
        return false;
      }
      if (!_isFasting || _startTime != remoteStartTime) {
        _startTime = remoteStartTime;
        _isFasting = true;
        _elapsed = DateTime.now().difference(remoteStartTime);
        _startTicker();
        // Adopt the other device's change time so we don't later "win" over it.
        // Guard above guarantees remoteChangedMs is non-null here.
        _lastChangedMs = remoteChangedMs;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            'fast_start_ms', remoteStartTime.millisecondsSinceEpoch);
        await prefs.setInt('fast_changed_ms', _lastChangedMs!);
        unawaited(NotificationService.scheduleMilestones(remoteStartTime, _protocol.hours));
        unawaited(OngoingActivityService.start(
          startMs: remoteStartTime.millisecondsSinceEpoch,
          goalHours: _protocol.hours,
        ));
        changed = true;
      }
    } else if (!isFasting && _isFasting) {
      // ONLY stop if the remote device DELIBERATELY stopped a fast more recently
      // than our last change. Last-writer-wins on actual state changes — NOT on
      // broadcast time. An empty/idle device whose last real change predates our
      // fast (or which never changed, remoteChangedMs == null) must NOT win.
      final localChangedMs = _lastChangedMs ?? 0;
      final isNewerStop =
          remoteChangedMs != null && remoteChangedMs > localChangedMs;
      if (isNewerStop) {
        debugPrint('[FAST] syncFromRemote: applying remote STOP '
            '(remoteChangedMs=$remoteChangedMs > localChangedMs=$localChangedMs)');
        await stopFast();
        return true;
      }
      // Stale/empty remote state — keep the local fast and re-broadcast our
      // (newer) state so the other device catches up.
      debugPrint('[FAST] syncFromRemote: IGNORING remote stop as stale/empty '
          '(remoteChangedMs=$remoteChangedMs <= localChangedMs=$localChangedMs)');
      unawaited(ComplicationService.refresh());
      return false;
    }

    if (changed) {
      notifyListeners();
      unawaited(ComplicationService.refresh());
    }
    return changed;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startTime != null) {
        _elapsed = DateTime.now().difference(_startTime!);
        notifyListeners();
      }
    });
  }

  Future<void> _saveProtocol() async {
    final prefs = await SharedPreferences.getInstance();
    if (_protocol.isCustom) {
      await prefs.setInt('protocol_idx', -1);
      await prefs.setInt('custom_hours', _customHours);
    } else {
      await prefs.setInt(
          'protocol_idx', FastingProtocol.presets.indexOf(_protocol));
    }
  }

  String formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
