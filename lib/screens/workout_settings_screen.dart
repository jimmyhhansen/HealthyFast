import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/exercise.dart';
import '../providers/training_provider.dart';
import '../services/custom_exercises_service.dart';
import '../services/custom_programs_service.dart';
import '../services/exercise_guides.dart';
import '../services/training_programs.dart';
import 'program_editor_screen.dart';

class WorkoutSettingsScreen extends StatefulWidget {
  const WorkoutSettingsScreen({super.key});

  @override
  State<WorkoutSettingsScreen> createState() => _WorkoutSettingsScreenState();
}

class _WorkoutSettingsScreenState extends State<WorkoutSettingsScreen> {
  List<Program> _customProgs = [];
  List<Exercise> _customExs = [];
  final bool _busy = false;

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
      await context.read<TrainingProvider>().refreshCustomPrograms();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Settings')),
      body: _busy 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember weights across programs'),
              subtitle: const Text('Keeps your set weights when switching to a different program.'),
              value: context.watch<TrainingProvider>().rememberGlobally,
              onChanged: (val) => context.read<TrainingProvider>().setRememberGlobally(val),
            ),
            const Divider(height: 32),
            _sectionHeader(context, 'CUSTOM PROGRAMS', trailing: IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () async {
                final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ProgramEditorScreen()));
                if (ok == true) _reload();
              },
            )),
            if (_customProgs.isEmpty)
              _emptyState('No custom programs created.')
            else
              for (final p in _customProgs)
                _itemTile(
                  context,
                  icon: Icons.edit_note_rounded,
                  title: p.name,
                  subtitle: '${p.daysPerWeek} · ${p.days.length} day types',
                  onTap: () async {
                    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ProgramEditorScreen(existing: p)));
                    if (ok == true) _reload();
                  },
                  onDelete: () async {
                    await CustomProgramsService.delete(p.id);
                    _reload();
                  },
                ),
            const SizedBox(height: 24),
            _sectionHeader(context, 'CUSTOM EXERCISES', trailing: IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () async {
                final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ExerciseEditorScreen()));
                if (ok == true) _reload();
              },
            )),
            if (_customExs.isEmpty)
              _emptyState('No custom exercises created.')
            else
              for (final e in _customExs)
                _itemTile(
                  context,
                  icon: Icons.fitness_center_rounded,
                  title: e.name,
                  subtitle: e.muscleGroup,
                  onTap: () async {
                    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => ExerciseEditorScreen(existing: e)));
                    if (ok == true) _reload();
                  },
                  onDelete: () async {
                    await CustomExercisesService.delete(e.name);
                    _reload();
                  },
                ),
            const SizedBox(height: 24),
            _sectionHeader(context, 'DEFAULT EXERCISES'),
            for (final e in ExerciseGuides.getAll().where((e) => !e.isCustom))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fitness_center_rounded, size: 20),
                title: Text(e.name),
                subtitle: Text(e.muscleGroup),
              ),
          ],
        ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          )),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _itemTile(BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required VoidCallback onDelete,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onDelete,
      ),
    );
  }

  Widget _emptyState(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
    );
  }
}
