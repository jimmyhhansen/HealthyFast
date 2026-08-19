import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/exercise.dart';
import '../models/workout_record.dart';
import '../providers/fasting_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/training_provider.dart';
import '../services/exercise_guides.dart';

/// Guided program workout with a live session timer. The session state
/// LIVES IN TrainingProvider — backing out of this screen keeps the
/// workout "in progress" (Resume from the Workout tab) until you finish
/// or cancel. Header shows Duration · Volume · Sets · a low-end kcal
/// estimate; sets are logged in a table with the previous session's
/// numbers alongside.
class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  Timer? _restTimer;
  int _restLeft = 0;
  bool _finishing = false;

  ActiveWorkoutSession? get _session =>
      context.read<TrainingProvider>().activeSession;

  @override
  void initState() {
    super.initState();
    // Timer derives from the session's start time, so it keeps counting
    // even while this screen is closed.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _session;
      if (mounted && s != null) {
        setState(() => _elapsed = DateTime.now().difference(s.startedAt));
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _restTimer?.cancel();
    super.dispose();
  }

  void _startRest() {
    _restTimer?.cancel();
    setState(() => _restLeft = 180);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _restLeft--;
        if (_restLeft <= 0) t.cancel();
      });
    });
  }

  static String _kg(double v, {bool isImperial = false}) {
    final value = isImperial ? v / 0.45359237 : v;
    return value == value.roundToDouble() ? value.round().toString() : value.toStringAsFixed(1);
  }

  double _volume(ActiveWorkoutSession s, {bool isImperial = false}) {
    final v = s.exercises.fold(
        0.0,
        (sum, e) =>
            sum +
            e.sets
                .where((x) => x.done)
                .fold(0.0, (t, x) => t + x.kg * x.reps));
    return isImperial ? v / 0.45359237 : v;
  }

  int _doneSets(ActiveWorkoutSession s) => s.exercises
      .fold(0, (sum, e) => sum + e.sets.where((x) => x.done).length);

  /// Live low-end kcal estimate: strength MET 3.5 × weight × elapsed,
  /// nudged by intensity — the same model the journal uses afterwards.
  int _kcalEstimate(ActiveWorkoutSession s) {
    final weight = context.read<ProfileProvider>().weightKg ?? 75;
    final factor = switch (s.intensity) {
      'light' => 0.8,
      'hard' => 1.15,
      _ => 1.0,
    };
    return (3.5 * weight * (_elapsed.inSeconds / 3600.0) * factor).round();
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel workout?'),
        content: const Text('The session and its logged sets are discarded.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel workout')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<TrainingProvider>().cancelSession();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final session = _session;
    if (session == null) {
      Navigator.of(context).pop();
      return;
    }
    final anyDone = session.exercises.any((e) => e.sets.any((s) => s.done));
    if (!anyDone) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _finishing = true);
    final fp = context.read<FastingProvider>();
    final tp = context.read<TrainingProvider>();

    try {
      debugPrint('[TRAIN] Finishing workout: ${session.dayTitle}');
      final programName = tp.program?.name;
      final fullTitle = programName != null 
          ? '$programName, ${session.dayTitle}' 
          : session.dayTitle;

      final exercisesJson = jsonEncode([
        for (final e in session.exercises)
          if (e.sets.any((s) => s.done))
            {
              'n': e.name,
              'sets': [
                for (final s in e.sets)
                  if (s.done) {'kg': s.kg, 'reps': s.reps},
              ],
            },
      ]);

      await fp.addWorkout(WorkoutRecord(
        startTime: session.startedAt,
        endTime: DateTime.now(),
        title: fullTitle,
        exercisesJson: exercisesJson,
        programId: session.programId,
        programDayIdx: session.dayIdxInSplit,
        activityType: 'STRENGTH_TRAINING',
        intensity: session.intensity,
      ));
      debugPrint('[TRAIN] Workout record added to history');

      // Advance progression when this session matches the program's
      // expected next day.
      final day = tp.nextDay;
      if (day != null && day.title == session.dayTitle) {
        debugPrint('[TRAIN] Updating program progression');
        await tp.completeWorkout(
          day,
          {
            for (final e in session.exercises) e.name: e.succeeded,
          },
          usedKg: {
            for (final e in session.exercises)
              if (e.sets.any((s) => s.done))
                e.name: e.sets
                    .where((s) => s.done)
                    .map((s) => s.kg)
                    .toList(),
          },
          usedReps: {
            for (final e in session.exercises)
              if (e.sets.any((s) => s.done))
                e.name: e.sets
                    .where((s) => s.done)
                    .map((s) => s.reps)
                    .toList(),
          },
        );
      }
      
      await tp.clearSession();
      debugPrint('[TRAIN] Session cleared');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Workout saved — weights updated for next time.')));
        // Use popUntil to ensure we land back on the RootScreen (index 0)
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      debugPrint('[TRAIN] CRITICAL ERROR in _finish: $e');
      setState(() => _finishing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving workout: $e')));
      }
    }
  }

  String _fmtElapsed() {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Rebuild when the provider-held session changes.
    final session = context.watch<TrainingProvider>().activeSession;
    final pp = context.watch<ProfileProvider>();
    final isImperial = pp.unitSystem == UnitSystem.imperial;
    final weightUnit = isImperial ? 'lbs' : 'kg';

    if (session == null) {
      // Finished/cancelled elsewhere — nothing to show.
      return const Scaffold(body: SizedBox.shrink());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(session.dayTitle),
        actions: [
          TextButton(
            onPressed: _cancel,
            child: Text('Cancel',
                style: TextStyle(color: scheme.error)),
          ),
          if (_restLeft > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  'Rest ${_restLeft ~/ 60}:'
                  '${(_restLeft % 60).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'light', label: Text('Light')),
                    ButtonSegment(value: 'moderate', label: Text('Moderate')),
                    ButtonSegment(value: 'hard', label: Text('Hard')),
                  ],
                  selected: {session.intensity},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (s) {
                    setState(() => session.intensity = s.first);
                    context.read<TrainingProvider>().persistSession();
                  },
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: _finish,
                child: const Text('Finish workout'),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          children: [
            // ── Live session summary ─────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Expanded(
                      child: _headItem(scheme, 'Duration', _fmtElapsed(),
                          highlight: true)),
                  _vDivider(scheme),
                  Expanded(
                      child: _headItem(scheme, 'Volume',
                          '${_volume(session, isImperial: isImperial).round()} $weightUnit')),
                  _vDivider(scheme),
                  Expanded(
                      child: _headItem(
                          scheme, 'Sets', '${_doneSets(session)}')),
                  _vDivider(scheme),
                  Expanded(
                      child: _headItem(scheme, '≈ Burn',
                          '${_kcalEstimate(session)} kcal')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final e in session.exercises) _exerciseCard(scheme, e, isImperial),
          ],
        ),
      ),
    );
  }

  Widget _vDivider(ColorScheme scheme) => Container(
        width: 1,
        height: 32,
        color: scheme.outlineVariant.withValues(alpha: 0.6),
      );

  Widget _headItem(ColorScheme scheme, String label, String value,
      {bool highlight = false}) {
    return Column(
      children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: highlight ? scheme.primary : null,
                  )),
        ),
      ],
    );
  }

  Widget _exerciseCard(ColorScheme scheme, ActiveExercise e, bool isImperial) {
    final labelStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.5);
    final weightUnit = isImperial ? 'LBS' : 'KG';
    final previous = context.read<FastingProvider>().previousSets(e.name);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showExerciseGuide(context, e.name),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Click for guide',
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.info_outline_rounded,
                        size: 20, color: scheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Table header: SET · PREVIOUS · KG · REPS · ✓
          Row(
            children: [
              SizedBox(width: 30, child: Text('SET', style: labelStyle)),
              Expanded(
                  flex: 3, child: Text('PREVIOUS', style: labelStyle)),
              Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(weightUnit, style: labelStyle),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_outlined, size: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ],
                  )),
              Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('REPS', style: labelStyle),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_outlined, size: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ],
                  )),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < e.sets.length; i++)
            _setRow(scheme, e, i, previous, isImperial),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add set'),
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              onPressed: () {
                setState(() {
                  final last = e.sets.isEmpty ? null : e.sets.last;
                  if (last != null) {
                    e.sets.add(ActiveSet(kg: last.kg, reps: last.reps));
                  } else {
                    // Try to pre-fill from history
                    final hist = context.read<FastingProvider>().previousSets(e.name);
                    if (hist.isNotEmpty) {
                      e.sets.add(ActiveSet(kg: hist.first.$1, reps: hist.first.$2));
                    } else {
                      e.sets.add(ActiveSet(kg: 20, reps: e.targetReps));
                    }
                  }
                });
                context.read<TrainingProvider>().persistSession();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _setRow(ColorScheme scheme, ActiveExercise e, int i,
      List<(double, int)> previous, bool isImperial) {
    final s = e.sets[i];
    final prev = i < previous.length ? previous[i] : null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: s.done
            ? const Color(0xFF1D9E75).withValues(alpha: 0.12)
            : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text('${i + 1}',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: scheme.primary)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              prev == null ? '—' : '${_kg(prev.$1, isImperial: isImperial)}${isImperial ? 'lb' : 'kg'} × ${prev.$2}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          // Tap kg or reps to adjust that set.
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () => _editValue(e, i, editKg: true, isImperial: isImperial),
              child: Text(_kg(s.kg, isImperial: isImperial),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () => _editValue(e, i, editKg: false, isImperial: isImperial),
              child: Text('${s.reps}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                s.done
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked,
                color:
                    s.done ? const Color(0xFF1D9E75) : scheme.outlineVariant,
              ),
              onPressed: () {
                setState(() => s.done = !s.done);
                context.read<TrainingProvider>().persistSession();
                if (s.done) _startRest();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editValue(ActiveExercise e, int i,
      {required bool editKg, required bool isImperial}) async {
    final s = e.sets[i];
    var kg = s.kg;
    var reps = s.reps;

    final controller = TextEditingController(
        text: editKg ? (isImperial ? _kg(kg, isImperial: true) : _kg(kg)) : reps.toString());

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${e.name} — set ${i + 1}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: false),
                decoration: InputDecoration(
                  labelText: editKg ? (isImperial ? 'Weight (lbs)' : 'Weight (kg)') : 'Reps',
                  suffixText: editKg ? (isImperial ? 'lbs' : 'kg') : 'reps',
                  border: const OutlineInputBorder(),
                  filled: true,
                ),
                onChanged: (val) {
                  final n = double.tryParse(val.replaceAll(',', '.'));
                  if (n != null) {
                    if (editKg) {
                      kg = isImperial ? n * 0.45359237 : n;
                    } else {
                      reps = n.round();
                    }
                  }
                },
                onSubmitted: (val) {
                  final n = double.tryParse(val.replaceAll(',', '.'));
                  if (n != null) {
                    setState(() {
                      if (editKg) {
                        s.kg = isImperial ? n * 0.45359237 : n;
                      } else {
                        s.reps = n.round();
                      }
                    });
                    context.read<TrainingProvider>().persistSession();
                    Navigator.pop(ctx);
                  }
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () {
                      setLocal(() {
                        if (editKg) {
                          if (isImperial) {
                            var lbs = kg / 0.45359237;
                            lbs = (lbs - 1).clamp(0, 2000);
                            kg = lbs * 0.45359237;
                            controller.text = _kg(kg, isImperial: true);
                          } else {
                            kg = (kg - 0.5).clamp(0, 999);
                            controller.text = _kg(kg);
                          }
                        } else {
                          if (reps > 0) reps--;
                          controller.text = reps.toString();
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 24),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      setLocal(() {
                        if (editKg) {
                          if (isImperial) {
                            var lbs = kg / 0.45359237;
                            lbs += 1;
                            kg = lbs * 0.45359237;
                            controller.text = _kg(kg, isImperial: true);
                          } else {
                            kg += 0.5;
                            controller.text = _kg(kg);
                          }
                        } else {
                          reps++;
                          controller.text = reps.toString();
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
                onPressed: () {
                  setState(() {
                    s.kg = kg;
                    s.reps = reps;
                  });
                  context.read<TrainingProvider>().persistSession();
                  Navigator.pop(ctx);
                },
                child: const Text('Set')),
          ],
        ),
      ),
    );
  }
}

/// Exercise guide sheet: open illustration (Free Exercise DB, public
/// domain), numbered steps, and a form-video search link.
Future<void> showExerciseGuide(BuildContext context, String name) {
  final guide = ExerciseGuides.byName(name);
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(name,
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (guide != null && (guide.imageIds.isNotEmpty || guide.customImagePath != null))
              _GuideImages(guide: guide),
            const SizedBox(height: 12),
            if (guide != null)
              for (var i = 0; i < guide.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: scheme.primaryContainer,
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimaryContainer)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(guide.steps[i],
                            style: Theme.of(ctx)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(height: 1.4)),
                      ),
                    ],
                  ),
                )
            else
              Text(
                'No guide available for this exercise yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Watch a form video'),
              onPressed: () => launchUrl(
                Uri.parse(guide?.videoUrl ??
                    'https://www.youtube.com/results?search_query='
                        '${Uri.encodeComponent('$name proper form')}'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ExerciseGuides.attribution,
              style: Theme.of(ctx)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    },
  );
}

/// Loads the two illustration frames, falling back through candidate ids
/// and finally to nothing — a wrong id never breaks the sheet.
class _GuideImages extends StatefulWidget {
  final Exercise guide;
  const _GuideImages({required this.guide});

  @override
  State<_GuideImages> createState() => _GuideImagesState();
}

class _GuideImagesState extends State<_GuideImages> {
  int _candidate = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.guide.customImagePath != null) {
      final file = File(widget.guide.customImagePath!);
      if (file.existsSync()) {
        return GestureDetector(
          onTap: () => _openFull(context, Image.file(file)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(file, height: 180, width: double.infinity, fit: BoxFit.cover),
          ),
        );
      }
    }

    if (_candidate >= widget.guide.imageIds.length) {
      return const SizedBox.shrink();
    }
    final urls = widget.guide.imageUrls(widget.guide.imageIds[_candidate]);
    return Row(
      children: [
        for (final url in urls)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _openFull(context, Image.network(url)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    height: 130,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted &&
                            _candidate < widget.guide.imageIds.length) {
                          setState(() => _candidate++);
                        }
                      });
                      return const SizedBox(height: 130);
                    },
                    loadingBuilder: (ctx, child, progress) => progress == null
                        ? child
                        : const SizedBox(
                            height: 130,
                            child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openFull(BuildContext context, Widget image) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: image,
            ),
          ),
        ),
      ),
    );
  }
}
