import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watch_connectivity/watch_connectivity.dart';
import '../models/workout_record.dart';
import '../providers/fasting_provider.dart';
import '../providers/training_provider.dart';
import '../services/meal_sync_queue.dart';
import '../services/ongoing_activity_service.dart';
import '../services/training_programs.dart';
import '../widgets/wear_scroll_view.dart';

/// Guided workout logging on the watch, fully standalone:
///  1. pick the workout (day in the split),
///  2. pick an exercise,
///  3. log set 1 with kg/reps steppers + Save → next set,
///  4. after the last set: add an extra set or go to the next exercise,
///  5. Finish saves LOCALLY (watch Hive) with the real elapsed time and
///     queues the workout for the phone — synced at first opportunity.
class WatchWorkoutFlow extends StatefulWidget {
  const WatchWorkoutFlow({super.key});

  @override
  State<WatchWorkoutFlow> createState() => _WatchWorkoutFlowState();
}

class _FlowSet {
  _FlowSet(this.kg, this.reps);
  double kg;
  int reps;
}

class _FlowExercise {
  _FlowExercise(this.name, this.targetSets, this.targetReps, this.kg);
  final String name;
  final int targetSets;
  final int targetReps;
  double kg;
  final List<_FlowSet> logged = [];
}

enum _Stage { pickProgram, pickDay, exercises, set, afterExercise, sent }

class _WatchWorkoutFlowState extends State<WatchWorkoutFlow> {
  final _wc = WatchConnectivity();
  _Stage _stage = _Stage.pickProgram;

  String _programName = '';
  List<(String, List<_FlowExercise>)> _days = const [];
  List<Program> _allPrograms = [];
  int _dayIdx = 0;
  int _exIdx = 0;
  int _setNo = 0;
  DateTime? _startedAt;
  bool _loaded = false;
  bool _deliveredNow = false;

  List<_FlowExercise> get _exercises =>
      _days.isEmpty ? const [] : _days[_dayIdx].$2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load all programs synced from the phone
      final allRaw = prefs.getString('all_programs_json');
      if (allRaw != null && allRaw.isNotEmpty) {
        final list = jsonDecode(allRaw) as List;
        _allPrograms = [
          for (final p in list)
            if (p is Map) Program.fromJson(p.cast<String, dynamic>())
        ];
      } else {
        // Fallback to bundled programs if no sync yet
        _allPrograms = TrainingPrograms.all;
      }

