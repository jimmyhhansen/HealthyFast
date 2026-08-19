import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';
import '../models/meal_record.dart';
import '../models/workout_record.dart';
import '../providers/fasting_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/training_provider.dart';
import 'health_sync_service.dart';
import 'meal_estimator_service.dart';
import 'meal_sync_queue.dart';
import 'ongoing_activity_service.dart';

/// Keeps the fast state in sync between phone and watch over the
/// Wearable Data Layer, and additionally:
///  • pushes today's calorie intake, daily burn and on-device-AI
///    availability to the watch so the "Log meal" tile can show them;
///  • on the phone, receives a spoken meal description from the watch,
///    estimates it with on-device AI and logs it automatically.
///
/// Runs on both devices: each side broadcasts its state when it changes
/// and applies state received from the other side.
class WatchSyncService {
  WatchSyncService(this._fp, this._profile, this._training);

  final FastingProvider _fp;
  final ProfileProvider _profile;
  final TrainingProvider _training;
  final _wc = WatchConnectivity();

  StreamSubscription<Map<String, dynamic>>? _msgSub;
  StreamSubscription<Map<String, dynamic>>? _ctxSub;
  String _lastSignature = '';

  /// Whether on-device meal AI is available on THIS device (the phone).
  bool _nanoAvailable = false;

  /// Throttles the native checkNanoStatus() call in [_broadcast] — see the
  /// comment there. Without this, a session on a device where FastingProvider
  /// ticks every second (see fasting_provider.dart's Timer.periodic) fired a
  /// platform-channel round-trip to Android ML Kit every single second, for
  /// as long as the app was open — visible as a wall of repeated
  /// "[MealAI] checkNanoStatus" lines in the debug log with no other purpose
  /// than re-confirming a value that essentially never changes mid-session.
  DateTime? _lastNanoCheck;

  /// Ids of watch meals this phone has already logged (dedupe).
  List<String> _processedIds = const [];

  /// Pending meals on this device (only non-empty on the watch).
  List<Map<String, dynamic>> _pendingMeals = const [];

  /// Items currently being processed on this device (to prevent races).
  final Set<String> _inFlightIds = {};

  /// Helper to build a sync signature to prevent loops/echoes.
  /// Takes all variables as arguments to ensure purely local or remote state.
  String _buildSignature({
    required bool isFasting,
    required int? startMs,
    required int hours,
    required int todayKcal,
    required int burn,
    required bool nano,
    required String pendingIds,
    required String processedIds,
    required int nextWorkoutHash,
    required int weekDone,
    required int programsHash,
  }) =>
      '$isFasting|$startMs|$hours|$todayKcal|$burn|$nano'
      '|$pendingIds|$processedIds|$nextWorkoutHash|$weekDone|$programsHash';

  int get _todayKcal {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return _fp.meals
        .where((m) => m.time.isAfter(dayStart) && m.time.isBefore(dayEnd))
        .fold<double>(0, (s, m) => s + m.calories)
        .round();
  }

  int get _burn => (_profile.effectiveTdee ?? 0).round();

  String get _localSignature => _buildSignature(
        isFasting: _fp.isFasting,
        startMs: _fp.startTime?.millisecondsSinceEpoch,
        hours: _fp.protocol.hours,
        todayKcal: _todayKcal,
        burn: _burn,
        nano: _nanoAvailable,
        pendingIds: _pendingMeals.map((e) => e['id']).join(','),
        processedIds: _processedIds.join(','),
        nextWorkoutHash: _training.nextWorkoutJson().hashCode,
        weekDone: _fp.workoutsThisWeek,
        // Bundled + custom program list — was NOT part of the signature
        // before, so creating/editing a custom program on the phone while
        // nothing else changed (fasting state, next workout, etc.) never
        // flipped the signature, and the watch silently kept a stale
        // program list (could look like "the watch lost its programs").
        // Hashing the full list (not just its length) also catches edits
        // to an existing custom program, not just additions/removals.
        programsHash: _training.allProgramsJson().hashCode,
      );

