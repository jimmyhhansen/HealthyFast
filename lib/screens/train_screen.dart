import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/workout_record.dart';
import '../providers/fasting_provider.dart';
import '../providers/purchase_provider.dart';
import '../providers/training_provider.dart';
import '../services/health_sync_service.dart';
import '../services/training_programs.dart';
import '../widgets/settings_action.dart';
import '../widgets/app_bar_title.dart';
import 'exercise_library_screen.dart';
import 'paywall_screen.dart';
import 'program_library_screen.dart';
import 'workout_editor_screen.dart';
import 'workout_session_screen.dart';

/// The Train tab: next program workout, weekly progress and recent
/// workouts. Browsing is free; logging a workout (the "+"), programs and
/// guided sessions are premium.
class TrainScreen extends StatelessWidget {
  const TrainScreen({super.key});

  bool _premiumOrPaywall(BuildContext context) {
    if (context.read<PurchaseProvider>().isPremium) return true;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PaywallScreen()),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    final tp = context.watch<TrainingProvider>();
    final scheme = Theme.of(context).colorScheme;

    final program = tp.program;
    final nextDay = tp.nextDay;
    final recent = fp.workouts.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    return Scaffold(
      appBar: AppBar(
        title: const HealthyFastTitle(),
        actions: [settingsAction(context)],
      ),
      floatingActionButton: FloatingActionButton(
        // Explicit tag — see the matching comment in meals_dashboard_screen.dart.
        heroTag: 'fab_train',
        tooltip: 'Log training',
        elevation: 0,
        onPressed: () {
          // Browsing is free; logging a workout (the "+") requires premium.
          if (!_premiumOrPaywall(context)) return;
          _showAddSheet(context, fp, tp);
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
          children: [
            // ── In-progress session (survives navigation) ─────────────────
            if (tp.activeSession != null) ...[
              _inProgressCard(context, tp, scheme),
              const SizedBox(height: 12),
            ],

            // ── 1. Programs Library ───────────────────────────────────────
            _menuCard(
              context,
              scheme,
              icon: Icons.fitness_center_rounded,
              color: scheme.primary,
              title: 'Programs Library',
              subtitle: 'Browse splits and choose your training plan.',
              // This card used to skip straight to _pickProgram, bypassing
              // the paywall entirely — a free user could adopt any bundled
              // program, build a custom one, or (before the fix in
              // program_ai_screen.dart) generate one with AI, all for free.
              // Gate it the same way the "Choose a program" button below is.
              onTap: () {
                if (!_premiumOrPaywall(context)) return;
                _pickProgram(context, tp);
              },
            ),
            const SizedBox(height: 12),

            // ── 2. Exercise Library ───────────────────────────────────────
            _menuCard(
              context,
              scheme,
              icon: Icons.library_books_rounded,
              color: scheme.secondary,
              title: 'Exercise Library',
              subtitle: 'Browse guides and see your personal records.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen()),
              ),
            ),
            const SizedBox(height: 12),

            // ── 3. Next workout / active program card ─────────────────────
            _card(
              scheme,
              child: program == null || nextDay == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionLabel(context, 'ACTIVE PROGRAM'),
                        const SizedBox(height: 8),
                        Text(
                          'No active program. Pick one from the library to '
                          'get guided workouts with progression.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Choose a program'),
                          onPressed: () {
                            if (!_premiumOrPaywall(context)) return;
                            _pickProgram(context, tp);
                          },
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: _sectionLabel(context,
                                    'NEXT · ${program.name.toUpperCase()}')),
                            TextButton(
                              onPressed: () => _showChangeOptions(context, fp, tp),
                              child: const Text('Change'),
                            ),
                          ],
                        ),
                        // Only THIS day's workout is shown — tap to jump
                        // elsewhere in the split.
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _pickDay(context, tp),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      nextDay.title,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(Icons.swap_horiz_rounded,
                                      size: 20, color: scheme.primary),
                                ],
                              ),
                              Text(
                                'Day ${(tp.dayIdx % program.days.length) + 1} '
                                'of ${program.days.length} · tap to change',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final e in nextDay.exercises)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '${e.name} — ${e.sets}×${e.reps} @ '
                              '${_kg(tp.weightFor(e, 0))} kg',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Start workout'),
                            onPressed: () =>
                                _startOrResume(context, tp, nextDay),
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),

            // ── Recent workouts ───────────────────────────────────────────
            _sectionLabel(context, 'RECENT WORKOUTS'),
            const SizedBox(height: 4),
            if (recent.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing logged yet. Start a program workout or tap + '
                  'to quick-log a session.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else ...[
              for (final w in recent.take(5))
                _workoutTile(context, fp, w, onEdit: () => _editWorkout(context, fp, w)),
              if (recent.length > 5)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(
                      'Other workouts are available in Journal',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editWorkout(
      BuildContext context, FastingProvider fp, WorkoutRecord w) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WorkoutEditorScreen(workout: w)),
    );
  }

  static String _kg(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// Resumes the in-progress session if there is one, otherwise starts a
  /// new one from [day]. The session lives in the provider, so backing
  /// out of the screen never resets the timer or the logged sets.
  Future<void> _startOrResume(BuildContext context, TrainingProvider tp,
      ProgramDay day) async {
    if (tp.activeSession == null) {
      if (!_premiumOrPaywall(context)) return;
      await tp.startSession(day);
      if (!context.mounted) return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WorkoutSessionScreen()),
    );
  }

  /// Card shown while a workout is in progress: elapsed time + Resume,
  /// with a discard action.
  Widget _inProgressCard(
      BuildContext context, TrainingProvider tp, ColorScheme scheme) {
    final s = tp.activeSession!;
    final elapsed = DateTime.now().difference(s.startedAt);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60);
    final elapsedText = h > 0 ? '${h}h ${m}m' : '${m}m';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel(context, 'IN PROGRESS'),
          const SizedBox(height: 6),
          Text(
            '${s.dayTitle} · started $elapsedText ago',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Resume'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WorkoutSessionScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Discard workout?'),
                      content: const Text(
                          'The session and its logged sets are discarded.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Keep')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Discard')),
                      ],
                    ),
                  );
                  if (ok == true) await tp.cancelSession();
                },
                child:
                    Text('Discard', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
      );

  Widget _card(ColorScheme scheme, {required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: child,
      );

  Widget _workoutTile(
      BuildContext context, FastingProvider fp, WorkoutRecord w,
      {required VoidCallback onEdit}) {
    final scheme = Theme.of(context).colorScheme;
    final volume = w.totalVolumeKg;
    final mins = w.duration.inMinutes;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: const Icon(Icons.fitness_center_rounded, size: 18),
      ),
      title: Text(w.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${DateFormat('d MMM · HH:mm').format(w.startTime)} · ${mins}m'
        '${volume > 0 ? ' · ${volume.round()} kg volume' : ''}',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18),
        onPressed: onEdit,
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, FastingProvider fp,
      TrainingProvider tp) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tp.nextDay != null)
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: Text('Start ${tp.nextDay!.title}'),
                subtitle: const Text('Next workout in your program'),
                onTap: () => Navigator.pop(ctx, 'start'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Quick log'),
              subtitle: const Text('Title and duration — no details'),
              onTap: () => Navigator.pop(ctx, 'quick'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == 'start') {
      final day = tp.nextDay;
      if (day == null) return;
      await _startOrResume(context, tp, day);
    } else {
      await showQuickLogWorkout(context, fp);
    }
  }

  Future<void> _pickProgram(BuildContext context, TrainingProvider tp) async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ProgramLibraryScreen()),
    );
    if (selected != null) {
      await tp.selectProgram(selected);
      // Splits with several day types: let the user pick where to start.
      if (context.mounted) await _pickDay(context, tp, starting: true);
    }
  }

  Future<void> _showChangeOptions(BuildContext context, FastingProvider fp, TrainingProvider tp) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Change day'),
              subtitle: const Text('Jump to another day in the current split'),
              onTap: () => Navigator.pop(ctx, 'day'),
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center_rounded),
              title: const Text('Change program'),
              subtitle: const Text('Switch to a completely different plan'),
              onTap: () => Navigator.pop(ctx, 'program'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == 'day') {
      await _pickDay(context, tp);
    } else {
      await _pickProgram(context, tp);
    }
  }

  Widget _menuCard(BuildContext context, ColorScheme scheme,
      {required IconData icon,
      required Color color,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return _card(
      scheme,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  /// Day picker for the current program's rotation — used both when
  /// starting a program ("which day am I on?") and to jump later.
  Future<void> _pickDay(BuildContext context, TrainingProvider tp,
      {bool starting = false}) async {
    final program = tp.program;
    if (program == null || program.days.length <= 1) return;

    final idx = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              starting
                  ? 'Where do you want to start?'
                  : 'Jump to a day in the split',
              style: Theme.of(ctx)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              '${program.name} rotates through these days in order:',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < program.days.length; i++)
              ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('${i + 1}',
                      style: const TextStyle(fontSize: 13)),
                ),
                title: Text(program.days[i].title),
                subtitle: Text(
                  program.days[i].exercises.map((e) => e.name).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected:
                    i == tp.dayIdx % program.days.length,
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
      ),
    );
    if (idx != null) await tp.setDayIdx(idx);
  }
}