      final raw = prefs.getString('program_json');
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map;
        _programName = m['name'] as String? ?? 'Program';
        _days = [
          for (final d in (m['days'] as List? ?? const []))
            if (d is Map)
              (
                d['title'] as String? ?? 'Day',
                [
                  for (final e in (d['exercises'] as List? ?? const []))
                    if (e is Map)
                      _FlowExercise(
                        e['n'] as String? ?? 'Exercise',
                        ((e['sets'] as num?) ?? 3).toInt(),
                        ((e['reps'] as num?) ?? 5).toInt(),
                        ((e['kg'] as num?) ?? 20).toDouble(),
                      ),
                ],
              ),
        ];
      }
    } catch (_) {}

    // Resume an already-started session (e.g. this screen was backed out
    // of, or the app was reopened) instead of forcing the user back to
    // "pick a program". Without this, re-tapping the same day in
    // _startDay would call tp.startSession() a second time and silently
    // wipe any sets already logged — going back or switching exercises
    // must never restart or end an in-progress workout.
    if (mounted) {
      final session = context.read<TrainingProvider>().activeSession;
      if (session != null) {
        final idx = _days.indexWhere((d) => d.$1 == session.dayTitle);
        if (idx != -1) {
          _dayIdx = idx;
          _startedAt = session.startedAt;
          final exercises = _exercises;
          for (var i = 0;
              i < exercises.length && i < session.exercises.length;
              i++) {
            for (final s in session.exercises[i].sets.where((s) => s.done)) {
              exercises[i].logged.add(_FlowSet(s.kg, s.reps));
            }
            if (exercises[i].logged.isNotEmpty) {
              exercises[i].kg = exercises[i].logged.last.kg;
            }
          }
          _stage = _Stage.exercises;
        }
      }
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _startDay(int idx) async {
    _dayIdx = idx;
    final tp = context.read<TrainingProvider>();
    final dayTitle = _days[idx].$1;
    final existing = tp.activeSession;

    if (existing != null && existing.dayTitle == dayTitle) {
      // Resume rather than restart: starting a fresh session here would
      // silently wipe any sets already logged for this day.
      _startedAt = existing.startedAt;
    } else {
      _exIdx = 0;
      _setNo = 0;
      _startedAt = DateTime.now();
      // Start the active session in the shared provider. This stays local
      // to this device until "Finish workout" — see the comment on
      // 'activeSession' in WatchSyncService._broadcast().
      final p = tp.program;
      if (p != null && idx < p.days.length) {
        await tp.startSession(p.days[idx]);
      }
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_in_progress', dayTitle);
      await prefs.setInt(
          'workout_start_ms', _startedAt!.millisecondsSinceEpoch);
    } catch (_) {}

    // 3) Start the workout's own ongoing-activity chip/timer. This runs
    // fully independently of the fasting one (separate notification), so
    // starting a workout never pauses or breaks an active fast's timer —
    // both can be shown on the watch face at the same time.
    final fullTitle =
        _programName.isNotEmpty ? '$_programName, $dayTitle' : dayTitle;
    unawaited(OngoingActivityService.startWorkout(
      startMs: _startedAt!.millisecondsSinceEpoch,
      title: fullTitle,
    ));

    unawaitedRefresh();
    setState(() => _stage = _Stage.exercises);
  }

  void unawaitedRefresh() {
    OngoingActivityService.refreshTiles();
  }

  Future<void> _finish() async {
    final started = _startedAt ?? DateTime.now();
    final dayTitle = _days[_dayIdx].$1;
    final fullTitle = _programName.isNotEmpty 
        ? '$_programName, $dayTitle' 
        : dayTitle;

    final exercisesJson = jsonEncode([
      for (final e in _exercises)
        if (e.logged.isNotEmpty)
          {
            'n': e.name,
            'sets': [
              for (final s in e.logged) {'kg': s.kg, 'reps': s.reps},
            ],
          },
    ]);

    // 1) Update progression LOCALLY on the watch's provider.
    final tp = context.read<TrainingProvider>();
    final currentDay = tp.nextDay;
    if (currentDay != null && currentDay.title == dayTitle) {
      await tp.completeWorkout(
        currentDay,
        {for (final e in _exercises) e.name: e.logged.length >= e.targetSets},
        usedKg: {for (final e in _exercises) if (e.logged.isNotEmpty) e.name: e.logged.map((s) => s.kg).toList()},
        usedReps: {for (final e in _exercises) if (e.logged.isNotEmpty) e.name: e.logged.map((s) => s.reps).toList()},
      );
    }
    await tp.clearSession();

    // 2) Save to Journal history (Hive).
    try {
      if (mounted) {
        await context.read<FastingProvider>().addWorkout(WorkoutRecord(
              startTime: started,
              endTime: DateTime.now(),
              title: fullTitle,
              exercisesJson: exercisesJson,
              activityType: 'STRENGTH_TRAINING',
              source: 'watch',
            ));
      }
    } catch (_) {}

    // 3) Queue for the phone (real elapsed time travels with it) and try
    //    the fast path when reachable.
    final payload = await MealSyncQueue.enqueueRaw({
      'type': 'workout',
      'title': fullTitle,
      'dayTitle': dayTitle, // Send raw day title for progression matching
      'startMs': started.millisecondsSinceEpoch,
      'endMs': DateTime.now().millisecondsSinceEpoch,
      'exercises': exercisesJson,
    });
    var delivered = false;
    try {
      if (await _wc.isReachable
          .timeout(const Duration(seconds: 3), onTimeout: () => false)) {
        await _wc.sendMessage(payload);
        delivered = true;
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('workout_in_progress');
      await prefs.remove('workout_start_ms');
    } catch (_) {}
    // Stop only the workout chip — the fasting one (if any) is untouched.
    unawaited(OngoingActivityService.stopWorkout());
    unawaitedRefresh();

    if (!mounted) return;
    setState(() {
      _deliveredNow = delivered;
      _stage = _Stage.sent;
    });
    await Future.delayed(const Duration(milliseconds: 1600));
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    // Always let the user confirm/change the Program first — Program →
    // workout → exercises. Only auto-skip once a program is picked for
    // this session (see _adoptProgram / the "current program" pill).
    //
    // The hardware/swipe back gesture on Wear OS pops the current route by
    // default, which used to exit this whole flow (and the app) from any
    // stage — losing your place mid-set. PopScope intercepts that: from
    // any stage after picking a program, back steps to the previous stage
    // instead. The active session itself is untouched either way (it lives
    // in TrainingProvider, not in this widget's stage) — only leaving the
    // very first "pick a program" stage actually exits.
    return PopScope(
      canPop: _stage == _Stage.pickProgram || _stage == _Stage.sent,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          _stage = switch (_stage) {
            _Stage.pickDay => _Stage.pickProgram,
            _Stage.exercises => _Stage.pickDay,
            _Stage.set => _Stage.exercises,
            _Stage.afterExercise => _Stage.exercises,
            _Stage.pickProgram || _Stage.sent => _stage,
          };
        });
      },
      child: switch (_stage) {
        _Stage.pickProgram => _pickProgramScreen(),
        _Stage.pickDay => _pickDayScreen(),
        _Stage.exercises => _exercisesScreen(),
        _Stage.set => _setScreen(),
        _Stage.afterExercise => _afterExerciseScreen(),
        _Stage.sent => _sentScreen(),
      },
    );
  }


  Widget _pill(String text,
      {Color? color, VoidCallback? onTap, bool small = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? Colors.grey.shade900,
          minimumSize: Size.fromHeight(small ? 36 : 42),
          shape: const StadiumBorder(),
        ),
        onPressed: onTap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: small ? 12 : 14,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // ── 0: choose (or confirm) the program — always shown first ───────────
  Widget _pickProgramScreen() {
    final hasProgram = _days.isNotEmpty;
    final custom = _allPrograms.where((p) => p.experience == 'Custom').toList();
    final bundled = _allPrograms.where((p) => p.experience != 'Custom').toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 26),
        children: [
          const Text(
            'Choose a program',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          if (hasProgram) ...[
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                'CURRENT',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
            _pill(_programName,
                color: Colors.green.shade900,
                onTap: () => setState(() => _stage = _Stage.pickDay)),
            const SizedBox(height: 4),
          ],
          
          if (custom.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 6, bottom: 2),
              child: Text(
                'CUSTOM',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
            for (final p in custom)
              _pill(p.name, onTap: () => _adoptProgram(p)),
          ],

          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 2),
            child: Text(
              'BUILT-IN',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          for (final p in bundled)
            _pill(p.name, onTap: () => _adoptProgram(p)),
        ],
      ),
    );
  }

  /// Adopts a bundled program locally (start weights) and persists it in
  /// the same 'program_json' format the phone syncs — so the tile and the
  /// next launch see it too. A later phone sync simply overwrites it.
  Future<void> _adoptProgram(Program p) async {
    HapticFeedback.selectionClick();
    _programName = p.name;
    _days = [
      for (final d in p.days)
        (
          d.title,
          [
            for (final e in d.exercises)
              _FlowExercise(e.name, e.sets, e.reps, e.startKg),
          ],
        ),
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'program_json',
          jsonEncode({
            'name': p.name,
            'dayIdx': 0,
            'days': [
              for (final d in p.days)
                {
                  'title': d.title,
                  'exercises': [
                    for (final e in d.exercises)
                      {
                        'n': e.name,
                        'sets': e.sets,
                        'reps': e.reps,
                        'kg': e.startKg,
                      },
                  ],
                },
            ],
          }));
    } catch (_) {}
    if (mounted) setState(() => _stage = _Stage.pickDay);
  }

  // ── 1: choose the workout ─────────────────────────────────────────────
  Widget _pickDayScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 26),
        children: [
          Text(
            _programName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _days.length; i++)
            _pill(_days[i].$1, onTap: () => _startDay(i)),
          const SizedBox(height: 4),
          _pill('Change program', small: true,
              onTap: () => setState(() => _stage = _Stage.pickProgram)),
        ],
      ),
    );
  }

  // ── 2: exercises in the chosen workout ────────────────────────────────
  Widget _exercisesScreen() {
    final anyLogged = _exercises.any((e) => e.logged.isNotEmpty);
    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 26),
        children: [
          Text(
            _days[_dayIdx].$1,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _exercises.length; i++)
            _pill(
              '${_exercises[i].name} · ${_exercises[i].logged.length}/'
              '${_exercises[i].targetSets}',
              color: _exercises[i].logged.length >=
                      _exercises[i].targetSets
                  ? Colors.green.shade900
                  : null,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _exIdx = i;
                  _setNo = _exercises[i].logged.length;
                  _stage = _Stage.set;
                });
              },
            ),
          const SizedBox(height: 4),
          _pill('Finish workout',
              color: anyLogged ? Colors.green.shade800 : Colors.grey.shade800,
              onTap: anyLogged ? _finish : null),
        ],
      ),
    );
  }

  // ── 3: one set at a time ──────────────────────────────────────────────
  Widget _setScreen() {
    final e = _exercises[_exIdx];
    final side = MediaQuery.sizeOf(context).shortestSide;
    // Bezel-safe inset — same convention as WearScrollView's _safePadding.
    // Without this, FittedBox scales its child to fit the full (rectangular)
    // screen size, so at large system font/display sizes the Save set
    // button — the bottommost element — can land in the bezel-clipped zone
    // on round displays. Reserving this padding shrinks the available space
    // FittedBox scales into, forcing everything down a notch so the button
    // stays fully on-screen.
    final safeInset = side * 0.18;
    var reps = e.targetReps;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: safeInset, vertical: safeInset),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: side * 0.82),
              child: _SetEditor(
                key: ValueKey('$_exIdx-$_setNo'),
                exerciseName: e.name,
                setNo: _setNo + 1,
                initialKg: e.kg,
                initialReps: reps,
                  onSave: (kg, savedReps) async {
                  HapticFeedback.selectionClick();
                  
                  // Update the local TrainingProvider session so it broadcasts to the phone
                  final tp = context.read<TrainingProvider>();
                  final session = tp.activeSession;
                  if (session != null && _exIdx < session.exercises.length) {
                    final ex = session.exercises[_exIdx];
                    if (_setNo < ex.sets.length) {
                      ex.sets[_setNo].kg = kg;
                      ex.sets[_setNo].reps = savedReps;
                      ex.sets[_setNo].done = true;
                    } else {
                      // Extra set
                      ex.sets.add(ActiveSet(kg: kg, reps: savedReps, done: true));
                    }
                    await tp.persistSession();
                  }

                  setState(() {
                    e.kg = kg;
                    e.logged.add(_FlowSet(kg, savedReps));
                    if (e.logged.length >= e.targetSets) {
                      _stage = _Stage.afterExercise;
                    } else {
                      _setNo = e.logged.length;
                    }
                  });
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 4: after the last set of an exercise ──────────────────────────────
  Widget _afterExerciseScreen() {
    final e = _exercises[_exIdx];
    final hasNext = _exercises.any((x) => x.logged.length < x.targetSets);
    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 26),
        children: [
          Text(
            '${e.name} done · ${e.logged.length} sets',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _pill('Add extra set', onTap: () {
            setState(() {
              _setNo = e.logged.length;
              _stage = _Stage.set;
            });
          }),
          if (hasNext)
            _pill('Next exercise', color: Colors.green.shade800, onTap: () {
              setState(() => _stage = _Stage.exercises);
            })
          else
            _pill('Finish workout',
                color: Colors.green.shade800, onTap: _finish),
        ],
      ),
    );
  }

  Widget _sentScreen() => Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _deliveredNow
                    ? Icons.check_circle
                    : Icons.schedule_send_rounded,
                color: _deliveredNow ? Colors.green : Colors.amber,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                _deliveredNow
                    ? 'Saved — sent to phone'
                    : 'Saved on watch —\nsyncs when phone is nearby',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );
}

