import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exercise.dart';
import '../providers/fasting_provider.dart';
import '../providers/profile_provider.dart';
import '../services/exercise_guides.dart';
import 'program_editor_screen.dart' show ExerciseEditorScreen;
import 'workout_session_screen.dart' show showExerciseGuide;

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final List<Exercise> _all = ExerciseGuides.getAll();
  String _query = '';
  // null = all muscle groups. With ~900 exercises now in the library, a
  // flat list is unwieldy — these chips narrow it down before searching.
  String? _muscleFilter;

  List<String> get _muscleGroups {
    final set = <String>{};
    for (final e in _all) {
      set.add(e.muscleGroup);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _addExercise({String? initialName}) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseEditorScreen(initialName: initialName),
      ),
    );
    if (changed == true) {
      await ExerciseGuides.init();
      setState(() {
        _all.clear();
        _all.addAll(ExerciseGuides.getAll());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _all
        .where((e) => e.name.toLowerCase().contains(_query.toLowerCase()))
        .where((e) => _muscleFilter == null || e.muscleGroup == _muscleFilter)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Library'),
      ),
      // Goes straight to the add-exercise form — no detour through Workout
      // Settings.
      floatingActionButton: FloatingActionButton.extended(
        // Explicit tag — see the matching comment in program_editor_screen.dart.
        heroTag: 'fab_exercise_library',
        onPressed: () => _addExercise(initialName: _query.trim().isEmpty ? null : _query.trim()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add New'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search exercises...',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _muscleFilter == null,
                    onSelected: (_) => setState(() => _muscleFilter = null),
                  ),
                ),
                for (final g in _muscleGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(g),
                      selected: _muscleFilter == g,
                      onSelected: (_) => setState(() => _muscleFilter = g),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _query.trim().isEmpty
                                ? 'No exercises in this group.'
                                : 'No match for "${_query.trim()}".',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                          if (_query.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () =>
                                  _addExercise(initialName: _query.trim()),
                              icon: const Icon(Icons.add_rounded),
                              label: Text('Add "${_query.trim()}"'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final e = filtered[index];
                      return _ExerciseListTile(exercise: e);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseListTile extends StatelessWidget {
  final Exercise exercise;

  const _ExerciseListTile({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fp = context.watch<FastingProvider>();
    final pp = context.watch<ProfileProvider>();
    final isImperial = pp.unitSystem == UnitSystem.imperial;
    final unit = isImperial ? 'lbs' : 'kg';

    final history = fp.previousSets(exercise.name);
    
    // Calculate PR from history
    double? pr;
    if (history.isNotEmpty) {
      pr = history.map((s) => s.$1).reduce((a, b) => a > b ? a : b);
    }

    final displayPr = pr == null ? null : (isImperial ? pr / 0.45359237 : pr);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: exercise.customImagePath != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(exercise.customImagePath!), fit: BoxFit.cover),
                )
              : Icon(Icons.fitness_center_rounded, color: scheme.primary, size: 24),
        ),
        title: Text(exercise.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exercise.muscleGroup),
            if (displayPr != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'PR: ${displayPr == displayPr.roundToDouble() ? displayPr.round() : displayPr.toStringAsFixed(1)} $unit',
                  style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showExerciseGuide(context, exercise.name),
      ),
    );
  }
}
