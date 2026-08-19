import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../providers/training_provider.dart';
import '../services/exercise_guides.dart';
import '../services/training_programs.dart';
import 'program_ai_screen.dart';
import 'program_details_screen.dart';
import 'program_editor_screen.dart';

/// Full-screen program library: one tab per experience level, each program
/// as a card. Tapping a card opens details; "adopting" a program from
/// details pops with the chosen program id.
class ProgramLibraryScreen extends StatelessWidget {
  const ProgramLibraryScreen({super.key});

  /// Tabs as (storage key, label) pairs.
  ///
  /// The key is the value stored on `TrainingProgram.experience` and is
  /// persisted in saved programs and cloud backups — it must stay
  /// 'Custom'. Only the label is user-facing, so the two are kept separate.
  ///
  /// The user's own programs come first deliberately: once someone has
  /// built or adopted a program, that is what they open this screen to
  /// reach. Browsing the bundled levels is the rarer, later action.
  static const _tabs = <(String, String)>[
    ('Custom', 'My programs'),
    ('Beginner', 'Beginner'),
    ('Intermediate', 'Intermediate'),
    ('Advanced', 'Advanced'),
  ];

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TrainingProvider>();
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Workout Programs'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final (_, label) in _tabs) Tab(text: label)],
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              for (final (key, _) in _tabs)
                _levelList(context, tp, scheme, key),
            ],
          ),
        ),
      ),
    );
  }

  Widget _levelList(BuildContext context, TrainingProvider tp,
      ColorScheme scheme, String level) {
    final programs =
        tp.availablePrograms.where((p) => p.experience == level).toList();
    if (programs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (level == 'Custom') ...[
                // This is the first thing a new user sees on this screen,
                // so it has to point somewhere rather than just say "empty".
                Icon(Icons.fitness_center_rounded,
                    size: 40, color: scheme.primary),
                const SizedBox(height: 14),
                Text(
                  'Nothing here yet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Programs you build or generate live here. Or start from '
                  'a proven one in the Beginner tab and make it yours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Create program using AI'),
                  onPressed: () => _createWithAi(context, tp),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Build one from scratch'),
                  onPressed: () => _createCustom(context, tp),
                ),
              ] else
                Text(
                  'No programs at this level yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final p in programs) _programCard(context, tp, scheme, p),
        if (level == 'Custom') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('New program'),
              onPressed: () => _createCustom(context, tp),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Create program using AI'),
              onPressed: () => _createWithAi(context, tp),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final isImperial = context.watch<ProfileProvider>().unitSystem == UnitSystem.imperial;
            final inc = isImperial ? '5 lbs' : '2.5 kg';
            return Text(
              'Linear progression on every program: +$inc per successful '
              'exercise, deload −10% after three misses. Guidance, not '
              'medical advice.',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            );
          },
        ),
      ],
    );
  }

  Future<void> _createCustom(
      BuildContext context, TrainingProvider tp) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => const ProgramEditorScreen()),
    );
    if (changed == true) {
      await tp.refreshCustomPrograms();
    }
  }

  Future<void> _createWithAi(BuildContext context, TrainingProvider tp) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ProgramAiScreen()),
    );
    if (changed == true) {
      await tp.refreshCustomPrograms();
    }
  }

  Future<void> _showDetails(BuildContext context, Program program) async {
    final adoptedId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ProgramDetailsScreen(program: program)),
    );
    if (adoptedId != null && context.mounted) {
      Navigator.pop(context, adoptedId);
    }
  }

  Widget _programCard(BuildContext context, TrainingProvider tp,
      ColorScheme scheme, Program p) {
    final selected = tp.programId == p.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.4),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showDetails(context, p),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      p.daysPerWeek,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                p.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 10),
              // Muscle groups summary
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final m in ExerciseGuides.muscleGroupsFor(
                      p.days.expand((d) => d.exercises).map((e) => e.name)))
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        m,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                                color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