  Future<void> init() async {
    try {
      // The phone estimates meals; check once whether it can.
      _nanoAvailable =
          (await MealEstimatorService.checkStatus()) == NanoStatus.available;

      // Restore dedupe/queue state.
      final prefs = await SharedPreferences.getInstance();
      _processedIds = prefs.getStringList('processed_meal_ids') ?? const [];
      _pendingMeals = await MealSyncQueue.pending();
      MealSyncQueue.onChanged = () async {
        _pendingMeals = await MealSyncQueue.pending();
        await _broadcast();
      };

      if (!await _wc.isSupported) return;

      _msgSub = _wc.messageStream.listen(_applyRemote);
      _ctxSub = _wc.contextStream.listen(_applyRemote);

      // Catch up on the last state broadcast while we weren't running.
      final contexts = await _wc.receivedApplicationContexts;
      if (contexts.isNotEmpty) {
        _applyRemote(contexts.last);
      }

      _fp.addListener(_broadcast);
      _profile.addListener(_broadcast);
      _training.addListener(_broadcast);
      await _broadcast();
    } catch (e) {
      debugPrint('WatchSyncService.init failed: $e');
    }
  }

  Future<void> _broadcast() async {
    // Re-check periodically (not on every broadcast — this used to run
    // every second, see _lastNanoCheck's doc comment): the user may have
    // downloaded the AI model since app start, and the watch tile must
    // reflect that within a reasonable delay, but it doesn't need to be
    // instant.
    final now = DateTime.now();
    if (_lastNanoCheck == null ||
        now.difference(_lastNanoCheck!) > const Duration(seconds: 30)) {
      _lastNanoCheck = now;
      try {
        _nanoAvailable =
            (await MealEstimatorService.checkStatus()) == NanoStatus.available;
      } catch (_) {}
    }

    final sig = _localSignature;
    if (sig == _lastSignature) return; // unchanged or just applied remotely
    _lastSignature = sig;

    final state = <String, dynamic>{
      'isFasting': _fp.isFasting,
      'startMs': _fp.startTime?.millisecondsSinceEpoch,
      'protocolHours': _fp.protocol.hours,
      'protocolLabel': _fp.protocol.label,
      'isCustom': _fp.protocol.isCustom,
      // Time of the last INTENTIONAL start/stop/edit on this device (not the
      // broadcast time). Lets the receiver do last-writer-wins and ignore a
      // stale/empty state that merely happens to be re-broadcast now.
      'changedMs': _fp.lastChangedMs,
      // Meal-logging fields for the watch tile.
      'todayKcal': _todayKcal,
      'dailyBurn': _burn,
      'nanoAvailable': _nanoAvailable,
      // Reliable meal delivery: the watch's outstanding meals ride in the
      // persisted context until the phone acknowledges them, and the
      // phone's ack list rides back the same way. JSON strings, since the
      // data layer handles flat maps best.
      'pendingMeals': jsonEncode(_pendingMeals),
      'processedMealIds': jsonEncode(_processedIds),
      // Training fields for the watch's Train tile + on-watch logging.
      'nextWorkout': _training.nextWorkoutJson(),
      'programJson': _training.programJson(),
      'allProgramsJson': _training.allProgramsJson(),
      'weekWorkoutsDone': _fp.workoutsThisWeek,
      // Deliberately NOT included: an in-progress workout session. Every
      // set/exercise change during a session calls notifyListeners() on
      // TrainingProvider, which used to re-broadcast the full state here —
      // i.e. a message to the other device on nearly every tap while a
      // workout was in progress, which made the phone app unstable. A
      // session now lives ONLY on the device it was started on until it's
      // finished; "Finish workout" is what actually delivers it, as a
      // single explicit `type: workout` message/queue item (see
      // _handleRemoteWorkout / WatchWorkoutFlow._finish).
    };
    try {
      // Context persists for devices that are offline right now;
      // message reaches a connected device instantly.
      await _wc.updateApplicationContext(state);
      if (await _wc.isReachable) {
        await _wc.sendMessage(state);
      }
    } catch (e) {
      debugPrint('WatchSyncService.broadcast failed: $e');
    }
  }

