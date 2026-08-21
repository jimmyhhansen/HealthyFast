import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/workout_record.dart';
import '../providers/fasting_provider.dart';
import '../providers/training_provider.dart';
import 'program_library_screen.dart';
import 'workout_session_screen.dart' show showExerciseGuide;
import '../widgets/number_wheel_picker.dart';

class WorkoutEditorScreen extends StatefulWidget {
  final WorkoutRecord workout;
  const WorkoutEditorScreen({super.key, required this.workout});

  @override
  State<WorkoutEditorScreen> createState() => _WorkoutEditorScreenState();
}

class _EditableSet {
  double kg;
  int reps;
  _EditableSet({required this.kg, required this.reps});
  Map<String, dynamic> toJson() => {'kg': kg, 'reps': reps};
}

class _EditableExercise {
  String name;
  List<_EditableSet> sets;
  _EditableExercise({required this.name, required this.sets});
}

class _WorkoutEditorScreenState extends State<WorkoutEditorScreen> {
  late String _title;
  late DateTime _startTime;
  late DateTime _endTime;
  late String _intensity;
  late List<_EditableExercise> _exercises;

  @override
  void initState() {
    super.initState();
    _title = widget.workout.title;
    _startTime = widget.workout.startTime;
    _endTime = widget.workout.endTime;
    _intensity = widget.workout.intensity ?? 'moderate';
    
    final json = widget.workout.exercisesJson;
    if (json != null && json.isNotEmpty) {
      try {
        final list = jsonDecode(json) as List;
        _exercises = [
          for (final e in list.whereType<Map>())
            _EditableExercise(
              name: e['n'] as String? ?? 'Exercise',
              sets: [
                for (final s in (e['sets'] as List? ?? []).whereType<Map>())
                  _EditableSet(
                    kg: ((s['kg'] as num?) ?? 0).toDouble(),
                    reps: ((s['reps'] as num?) ?? 0).toInt(),
                  ),
              ],
            ),
        ];
      } catch (_) {
        _exercises = [];
      }
    } else {
      _exercises = [];
    }
  }

  Future<void> _pickTimes() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;

    final startT = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
      helpText: 'START TIME',
    );
    if (startT == null || !mounted) return;

    final endT = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endTime),
      helpText: 'END TIME',
    );
    if (endT == null || !mounted) return;

    setState(() {
      _startTime = DateTime(date.year, date.month, date.day, startT.hour, startT.minute);
      _endTime = DateTime(date.year, date.month, date.day, endT.hour, endT.minute);
      // Ensure end is after start
      if (!_endTime.isAfter(_startTime)) {
        _endTime = _startTime.add(const Duration(minutes: 45));
      }
    });
  }

  Future<void> _convertQuickLog() async {
    final tp = context.read<TrainingProvider>();
    final selectedId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ProgramLibraryScreen()),
    );
    if (selectedId == null || !mounted) return;

    final program = tp.availablePrograms.firstWhere((p) => p.id == selectedId);
    
    final dayIdx = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Choose which day to apply', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < program.days.length; i++)
              ListTile(
                title: Text(program.days[i].title),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (dayIdx == null || !mounted) return;

    final day = program.days[dayIdx];
    setState(() {
      _title = day.title;
      _exercises = [
        for (final e in day.exercises)
          _EditableExercise(
            name: e.name,
            sets: [
              for (var i = 0; i < e.sets; i++)
                _EditableSet(kg: tp.weightFor(e, i), reps: e.reps),
            ],
          ),
      ];
    });
  }

  Future<void> _save() async {
    if (!_endTime.isAfter(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after start time.')));
      return;
    }

    final exercisesJson = jsonEncode([
      for (final e in _exercises)
        {
          'n': e.name,
          'sets': [for (final s in e.sets) s.toJson()],
        },
    ]);

    final fp = context.read<FastingProvider>();
    try {
      await fp.updateWorkout(
        widget.workout,
        title: _title,
        startTime: _startTime,
        endTime: _endTime,
        intensity: _intensity,
        exercisesJson: exercisesJson,
      );
    } catch (e) {
      debugPrint('[TRAIN] Editor save failed: $e');
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = _endTime.difference(_startTime);
    final fp = context.read<FastingProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Workout'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            tooltip: 'Delete workout',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete workout?'),
                  content: const Text('This will permanently remove the record.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (ok == true && mounted) {
                await fp.deleteWorkout(widget.workout);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _card(scheme, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Title', border: InputBorder.none),
                controller: TextEditingController(text: _title),
                onChanged: (v) => _title = v,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Divider(),
              InkWell(
                onTap: _pickTimes,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        '${DateFormat('d MMM, HH:mm').format(_startTime)} – ${DateFormat('HH:mm').format(_endTime)} '
                        '(${duration.inMinutes} min)',
                      ),
                      const Spacer(),
                      const Icon(Icons.edit_outlined, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'light', label: Text('Light')),
                  ButtonSegment(value: 'moderate', label: Text('Moderate')),
                  ButtonSegment(value: 'hard', label: Text('Hard')),
                ],
                selected: {_intensity},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _intensity = s.first),
              ),
            ],
          )),
          const SizedBox(height: 12),
          if (_exercises.isEmpty)
            _card(scheme, child: Column(
              children: [
                const Text('No exercise details yet (Quick Log).'),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _convertQuickLog,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Apply program workout'),
                ),
              ],
            ))
          else
            for (var i = 0; i < _exercises.length; i++) _exerciseCard(scheme, _exercises[i], i),
          
          if (_exercises.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: _convertQuickLog,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Switch to another program'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(ColorScheme scheme, {required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
    ),
    child: child,
  );

  Widget _exerciseCard(ColorScheme scheme, _EditableExercise e, int exIdx) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => showExerciseGuide(context, e.name),
                  child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _exercises.removeAt(exIdx)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < e.sets.length; i++)
            _setRow(scheme, e, i, exIdx),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() {
              final last = e.sets.isEmpty ? null : e.sets.last;
              e.sets.add(_EditableSet(kg: last?.kg ?? 20, reps: last?.reps ?? 10));
            }),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add set'),
          ),
        ],
      ),
    );
  }

  Widget _setRow(ColorScheme scheme, _EditableExercise e, int setIdx, int exIdx) {
    final s = e.sets[setIdx];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(radius: 12, child: Text('${setIdx + 1}', style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => _editValue(e, setIdx),
              child: Text('${s.kg == s.kg.roundToDouble() ? s.kg.round() : s.kg.toStringAsFixed(1)} kg', textAlign: TextAlign.center),
            ),
          ),
          const Text('×'),
          Expanded(
            child: InkWell(
              onTap: () => _editValue(e, setIdx),
              child: Text('${s.reps} reps', textAlign: TextAlign.center),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey),
            onPressed: () => setState(() => e.sets.removeAt(setIdx)),
          ),
        ],
      ),
    );
  }

  Future<void> _editValue(_EditableExercise e, int i) async {
    final s = e.sets[i];
    // Same wheel sheet as the live session screen. This screen has only ever
    // shown kilos, so the wheel counts kilos too rather than quietly changing
    // the unit under an imperial user's existing logs.
    final picked = await showSetPicker(
      context,
      title: '${e.name} — set ${i + 1}',
      kg: s.kg,
      reps: s.reps,
      isImperial: false,
    );
    if (picked == null || !mounted) return;
    setState(() {
      s.kg = picked.kg;
      s.reps = picked.reps;
    });
  }
}
