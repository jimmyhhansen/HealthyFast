import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/exercise.dart';
import '../providers/training_provider.dart';
import '../services/custom_exercises_service.dart';
import '../services/custom_programs_service.dart';
import '../services/exercise_guides.dart';
import '../services/training_programs.dart';

/// Settings → Workout programs: bundled programs (read-only) and the
/// user's own programs with create/edit/delete.
class ProgramsManagerScreen extends StatefulWidget {
  const ProgramsManagerScreen({super.key});

  @override
  State<ProgramsManagerScreen> createState() => _ProgramsManagerScreenState();
}

class _ProgramsManagerScreenState extends State<ProgramsManagerScreen> {
  List<Program> _customProgs = [];
  List<Exercise> _customExs = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final progs = await CustomProgramsService.load();
    final exs = await CustomExercisesService.load();
    await ExerciseGuides.init();
    if (mounted) {
      setState(() {
        _customProgs = progs;
        _customExs = exs;
      });
    }
    if (mounted) {
      await context.read<TrainingProvider>().refreshCustomPrograms();
    }
  }

  Future<void> _editProg([Program? existing]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => ProgramEditorScreen(existing: existing)),
    );
    if (changed == true) await _reload();
  }

  Future<void> _editEx([Exercise? existing]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => ExerciseEditorScreen(existing: existing)),
    );
    if (changed == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Workout programs')),
      floatingActionButton: FloatingActionButton(
        // Explicit tag — pushed via Navigator so unlikely to coexist with a
        // bottom-nav tab's FAB, but a unique tag costs nothing and avoids
        // ever hitting the "multiple heroes share the same tag" issue (see
        // meals_dashboard_screen.dart).
        heroTag: 'fab_program_editor',
        tooltip: 'Create program',
        elevation: 0,
        onPressed: () => _editProg(),
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Text('YOUR PROGRAMS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    )),
            if (_customProgs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No custom programs yet. Tap + to build your own — it '
                  'gets the same progression engine as the built-in ones.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              for (final p in _customProgs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_note_rounded),
                  title: Text(p.name),
                  subtitle: Text(
                      '${p.daysPerWeek} · ${p.days.length} day types'),
                  onTap: () => _editProg(p),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      await CustomProgramsService.delete(p.id);
                      await _reload();
                    },
                  ),
                ),
            const SizedBox(height: 16),
            Text('BUILT-IN',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    )),
            for (final p in TrainingPrograms.all)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fitness_center_rounded),
                title: Text('${p.name} · ${p.experience}'),
                subtitle: Text('${p.daysPerWeek} — ${p.source}',
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('YOUR EXERCISES',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        )),
                TextButton.icon(
                  onPressed: () => _editEx(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add new'),
                ),
              ],
            ),
            if (_customExs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No custom exercises yet. Add your own to use them in your '
                  'programs.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              for (final e in _customExs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fitness_center_rounded),
                  title: Text(e.name),
                  subtitle: Text(e.muscleGroup),
                  onTap: () => _editEx(e),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      await CustomExercisesService.delete(e.name);
                      await _reload();
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// Create/edit a custom exercise.
class ExerciseEditorScreen extends StatefulWidget {
  const ExerciseEditorScreen({super.key, this.existing, this.initialName});
  final Exercise? existing;

  /// Pre-fills the name field when creating a new exercise — e.g. the
  /// search text that didn't match anything in the library.
  final String? initialName;

  @override
  State<ExerciseEditorScreen> createState() => _ExerciseEditorScreenState();
}

class _ExerciseEditorScreenState extends State<ExerciseEditorScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? widget.initialName);
  late final TextEditingController _muscle =
      TextEditingController(text: widget.existing?.muscleGroup ?? 'Other');
  late final TextEditingController _video =
      TextEditingController(text: widget.existing?.videoUrl);
  late final List<TextEditingController> _stepCtrls;
  String? _customImagePath;

  @override
  void initState() {
    super.initState();
    _customImagePath = widget.existing?.customImagePath;
    _stepCtrls = (widget.existing?.steps ?? [''])
        .map((s) => TextEditingController(text: s))
        .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _muscle.dispose();
    _video.dispose();
    for (final c in _stepCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _customImagePath = image.path);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give the exercise a name.')));
      return;
    }
    final steps = _stepCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    final exercise = Exercise(
      name: name,
      muscleGroup: _muscle.text.trim(),
      videoUrl: _video.text.trim().isEmpty ? null : _video.text.trim(),
      steps: steps,
      imageIds: widget.existing?.imageIds ?? const [],
      customImagePath: _customImagePath,
    );
    await CustomExercisesService.upsert(exercise);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add exercise' : 'Edit exercise'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Image Picker Header
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: _customImagePath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(19),
                          child: Image.file(File(_customImagePath!), fit: BoxFit.cover),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_rounded, color: scheme.primary),
                            const SizedBox(height: 4),
                            Text('Add image', style: TextStyle(color: scheme.primary, fontSize: 12)),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. Bench press)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _muscle,
              decoration: const InputDecoration(
                labelText: 'Muscle group (e.g. Chest)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _video,
              decoration: const InputDecoration(
                labelText: 'Video URL (optional)',
                hintText: 'https://youtube.com/...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text('STEPS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    )),
            const SizedBox(height: 12),
            for (var i = 0; i < _stepCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _stepCtrls[i],
                        decoration: const InputDecoration(
                          hintText: 'Describe how to perform...',
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => setState(() => _stepCtrls.removeAt(i).dispose()),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => setState(() => _stepCtrls.add(TextEditingController())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add step'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Create/edit one custom program: name, level, days and exercises.
class ProgramEditorScreen extends StatefulWidget {
  const ProgramEditorScreen({super.key, this.existing, this.isAiDraft = false});
  final Program? existing;

  /// True when [existing] is an unsaved AI-generated draft being reviewed
  /// for the first time — tweaks the title so it doesn't read as "Edit"
  /// for something that was never saved yet.
  final bool isAiDraft;

  @override
  State<ProgramEditorScreen> createState() => _ProgramEditorScreenState();
}

class _EditableExercise {
  String name;
  int sets;
  int reps;
  double startKg;
  double incrementKg;
  _EditableExercise({
    // Empty by default: a placeholder name like 'Exercise' reads as a
    // suggestion and gets saved as-is. The picker opens on the list instead.
    this.name = '',
    this.sets = 3,
    this.reps = 8,
    this.startKg = 20,
    this.incrementKg = 2.5,
  });
}

class _EditableDay {
  String title;
  List<_EditableExercise> exercises;
  _EditableDay({this.title = 'Day', List<_EditableExercise>? exercises})
      : exercises = exercises ?? [];
}

class _ProgramEditorScreenState extends State<ProgramEditorScreen> {
  late final TextEditingController _name = TextEditingController(
      text: widget.existing?.name ?? 'My program');
  late final TextEditingController _daysPerWeek = TextEditingController(
      text: widget.existing?.daysPerWeek ?? '3 days/week');
  late final List<_EditableDay> _days = widget.existing == null
      ? [_EditableDay(title: 'Day 1')]
      : [
          for (final d in widget.existing!.days)
            _EditableDay(title: d.title, exercises: [
              for (final e in d.exercises)
                _EditableExercise(
                  name: e.name,
                  sets: e.sets,
                  reps: e.reps,
                  startKg: e.startKg,
                  incrementKg: e.incrementKg,
                ),
            ]),
        ];

  @override
  void dispose() {
    _name.dispose();
    _daysPerWeek.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty ||
        _days.isEmpty ||
        _days.any((d) => d.exercises.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Give the program a name and at least one exercise per day.')));
      return;
    }
    final program = Program(
      id: widget.existing?.id ?? CustomProgramsService.newId(),
      name: name,
      daysPerWeek: _daysPerWeek.text.trim(),
      experience: 'Custom',
      description: 'Your own program.',
      source: 'Created in HealthyFast',
      days: [
        for (final d in _days)
          ProgramDay(title: d.title, exercises: [
            for (final e in d.exercises)
              ProgramExercise(
                name: e.name,
                sets: e.sets,
                reps: e.reps,
                startKg: e.startKg,
                incrementKg: e.incrementKg,
              ),
          ]),
      ],
    );
    await CustomProgramsService.upsert(program);
    if (mounted) Navigator.pop(context, true);
  }

  // A bottom sheet (not AlertDialog) so the exercise picker's dropdown list
  // stays reachable when the keyboard is up — isScrollControlled + the
  // viewInsets padding below make the sheet resize/scroll around the
  // keyboard instead of letting the keyboard cover the results.
  Future<void> _editExercise(_EditableDay day, [_EditableExercise? ex]) async {
    final e = ex ?? _EditableExercise();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ex == null ? 'Add exercise' : 'Edit exercise',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _ExercisePicker(
                    initialValue: e.name,
                    onSelected: (name) => setLocal(() => e.name = name),
                  ),
                  const SizedBox(height: 16),
                  _stepRow(ctx, setLocal, 'Sets', e.sets.toDouble(), 1,
                      (v) => e.sets = v.round().clamp(1, 10)),
                  _stepRow(ctx, setLocal, 'Reps', e.reps.toDouble(), 1,
                      (v) => e.reps = v.round().clamp(1, 30)),
                  _stepRow(ctx, setLocal, 'Start kg', e.startKg, 2.5,
                      (v) => e.startKg = v.clamp(0, 500)),
                  _stepRow(ctx, setLocal, '+kg per success', e.incrementKg,
                      0.5, (v) => e.incrementKg = v.clamp(0, 20)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        // Nothing is prefilled any more, so an unpicked
                        // exercise must not be saveable.
                        child: FilledButton(
                          onPressed: e.name.trim().isEmpty
                              ? null
                              : () => Navigator.pop(ctx, true),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved == true) {
      setState(() {
        if (ex == null) day.exercises.add(e);
      });
    }
  }

  Widget _stepRow(BuildContext ctx, StateSetter setLocal, String label,
      double value, double step, void Function(double) onChanged) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: () => setLocal(() => onChanged(value - step)),
        ),
        SizedBox(
          width: 48,
          child: Text(
            value == value.roundToDouble()
                ? '${value.round()}'
                : value.toStringAsFixed(1),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: () => setLocal(() => onChanged(value + step)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAiDraft
            ? 'Review AI program'
            : widget.existing == null
                ? 'New program'
                : 'Edit program'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Program name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _daysPerWeek,
              decoration: const InputDecoration(
                labelText: 'Days per week (label)',
                hintText: '3 days/week',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            for (var d = 0; d < _days.length; d++) _dayCard(scheme, d),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add day'),
              onPressed: () => setState(
                  () => _days.add(_EditableDay(title: 'Day ${_days.length + 1}'))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCard(ColorScheme scheme, int idx) {
    final day = _days[idx];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: day.title,
                  decoration: const InputDecoration(
                    labelText: 'Day title',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => day.title = v,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: _days.length > 1
                    ? () => setState(() => _days.removeAt(idx))
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final e in day.exercises)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(e.name),
              subtitle: Text('${e.sets}×${e.reps} @ ${e.startKg} kg '
                  '(+${e.incrementKg})'),
              onTap: () => _editExercise(day, e),
              trailing: IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () =>
                    setState(() => day.exercises.remove(e)),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add exercise'),
            onPressed: () => _editExercise(day),
          ),
        ],
      ),
    );
  }
}

/// Searchable exercise picker that defaults to the list from ExerciseGuides.
class _ExercisePicker extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onSelected;

  const _ExercisePicker({required this.initialValue, required this.onSelected});

  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);
  final FocusNode _focusNode = FocusNode();
  List<Exercise> _all = ExerciseGuides.getAll();
  List<Exercise> _filtered = [];

  /// Open on the list when adding (nothing chosen yet) so the user browses
  /// straight away; collapsed when editing, where the name is already set.
  late bool _showList = widget.initialValue.trim().isEmpty;
  // null = all muscle groups. With ~900 exercises in the database, a flat
  // list is unwieldy — this chip filter narrows it down before/alongside
  // the text search.
  String? _muscleFilter;

  List<String> get _muscleGroups {
    final set = <String>{};
    for (final e in _all) {
      set.add(e.muscleGroup);
    }
    final list = set.toList()..sort();
    return list;
  }

  @override
  void initState() {
    super.initState();
    _filtered = _all;
    _ctrl.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      setState(() => _showList = true);
    }
  }

  void _onTextChanged() {
    final query = _ctrl.text.toLowerCase().trim();
    setState(() {
      _filtered = _all
          .where((e) => e.name.toLowerCase().contains(query))
          .where((e) => _muscleFilter == null || e.muscleGroup == _muscleFilter)
          .toList();
      // Only emit a valid selection if it matches an actual exercise name
      final match = _all.any((e) => e.name.toLowerCase() == query);
      if (match) {
        widget.onSelected(_ctrl.text.trim());
      } else if (_ctrl.text.isEmpty) {
        widget.onSelected('');
      }
    });
  }

  void _onMuscleFilterChanged(String? group) {
    setState(() {
      _muscleFilter = group;
      _filtered = _all
          .where((e) => e.name.toLowerCase().contains(_ctrl.text.toLowerCase().trim()))
          .where((e) => _muscleFilter == null || e.muscleGroup == _muscleFilter)
          .toList();
    });
  }

  Future<void> _addNew() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseEditorScreen()),
    );
    if (changed == true) {
      await ExerciseGuides.init();
      setState(() {
        _all = ExerciseGuides.getAll();
        _onTextChanged();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          focusNode: _focusNode,
          onTap: () => setState(() => _showList = true),
          decoration: InputDecoration(
            // hintText, not labelText — a floating label hides the hint
            // while empty, which is exactly when the user needs the cue.
            hintText: 'Search or browse exercises',
            border: const OutlineInputBorder(),
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _ctrl.clear();
                      widget.onSelected('');
                    },
                  )
                : const Icon(Icons.search_rounded),
          ),
        ),
        if (_showList)
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  leading: const Icon(Icons.add_rounded, size: 20),
                  title: const Text('Add new exercise',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  onTap: _addNew,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: SizedBox(
                    height: 32,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: const Text('All'),
                            visualDensity: VisualDensity.compact,
                            selected: _muscleFilter == null,
                            onSelected: (_) => _onMuscleFilterChanged(null),
                          ),
                        ),
                        for (final g in _muscleGroups)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(g),
                              visualDensity: VisualDensity.compact,
                              selected: _muscleFilter == g,
                              onSelected: (_) => _onMuscleFilterChanged(g),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                if (_filtered.isEmpty && _ctrl.text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Not found. Use "+" to add this exercise.',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  ),
                for (final e in _filtered)
                  ListTile(
                    dense: true,
                    title: Text(e.name),
                    subtitle: Text(e.muscleGroup),
                    selected: _ctrl.text.trim().toLowerCase() == e.name.toLowerCase(),
                    onTap: () {
                      _ctrl.text = e.name;
                      widget.onSelected(e.name);
                      setState(() => _showList = false);
                      _focusNode.unfocus();
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