  Future<void> _applyRemote(Map<String, dynamic> state) async {
    try {
      debugPrint('[SYNC] Incoming state: ${state['type'] ?? 'context'}');
      
      // 1. Spoken meal or finished workout (Fast Path)
      if (state['type'] == 'logMeal') {
        await _handleRemoteMeal(
          state['text'] as String?,
          id: state['id'] as String?,
        );
        // Do NOT return here if this is a context update (application context).
        // If it's a direct message, it usually only has one type.
      } else if (state['type'] == 'workout') {
        final id = state['id'] as String?;
        if (id != null && !_processedIds.contains(id)) {
          await _handleRemoteWorkout(state, id: id);
        }
      } else if (state['type'] == 'mealAck') {
        await _applyAck(state['ids'] as String?);
      }

      // 2. Reliable Queue Processing (Context Path)
      // Processes any meals/workouts bundled in the application context.
      await _processPendingMeals(state['pendingMeals'] as String?);
      await _applyAck(state['processedMealIds'] as String?);

      // 3. Persist Shared Context for UI
      await _persistMealContext(state);

      // 4. Fasting State Sync (Loop Protection)
      final isFasting = state['isFasting'] == true;
      final startMs = state['startMs'] as int?;
      final hours = state['protocolHours'] as int?;
      final label = state['protocolLabel'] as String?;
      final isCustom = state['isCustom'] == true;
      final changedMs = state['changedMs'] as int?;

      if (hours == null || label == null) {
        debugPrint('[SYNC] Incomplete fasting state received, skipping sync part.');
        return;
      }

      if (!isFasting && startMs == null && changedMs == null) {
        debugPrint('[FAST] Ignoring default/empty remote state');
        return;
      }

      // Re-build remote signature from actual received values
      final remoteSig = _buildSignature(
        isFasting: isFasting,
        startMs: startMs,
        hours: hours,
        todayKcal: state['todayKcal'] as int? ?? 0,
        burn: state['dailyBurn'] as int? ?? 0,
        nano: state['nanoAvailable'] == true,
        pendingIds: _extractIds(state['pendingMeals'] as String?),
        processedIds: _extractIds(state['processedMealIds'] as String?),
        nextWorkoutHash: (state['nextWorkout'] as String? ?? '').hashCode,
        weekDone: state['weekWorkoutsDone'] as int? ?? 0,
        programsHash: (state['allProgramsJson'] as String? ?? '').hashCode,
      );

      if (remoteSig == _localSignature) {
        debugPrint('[SYNC] Signature matches local, skipping sync to prevent echo.');
        return;
      }

      debugPrint('[FAST] Applying remote fasting state change...');
      _lastSignature = remoteSig;
      await _fp.syncFromRemote(
        isFasting: isFasting,
        remoteStartTime: startMs != null
            ? DateTime.fromMillisecondsSinceEpoch(startMs)
            : null,
        protocolHours: hours,
        protocolLabel: label,
        isCustom: isCustom,
        remoteChangedMs: changedMs,
      );
      // NOTE: an in-progress workout session is intentionally never applied
      // from remote state here — see the comment on 'activeSession' in
      // _broadcast(). Each device's session is local until finished.
    } catch (e) {
      debugPrint('WatchSyncService.applyRemote failed: $e');
    }
  }

  String _extractIds(String? json) {
    if (json == null || json.isEmpty) return '';
    try {
      final list = jsonDecode(json) as List;
      return [for (final e in list) if (e is Map) e['id'] else e].join(',');
    } catch (_) {
      return '';
    }
  }