/// Quick log of a workout without set details: title, Health Connect
/// activity type, duration and intensity. Shared with the Journal's +
/// menu — [day] presets the date (defaults to today).
Future<void> showQuickLogWorkout(BuildContext context, FastingProvider fp,
    {DateTime? day}) async {
  final titleCtrl = TextEditingController(text: 'Strength workout');
  final minsCtrl = TextEditingController(text: '45');
  var type = 'STRENGTH_TRAINING';
  var intensity = 'moderate';

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Quick log workout'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              // Types mirror Health Connect's activity types, so the
              // export lands correctly in other health apps.
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final e in HealthSyncService.workoutTypes.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) =>
                    setLocal(() => type = v ?? 'STRENGTH_TRAINING'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: minsCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration',
                  suffixText: 'min',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'light', label: Text('Light')),
                  ButtonSegment(value: 'moderate', label: Text('Mod.')),
                  ButtonSegment(value: 'hard', label: Text('Hard')),
                ],
                selected: {intensity},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                onSelectionChanged: (s) =>
                    setLocal(() => intensity = s.first),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    ),
  );

  final title = titleCtrl.text.trim();
  final mins = int.tryParse(minsCtrl.text.trim()) ?? 45;
  titleCtrl.dispose();
  minsCtrl.dispose();
  if (ok != true || title.isEmpty) return;

  final now = DateTime.now();
  var end = day == null
      ? now
      : DateTime(day.year, day.month, day.day, now.hour, now.minute);
  if (end.isAfter(now)) end = now;
  await fp.addWorkout(WorkoutRecord(
    startTime: end.subtract(Duration(minutes: mins.clamp(1, 600))),
    endTime: end,
    title: title,
    activityType: type,
    intensity: intensity,
  ));
}