/// One set: kg + reps steppers with a Save button. Pre-filled from the
/// program/progression; minus left, plus right, value centred.
class _SetEditor extends StatefulWidget {
  const _SetEditor({
    super.key,
    required this.exerciseName,
    required this.setNo,
    required this.initialKg,
    required this.initialReps,
    required this.onSave,
  });

  final String exerciseName;
  final int setNo;
  final double initialKg;
  final int initialReps;
  final void Function(double kg, int reps) onSave;

  @override
  State<_SetEditor> createState() => _SetEditorState();
}

class _SetEditorState extends State<_SetEditor> {
  late double _kg = widget.initialKg;
  late int _reps = widget.initialReps;

  Widget _stepperRow(String value, VoidCallback onMinus, VoidCallback onPlus) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          iconSize: 30,
          icon: const Icon(Icons.remove_circle_outline,
              color: Colors.white70),
          onPressed: () {
            HapticFeedback.lightImpact();
            onMinus();
          },
        ),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        IconButton(
          iconSize: 30,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
          onPressed: () {
            HapticFeedback.lightImpact();
            onPlus();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.exerciseName,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          'Set ${widget.setNo}',
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        _stepperRow(
          '${_kg == _kg.roundToDouble() ? _kg.round() : _kg.toStringAsFixed(1)} kg',
          () => setState(() => _kg = (_kg - 2.5).clamp(0, 999)),
          () => setState(() => _kg += 2.5),
        ),
        _stepperRow(
          '$_reps reps',
          () => setState(() => _reps = (_reps - 1).clamp(0, 99)),
          () => setState(() => _reps++),
        ),
        const SizedBox(height: 6),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade800,
            minimumSize: const Size(130, 42),
            shape: const StadiumBorder(),
          ),
          onPressed: () => widget.onSave(_kg, _reps),
          child: const Text('Save set',
              style: TextStyle(fontSize: 14, color: Colors.white)),
        ),
      ],
    );
  }
}