  /// Writes the meal-tile fields to SharedPreferences (native reads them
  /// with the "flutter." prefix), then asks the tile to refresh.
  Future<void> _persistMealContext(Map<String, dynamic> state) async {
    final kcal = state['todayKcal'];
    final burn = state['dailyBurn'];
    final nano = state['nanoAvailable'];
    if (kcal == null && burn == null && nano == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (kcal is int) await prefs.setInt('today_kcal', kcal);
    if (burn is int) await prefs.setInt('daily_burn', burn);
    if (nano is bool) await prefs.setBool('nano_available', nano);
    // Training context for the watch's Train tile + session screen.
    final nextWorkout = state['nextWorkout'];
    if (nextWorkout is String) {
      await prefs.setString('next_workout_json', nextWorkout);
    }
    final programJson = state['programJson'];
    // Empty means the phone has no program — don't wipe a program the
    // user picked locally on the watch.
    if (programJson is String && programJson.isNotEmpty) {
      await prefs.setString('program_json', programJson);
    }
    final allProgramsJson = state['allProgramsJson'];
    if (allProgramsJson is String && allProgramsJson.isNotEmpty) {
      await prefs.setString('all_programs_json', allProgramsJson);
    }
    final weekDone = state['weekWorkoutsDone'];
    if (weekDone is int) await prefs.setInt('week_workouts_done', weekDone);
    // Refresh the tiles on the watch so they show the new values.
    unawaited(OngoingActivityService.refreshTiles());
  }

  /// Watch side: removes acknowledged meals from the pending queue.
  Future<void> _applyAck(String? idsJson) async {
    if (idsJson == null || idsJson.isEmpty) return;
    try {
      final ids = (jsonDecode(idsJson) as List).cast<String>();
      if (ids.isEmpty) return;
      await MealSyncQueue.removeIds(ids);
    } catch (_) {}
  }

  /// Phone side: logs every not-yet-processed meal from the watch queue,
  /// then acknowledges so the watch can clear them.
  Future<void> _processPendingMeals(String? pendingJson) async {
    if (pendingJson == null || pendingJson.isEmpty) return;
    List<dynamic> items;
    try {
      items = jsonDecode(pendingJson) as List;
    } catch (_) {
      return;
    }
    var processedAny = false;
    for (final item in items) {
      if (item is! Map) continue;
      final id = item['id'] as String?;
      if (id == null) continue;

      if (_processedIds.contains(id) || _inFlightIds.contains(id)) {
        debugPrint('[SYNC] Item $id already processed or in-flight, marking processedAny for ack.');
        processedAny = true;
        continue;
      }

      if (item['type'] == 'workout') {
        debugPrint('[TRAIN] Processing pending workout: $id');
        await _handleRemoteWorkout(item, id: id);
        processedAny = true;
      } else {
        final text = item['text'] as String?;
        if (text == null) continue;
        debugPrint('[MEAL] Processing pending meal: $id');
        await _handleRemoteMeal(text, id: id, broadcastAfter: false);
        processedAny = true;
      }
    }
    if (processedAny) {
      // Ack fast when reachable; the context broadcast is the safety net.
      try {
        if (await _wc.isReachable) {
          await _wc.sendMessage(
              {'type': 'mealAck', 'ids': jsonEncode(_processedIds)});
        }
      } catch (_) {}
      await _broadcast();
    }
  }

  Future<void> _markProcessed(String id) async {
    final ids = [..._processedIds, id];
    while (ids.length > 100) {
      ids.removeAt(0);
    }
    _processedIds = ids;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('processed_meal_ids', ids);
  }

  /// Phone side: logs a workout completed on the watch and advances the
  /// program when it matches the expected next workout.
  Future<void> _handleRemoteWorkout(Map item, {required String id}) async {
    if (_processedIds.contains(id) || _inFlightIds.contains(id)) {
      debugPrint('[TRAIN] Workout $id already handled or in-flight. Skipping.');
      return;
    }
    _inFlightIds.add(id);
    try {
      final title = item['title'] as String? ?? 'Workout';
      final dayTitle = item['dayTitle'] as String? ?? title;
      final startMs = (item['startMs'] as num?)?.toInt();
      final endMs = (item['endMs'] as num?)?.toInt();
      final exercisesJson = item['exercises'] as String?;
      if (startMs == null || endMs == null) return;

      final program = _training.program;
      await _fp.addWorkout(WorkoutRecord(
        startTime: DateTime.fromMillisecondsSinceEpoch(startMs),
        endTime: DateTime.fromMillisecondsSinceEpoch(endMs),
        title: title,
        exercisesJson: exercisesJson,
        programId: _training.programId,
        programDayIdx: program == null
            ? null
            : _training.dayIdx % program.days.length,
        source: 'watch',
        syncId: id,
      ));

      // Advance the program only when this is the expected next day —
      // protects against double-advancing on duplicate/late deliveries.
      final day = _training.nextDay;
      if (day != null && day.title == dayTitle) {
        final succeeded = <String, bool>{};
        final usedKg = <String, List<double>>{};
        final usedReps = <String, List<int>>{};
        try {
          final list = jsonDecode(exercisesJson ?? '[]') as List;
          for (final e in day.exercises) {
            final logged = list.whereType<Map>().firstWhere(
                  (m) => m['n'] == e.name,
                  orElse: () => const {},
                );
            final sets = (logged['sets'] as List?) ?? const [];
            succeeded[e.name] = sets.length >= e.sets &&
                sets.whereType<Map>().every(
                    (s) => ((s['reps'] as num?) ?? 0) >= e.reps);

            final setWeights = <double>[];
            final setReps = <int>[];
            for (final s in sets.whereType<Map>()) {
              setWeights.add((s['kg'] as num?)?.toDouble() ?? 0);
              setReps.add((s['reps'] as num?)?.toInt() ?? 0);
            }
            if (setWeights.isNotEmpty) usedKg[e.name] = setWeights;
            if (setReps.isNotEmpty) usedReps[e.name] = setReps;
          }
        } catch (_) {}
        await _training.completeWorkout(day, succeeded,
            usedKg: usedKg, usedReps: usedReps);
      }
      await _markProcessed(id);
    } catch (e) {
      debugPrint('[TRAIN] remote workout failed: $e');
    } finally {
      _inFlightIds.remove(id);
    }
  }

  /// Phone side: turn a spoken description into a logged meal.
  Future<void> _handleRemoteMeal(String? text,
      {String? id, bool broadcastAfter = true}) async {
    final description = text?.trim();
    if (description == null || description.isEmpty) return;
    if (id != null && (_processedIds.contains(id) || _inFlightIds.contains(id))) {
      debugPrint('[MEAL] Duplicate or in-flight meal $id ignored');
      return;
    }
    if (id != null) _inFlightIds.add(id);

    try {
      debugPrint('[MEAL] Remote meal from watch: "$description" (ID: $id)');

      final est = await MealEstimatorService.estimate(description);
      final now = DateTime.now();
      final meal = MealRecord(
        time: now,
        name: description,
        calories: (est?.calories ?? 0).toDouble(),
        protein: est?.protein?.toDouble(),
        carbs: est?.carbs?.toDouble(),
        fat: est?.fat?.toDouble(),
        mealType: _mealTypeForHour(now.hour),
        syncId: id, // reuse watch id as syncId to prevent future cloud dupes
      );
      await _fp.addMeal(meal);

      // Sync to Health Connect (mirror phone app behavior).
      unawaited(HealthSyncService.logMeal(
        name: meal.name,
        calories: meal.calories,
        protein: meal.protein,
        carbs: meal.carbs,
        fat: meal.fat,
        time: meal.time,
        mealType: _mapToMealType(meal.mealType),
      ));

      if (id != null) await _markProcessed(id);

      // Tell the watch it worked (best-effort; shown if its app is open).
      try {
        if (await _wc.isReachable) {
          await _wc.sendMessage({
            'type': 'mealAck',
            'ids': jsonEncode(_processedIds),
            'name': description,
            'calories': meal.calories.round(),
            'estimated': est != null,
          });
        }
      } catch (_) {}
      // Broadcast refreshed totals (and the ack list) so the tile updates.
      if (broadcastAfter) await _broadcast();
    } catch (e) {
      debugPrint('[MEAL] remote meal failed: $e');
    } finally {
      if (id != null) _inFlightIds.remove(id);
    }
  }

  String _mealTypeForHour(int hour) {
    if (hour < 10) return 'BREAKFAST';
    if (hour < 14) return 'LUNCH';
    if (hour < 21) return 'DINNER';
    return 'SNACK';
  }

  MealType _mapToMealType(String type) {
    return switch (type) {
      'BREAKFAST' => MealType.BREAKFAST,
      'LUNCH' => MealType.LUNCH,
      'DINNER' => MealType.DINNER,
      'SNACK' => MealType.SNACK,
      _ => MealType.UNKNOWN,
    };
  }

  void dispose() {
    _msgSub?.cancel();
    _ctxSub?.cancel();
    _fp.removeListener(_broadcast);
    _profile.removeListener(_broadcast);
  }
}
