import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fast_record.dart';
import '../models/meal_record.dart';
import '../providers/fasting_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/purchase_provider.dart';
import '../providers/training_provider.dart';
import '../services/meal_insights_service.dart';
import '../services/micro_insights_service.dart';
import '../services/nutrition_data_service.dart';
import '../models/weight_record.dart';
import '../models/workout_record.dart';
import '../widgets/meal_editor.dart';
import '../widgets/settings_action.dart';
import '../widgets/app_bar_title.dart';
import 'meals_screen.dart';
import 'train_screen.dart' show showQuickLogWorkout;
import 'workout_editor_screen.dart';
import 'paywall_screen.dart';
import 'general_settings_screen.dart';

/// Journal: monthly calendar plus the day's fasts and meals, all editable.
/// A second tab shows fasting statistics filtered by period.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth =
          DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  Map<DateTime, double> _hoursPerDay(List<FastRecord> records) {
    final map = <DateTime, double>{};
    for (final r in records) {
      var cursor = r.startTime;
      while (cursor.isBefore(r.endTime)) {
        final day = DateTime(cursor.year, cursor.month, cursor.day);
        final nextMidnight = day.add(const Duration(days: 1));
        final segmentEnd =
            r.endTime.isBefore(nextMidnight) ? r.endTime : nextMidnight;
        map[day] = (map[day] ?? 0) +
            segmentEnd.difference(cursor).inMinutes / 60.0;
        cursor = segmentEnd;
      }
    }
    return map;
  }

  List<FastRecord> _fastsOnDay(List<FastRecord> records, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return records
        .where((r) =>
            r.startTime.isBefore(dayEnd) && r.endTime.isAfter(dayStart))
        .toList();
  }

  List<MealRecord> _mealsOnDay(List<MealRecord> meals, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return meals
        .where((m) => m.time.isAfter(dayStart) && m.time.isBefore(dayEnd))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    final records = fp.history;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const HealthyFastTitle(),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Sync from Health Connect',
              onPressed: () => _syncFromHealth(context, fp),
            ),
            settingsAction(context),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Journal'),
              Tab(text: 'Insights'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Log on this day',
          elevation: 0,
          onPressed: () => _logOnSelectedDay(context, fp),
          child: const Icon(Icons.add_rounded),
        ),
        body: SafeArea(
          child: TabBarView(
            children: [
              _buildJournalTab(context, fp, records),
              _StatsTab(records: records),
            ],
          ),
        ),
      ),
    );
  }

  /// Insights' refresh button: lets the user pick how far back to pull
  /// before syncing every Health Connect data type we read (weights,
  /// workouts, meals, steps, sleep) — not just steps/sleep like before.
  Future<void> _syncFromHealth(BuildContext context, FastingProvider fp) async {
    final days = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Sync from Health Connect',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Pulls weights, workouts, meals, steps and sleep logged in '
                'other apps. Choose how far back to look.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            for (final (label, d) in const [
              ('Last 7 days', 7),
              ('Last 30 days', 30),
              ('Last 90 days', 90),
              ('Last year', 366),
            ])
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, d),
              ),
          ],
        ),
      ),
    );
    if (days == null || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Syncing…'), duration: Duration(seconds: 1)),
    );
    final result = await fp.refreshAllFromHealth(sinceDays: days);
    if (!context.mounted) return;

    final parts = <String>[];
    if (result.weights > 0) parts.add('${result.weights} weight');
    if (result.workouts > 0) parts.add('${result.workouts} workout');
    if (result.meals > 0) parts.add('${result.meals} meal');
    final summary =
        parts.isEmpty ? 'Steps and sleep updated — no new entries.' : '${parts.join(', ')} added. Steps and sleep updated.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );
  }

  /// The Journal's +: log a meal or a fast on the selected day.
  Future<void> _logOnSelectedDay(
      BuildContext context, FastingProvider fp) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                DateFormat('EEEE, d MMMM').format(_selectedDay),
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restaurant_rounded),
              title: const Text('Log a meal'),
              subtitle: const Text('On the selected day'),
              onTap: () => Navigator.pop(ctx, 'meal'),
            ),
            ListTile(
              leading: const Icon(Icons.hourglass_bottom_rounded),
              title: const Text('Log a fast'),
              subtitle: const Text('Add a completed fast in retrospect'),
              onTap: () => Navigator.pop(ctx, 'fast'),
            ),
            ListTile(
              leading: const Icon(Icons.monitor_weight_outlined),
              title: const Text('Log weight'),
              subtitle: const Text('Carried forward until you log again'),
              onTap: () => Navigator.pop(ctx, 'weight'),
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center_rounded),
              title: const Text('Log a workout'),
              subtitle: const Text('Quick log on the selected day'),
              onTap: () => Navigator.pop(ctx, 'workout'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == 'meal') {
      // Meal logging is a premium feature, same as the Meals tab.
      if (!context.read<PurchaseProvider>().isPremium) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => MealsScreen(initialDate: _selectedDay)),
      );
    } else if (choice == 'fast') {
      await _addFast(context, fp);
    } else if (choice == 'weight') {
      await _logWeight(context, fp);
    } else {
      // Workout logging is a premium feature, same as the Workout tab.
      if (!context.read<PurchaseProvider>().isPremium) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PaywallScreen()),
        );
        return;
      }
      await showQuickLogWorkout(context, fp, day: _selectedDay);
    }
  }

  /// Logs a weight on the selected day. Also updates the energy profile's
  /// weight (so daily-burn estimates follow) when this is the newest entry.
  Future<void> _logWeight(BuildContext context, FastingProvider fp) async {
    final day = _selectedDay;
    final now = DateTime.now();
    var time = DateTime(day.year, day.month, day.day, now.hour, now.minute);
    if (time.isAfter(now)) time = now;

    final pp = context.read<ProfileProvider>();
    final isMetric = pp.unitSystem == UnitSystem.metric;

    double? prefill = fp.weightOnDay(day) ?? pp.weightKg;
    if (prefill != null && !isMetric) {
      prefill = prefill / 0.45359237;
    }

    final ctrl = TextEditingController(
        text: prefill == null ? '' : prefill.toStringAsFixed(1));

    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Weight · ${DateFormat('d MMM').format(day)}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Weight',
            suffixText: isMetric ? 'kg' : 'lbs',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, double.tryParse(ctrl.text.trim().replaceAll(',', '.'))),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (val == null || val <= 0) return;
    final kg = isMetric ? val : val * 0.45359237;
    if (kg > 500) return;
    if (!context.mounted) return;

    await fp.addWeight(kg, time);

    // Newest weight → keep the energy profile (and daily burn) in step.
    final latest = fp.latestWeight;
    if (latest != null &&
        (latest.time.difference(time)).abs() < const Duration(minutes: 1) &&
        context.mounted) {
      await context.read<ProfileProvider>().setWeightKg(kg);
    }
  }

  /// Adds a completed fast in retrospect. Defaults to an overnight 16h
  /// fast ending midday on the selected day.
  Future<void> _addFast(BuildContext context, FastingProvider fp) async {
    final day = _selectedDay;
    var end = DateTime(day.year, day.month, day.day, 12);
    final now = DateTime.now();
    if (end.isAfter(now)) end = now;
    var start = end.subtract(const Duration(hours: 16));

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> pick(bool isStart) async {
            final base = isStart ? start : end;
            final date = await showDatePicker(
              context: ctx,
              initialDate: base,
              firstDate: DateTime(2020),
              lastDate: now,
            );
            if (date == null || !ctx.mounted) return;
            final time = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay.fromDateTime(base),
            );
            if (time == null) return;
            final dt = DateTime(
                date.year, date.month, date.day, time.hour, time.minute);
            setLocal(() {
              if (isStart) {
                start = dt;
              } else {
                end = dt;
              }
            });
          }

          final fmt = DateFormat('d MMM, HH:mm');
          final valid = end.isAfter(start) && !end.isAfter(now);
          final hours = end.difference(start).inMinutes / 60.0;
          return AlertDialog(
            title: const Text('Log a fast'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start'),
                  subtitle: Text(fmt.format(start)),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: () => pick(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End'),
                  subtitle: Text(fmt.format(end)),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: () => pick(false),
                ),
                if (valid)
                  Text('${hours.toStringAsFixed(1)} hours',
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          fontSize: 12))
                else
                  Text('End must be after start (and not in the future)',
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final hours = end.difference(start).inHours;
      await fp.addFast(FastRecord(
        startTime: start,
        endTime: end,
        protocol: '${hours}h',
      ));
    }
  }

  Widget _buildJournalTab(
      BuildContext context, FastingProvider fp, List<FastRecord> records) {
    // Include the ONGOING fast (not yet in history) so a multi-day fast
    // shows its hours on every day it spans, including today.
    final effectiveRecords = [
      ...records,
      if (fp.isFasting && fp.startTime != null)
        FastRecord(
          startTime: fp.startTime!,
          endTime: DateTime.now(),
          protocol: fp.protocol.label,
        ),
    ];
    final hoursPerDay = _hoursPerDay(effectiveRecords);
    final dayFasts = _fastsOnDay(effectiveRecords, _selectedDay);
    final dayMeals = _mealsOnDay(fp.meals, _selectedDay);
    final dayKcal =
        dayMeals.fold<double>(0, (sum, m) => sum + m.calories);
    final dayFastHours = hoursPerDay[_selectedDay] ?? 0;

    return ListView(
      children: [
        _MonthHeader(
          month: _visibleMonth,
          onPrev: () => _changeMonth(-1),
          onNext: () => _changeMonth(1),
        ),
        _MonthGrid(
          month: _visibleMonth,
          hoursPerDay: hoursPerDay,
          selectedDay: _selectedDay,
          onDaySelected: (d) => setState(() => _selectedDay = d),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            DateFormat('EEEE, d MMMM').format(_selectedDay),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        _DaySummaryBar(
          workoutMinutes: fp
              .workoutsOnDay(_selectedDay)
              .fold<int>(0, (s, w) => s + w.duration.inMinutes),
          fastHours: dayFastHours,
          weightKg: fp.weightOnDay(_selectedDay),
          steps: fp.stepsOnDay(_selectedDay),
          sleepMinutes: fp.sleepMinutesOnDay(_selectedDay),
        ),
        _EnergyBalanceCard(
          kcal: dayKcal,
          workoutBurn: fp.workoutBurnOnDay(_selectedDay),
        ),
        _sectionLabel(context, 'Fasts'),
        if (dayFasts.isEmpty)
          _emptyLine(context, 'No fasts on this day.')
        else
          ...dayFasts.map((r) => _FastTile(
                record: r,
                day: _selectedDay,
                // The ongoing (virtual) fast is edited from the Fast tab,
                // not here — it isn't a saved record yet.
                onEdit: r.isInBox ? () => _editFast(context, fp, r) : null,
              )),
        _sectionLabel(context, 'Meals'),
        if (dayMeals.isEmpty)
          _emptyLine(context, 'No meals logged.')
        else
          ...dayMeals.map((m) => _MealTile(
                meal: m,
                onEdit: () => _editMeal(context, fp, m),
              )),
        _sectionLabel(context, 'Workouts'),
        if (fp.workoutsOnDay(_selectedDay).isEmpty)
          _emptyLine(context, 'No workouts logged.')
        else
          ...fp.workoutsOnDay(_selectedDay).map(
                (w) => _WorkoutTile(
                  workout: w,
                  fp: fp,
                  onEdit: () => _editWorkout(context, fp, w),
                ),
              ),
        _sectionLabel(context, 'Weight'),
        if (fp.weightsOnDay(_selectedDay).isEmpty)
          _emptyLine(context, 'No weight logged.')
        else
          ...fp.weightsOnDay(_selectedDay).map(
                (w) => _WeightTile(
                  weight: w,
                  fp: fp,
                  onEdit: () => _editWeight(context, fp, w),
                ),
              ),
        // Room for the FAB: the + must sit below the content when
        // scrolled to the bottom, never covering it.
        const SizedBox(height: 96),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
        ),
      );

  Widget _emptyLine(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Future<void> _editFast(
      BuildContext context, FastingProvider fp, FastRecord r) async {
    var start = r.startTime;
    var end = r.endTime;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> pick(bool isStart) async {
            final base = isStart ? start : end;
            final date = await showDatePicker(
              context: ctx,
              initialDate: base,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (date == null) return;
            if (!ctx.mounted) return;
            final time = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay.fromDateTime(base),
            );
            if (time == null) return;
            final dt = DateTime(
                date.year, date.month, date.day, time.hour, time.minute);
            setLocal(() {
              if (isStart) {
                start = dt;
              } else {
                end = dt;
              }
            });
          }

          final fmt = DateFormat('d MMM, HH:mm');
          final valid = end.isAfter(start);
          return AlertDialog(
            title: const Text('Edit fast'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start'),
                  subtitle: Text(fmt.format(start)),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: () => pick(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End'),
                  subtitle: Text(fmt.format(end)),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: () => pick(false),
                ),
                if (!valid)
                  Text('End must be after start',
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'delete'),
                child: Text('Delete',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, 'save') : null,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (result == 'save') {
      await fp.updateFast(r, startTime: start, endTime: end);
    } else if (result == 'delete') {
      await fp.deleteFast(r);
    }
  }

  Future<void> _editMeal(
      BuildContext context, FastingProvider fp, MealRecord m) async {
    await showMealEditor(context, fp, m);
  }

  Future<void> _editWorkout(
      BuildContext context, FastingProvider fp, WorkoutRecord w) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WorkoutEditorScreen(workout: w)),
    );
  }

  Future<void> _editWeight(
      BuildContext context, FastingProvider fp, WeightRecord w) async {
    final ctrl = TextEditingController(text: w.kg.toStringAsFixed(1));

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Weight · ${DateFormat('d MMM').format(w.time)}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Weight',
            suffixText: 'kg',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Text('Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final kg = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
    ctrl.dispose();

    if (result == 'save' && kg != null && kg > 0 && kg < 500) {
      await fp.updateWeight(w, kg: kg, time: w.time);
      // Newest weight → keep the energy profile (and daily burn) in step.
      final latest = fp.latestWeight;
      if (latest != null && latest == w && context.mounted) {
        await context.read<ProfileProvider>().setWeightKg(kg);
      }
    } else if (result == 'delete') {
      await fp.deleteWeight(w);
    }
  }
}

/// Intake vs estimated daily burn for the selected day — same design as
/// the Meals dashboard's Today card. Always visible; shows a setup hint
/// while the energy profile is incomplete.
class _EnergyBalanceCard extends StatelessWidget {
  final double kcal;

  /// Low-end estimate of calories burned by the day's workouts —
  /// added on top of the daily burn.
  final int workoutBurn;

  const _EnergyBalanceCard({required this.kcal, this.workoutBurn = 0});

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final scheme = Theme.of(context).colorScheme;
    // Workout burn only counts in 'per workout' mode — in weekly mode
    // the activity level already covers training (no double counting).
    final extraBurn = pp.burnMode == 'workout' ? workoutBurn : 0;
    final tdee =
        pp.effectiveTdee == null ? null : pp.effectiveTdee! + extraBurn;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ENERGY BALANCE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: ui.TextBaseline.alphabetic,
              children: [
                Text(
                  '${kcal.round()}',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    tdee == null
                        ? 'kcal logged'
                        : '/ ${tdee.round()} kcal daily burn'
                            '${extraBurn > 0 ? ' (incl. $extraBurn workout)' : ''}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (tdee != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (kcal / tdee).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    kcal > tdee ? scheme.error : const Color(0xFF1D9E75),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                kcal > tdee
                    ? '${(kcal - tdee).round()} kcal over estimated burn'
                    : '${(tdee - kcal).round()} kcal left of estimated burn',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: kcal > tdee
                          ? scheme.error
                          : const Color(0xFF0F6E56),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ] else
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GeneralSettingsScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Set up your energy profile to compare intake '
                          'with your daily burn.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A workout in the day view: title · duration · volume, with delete.
class _WorkoutTile extends StatelessWidget {
  final WorkoutRecord workout;
  final FastingProvider fp;
  final VoidCallback onEdit;

  const _WorkoutTile({
    required this.workout,
    required this.fp,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final volume = workout.totalVolumeKg;
    final names = workout.exerciseNames;
    // Which program (and day) this workout belonged to, when any.
    final progName = context
        .read<TrainingProvider>()
        .programNameById(workout.programId);
    final dayNo =
        workout.programDayIdx == null ? null : workout.programDayIdx! + 1;
    final programLine = progName == null
        ? ''
        : '\n$progName${dayNo != null ? ' · day $dayNo' : ''}';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: const Icon(Icons.fitness_center_rounded, size: 18),
      ),
      title: Text(workout.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${DateFormat('HH:mm').format(workout.startTime)} · '
        '${workout.duration.inMinutes}m'
        '${volume > 0 ? ' · ${volume.round()} kg' : ''}'
        '${workout.intensity != null ? ' · ${workout.intensity}' : ''}'
        '$programLine'
        '${programLine.isEmpty && names.isNotEmpty ? '\n${names.join(' · ')}' : ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      // Tap shows per-set details (weight × reps for every set).
      onTap: () => _showDetails(context),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18),
        onPressed: onEdit,
      ),
    );
  }
}

/// A weight entry in the day view — logged manually or synced from
/// Health Connect. Editable/deletable like the other logs.
class _WeightTile extends StatelessWidget {
  final WeightRecord weight;
  final FastingProvider fp;
  final VoidCallback onEdit;

  const _WeightTile({
    required this.weight,
    required this.fp,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final isMetric = pp.unitSystem == UnitSystem.metric;
    final displayWeight = isMetric ? weight.kg : weight.kg / 0.45359237;
    final unit = isMetric ? 'kg' : 'lbs';

    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.tertiaryContainer,
        child: const Icon(Icons.monitor_weight_outlined, size: 18),
      ),
      title: Text('${displayWeight.toStringAsFixed(1)} $unit'),
      subtitle: Text(DateFormat('HH:mm').format(weight.time)),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined, size: 18),
        onPressed: onEdit,
      ),
    );
  }
}

extension on _WorkoutTile {
  void _showDetails(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progName = context
        .read<TrainingProvider>()
        .programNameById(workout.programId);
    List<dynamic> exercises = const [];
    try {
      exercises = jsonDecode(workout.exercisesJson ?? '[]') as List;
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(workout.title,
                style: Theme.of(ctx)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              '${DateFormat('EEEE d MMM · HH:mm').format(workout.startTime)}'
              ' · ${workout.duration.inMinutes}m'
              '${workout.intensity != null ? ' · ${workout.intensity}' : ''}',
              style: Theme.of(ctx)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (progName != null)
              Text(
                '$progName'
                '${workout.programDayIdx != null ? ' · day ${workout.programDayIdx! + 1}' : ''}',
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 12),
            if (exercises.isEmpty)
              Text('No set details for this workout.',
                  style: TextStyle(color: scheme.onSurfaceVariant))
            else
              for (final e in exercises.whereType<Map>()) ...[
                Text(e['n'] as String? ?? 'Exercise',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 2),
                  child: Text(
                    [
                      for (final s in ((e['sets'] as List?) ?? const [])
                          .whereType<Map>())
                        '${_fmtKgJournal((s['kg'] as num?)?.toDouble() ?? 0, isImperial: context.read<ProfileProvider>().unitSystem == UnitSystem.imperial)}'
                            '×${(s['reps'] as num?)?.toInt() ?? 0}',
                    ].join('   '),
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

}

String _fmtKgJournal(double v, {bool isImperial = false}) {
  final value = isImperial ? v / 0.45359237 : v;
  return value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);
}

/// Compact summary of the selected day, right under the calendar:
/// Workout · Fasted · Weight — three uniform columns, title on top and
/// the number below. (Intake lives in the Energy balance card.)
class _DaySummaryBar extends StatelessWidget {
  final int workoutMinutes;
  final double fastHours;

  /// Carry-forward weight for the day; null when never logged.
  final double? weightKg;

  /// Steps and sleep mirrored from Health Connect; null when unknown.
  final int? steps;
  final int? sleepMinutes;

  const _DaySummaryBar({
    required this.workoutMinutes,
    required this.fastHours,
    this.weightKg,
    this.steps,
    this.sleepMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final isImperial = pp.unitSystem == UnitSystem.imperial;
    final displayWeight = weightKg == null ? null : (isImperial ? weightKg! / 0.45359237 : weightKg!);
    final unit = isImperial ? 'lbs' : 'kg';

    final scheme = Theme.of(context).colorScheme;

    Widget divider() => Container(
          width: 1,
          height: 36,
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _summaryItem(
                  context,
                  label: 'Workout',
                  value: workoutMinutes == 0 ? '—' : '${workoutMinutes}m',
                ),
              ),
              divider(),
              Expanded(
                child: _summaryItem(
                  context,
                  label: 'Fasted',
                  value: fastHours == 0
                      ? '—'
                      : '${fastHours.toStringAsFixed(1)}h',
                ),
              ),
              divider(),
              Expanded(
                child: _summaryItem(
                  context,
                  label: 'Weight',
                  value: displayWeight == null
                      ? '—'
                      : '${displayWeight.toStringAsFixed(1)} $unit',
                ),
              ),
            ],
          ),
          // Second row: Health Connect mirrors — same layout as row one,
          // separated by a calm horizontal line.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Container(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _summaryItem(
                  context,
                  label: 'Steps',
                  value: steps == null ? '—' : '$steps',
                ),
              ),
              divider(),
              Expanded(
                child: _summaryItem(
                  context,
                  label: 'Sleep',
                  value: sleepMinutes == null
                      ? '—'
                      : '${sleepMinutes! ~/ 60}h ${sleepMinutes! % 60}m',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(BuildContext context,
      {required String label, required String value}) {
    final scheme = Theme.of(context).colorScheme;
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
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev, onNext;

  const _MonthHeader(
      {required this.month, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
              icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Text(
            DateFormat('MMMM yyyy').format(month),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          IconButton(
              icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Map<DateTime, double> hoursPerDay;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  const _MonthGrid({
    required this.month,
    required this.hoursPerDay,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leadingEmpty = firstDay.weekday - 1;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    final cells = <Widget>[
      for (final w in weekdays)
        Center(
          child: Text(w,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      for (var i = 0; i < leadingEmpty; i++) const SizedBox(),
      for (var d = 1; d <= daysInMonth; d++)
        _DayCell(
          day: DateTime(month.year, month.month, d),
          hoursFasted:
              hoursPerDay[DateTime(month.year, month.month, d)] ?? 0,
          isToday: DateTime(month.year, month.month, d) == today,
          isSelected: DateTime(month.year, month.month, d) == selectedDay,
          onTap: onDaySelected,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: cells,
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final double hoursFasted;
  final bool isToday, isSelected;
  final ValueChanged<DateTime> onTap;

  const _DayCell({
    required this.day,
    required this.hoursFasted,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFast = hoursFasted > 0;
    final intensity = (hoursFasted / 24).clamp(0.0, 1.0);

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => onTap(day),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasFast
                ? scheme.primary.withValues(alpha: 0.15 + 0.55 * intensity)
                : null,
            border: isSelected
                ? Border.all(color: scheme.primary, width: 2)
                : isToday
                    ? Border.all(color: scheme.outline)
                    : null,
          ),
          alignment: Alignment.center,
          child: Text(
            '${day.day}',
            style: TextStyle(
              fontWeight:
                  isToday || isSelected ? FontWeight.bold : FontWeight.normal,
              color: hasFast && intensity > 0.5
                  ? scheme.onPrimary
                  : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Which window the Stats tab aggregates over.
enum _StatsPeriod { week, month, quarter, year }

/// Insight category, selected in the bar above the period filter.
enum _InsightCat { fast, nutrition, weight, training, steps, sleep }

/// Fasting statistics for a selectable period (month / quarter / year).
class _StatsTab extends StatefulWidget {
  final List<FastRecord> records;
  const _StatsTab({required this.records});

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  _InsightCat _cat = _InsightCat.fast;
  _StatsPeriod _period = _StatsPeriod.month;
  bool _expanded = false;

  /// 0 = current period, -1 = previous, etc. Never positive (no future).
  int _offset = 0;

  /// null = checking, false = not downloaded, true = ready.
  bool? _nutriReady;
  bool _nutriBusy = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    NutritionDataService.isReady().then((v) {
      if (mounted) setState(() => _nutriReady = v);
    });
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCat = prefs.getString('last_insight_cat');
      if (lastCat != null) {
        final val = _InsightCat.values.firstWhere((e) => e.name == lastCat, orElse: () => _InsightCat.fast);
        setState(() => _cat = val);
      }
    } catch (_) {}
  }

  Future<void> _saveCat(_InsightCat cat) async {
    setState(() => _cat = cat);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_insight_cat', cat.name);
    } catch (_) {}
  }

  Future<void> _downloadNutritionTable() async {
    setState(() => _nutriBusy = true);
    final ok = await NutritionDataService.download();
    if (!mounted) return;
    setState(() {
      _nutriBusy = false;
      _nutriReady = ok;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Could not download the food table. Try again later.')));
    }
  }

  /// Returns (start, endExclusive, label) for the selected period + offset.
  (DateTime, DateTime, String) _range() {
    final now = DateTime.now();
    switch (_period) {
      case _StatsPeriod.week:
        // Start of current week (Monday)
        final today = DateTime(now.year, now.month, now.day);
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final start = monday.add(Duration(days: _offset * 7));
        final end = start.add(const Duration(days: 7));
        return (
          start,
          end,
          _offset == 0 ? 'This week' : 'Week of ${DateFormat('d MMM').format(start)}',
        );
      case _StatsPeriod.month:
        final m = DateTime(now.year, now.month + _offset);
        return (
          m,
          DateTime(m.year, m.month + 1),
          DateFormat('MMMM yyyy').format(m),
        );
      case _StatsPeriod.quarter:
        final totalQ = now.year * 4 + (now.month - 1) ~/ 3 + _offset;
        final y = totalQ ~/ 4;
        final q = totalQ % 4;
        return (
          DateTime(y, q * 3 + 1),
          DateTime(y, q * 3 + 4),
          'Q${q + 1} $y',
        );
      case _StatsPeriod.year:
        final y = now.year + _offset;
        return (DateTime(y), DateTime(y + 1), '$y');
    }
  }

  Map<DateTime, double> _hoursPerDay(List<FastRecord> records, DateTime start, DateTime end) {
    final map = <DateTime, double>{};
    for (final r in records) {
      var cursor = r.startTime.isBefore(start) ? start : r.startTime;
      final stop = r.endTime.isAfter(end) ? end : r.endTime;
      while (cursor.isBefore(stop)) {
        final day = DateTime(cursor.year, cursor.month, cursor.day);
        final nextMidnight = day.add(const Duration(days: 1));
        final segmentEnd =
            stop.isBefore(nextMidnight) ? stop : nextMidnight;
        map[day] =
            (map[day] ?? 0) + segmentEnd.difference(cursor).inMinutes / 60.0;
        cursor = segmentEnd;
      }
    }
    return map;
  }

  IconData _getCatIcon(_InsightCat cat) {
    switch (cat) {
      case _InsightCat.fast: return Icons.hourglass_bottom_rounded;
      case _InsightCat.nutrition: return Icons.restaurant_rounded;
      case _InsightCat.weight: return Icons.monitor_weight_outlined;
      case _InsightCat.training: return Icons.fitness_center_rounded;
      case _InsightCat.steps: return Icons.directions_walk_rounded;
      case _InsightCat.sleep: return Icons.bedtime_rounded;
    }
  }

  Widget _categorySelector(BuildContext context, ColorScheme scheme) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: _expanded
                  ? const BorderRadius.vertical(top: Radius.circular(12))
                  : BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF1D9E75),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(_getCatIcon(_cat), color: const Color(0xFF1D9E75), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'View insights for...',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      Text(
                        _getCatLabel(_cat),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border.all(
                color: const Color(0xFF1D9E75),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                for (final c in _InsightCat.values)
                  _categoryItem(context, scheme, c),
              ],
            ),
          ),
      ],
    );
  }

  Widget _categoryItem(BuildContext context, ColorScheme scheme, _InsightCat c) {
    final selected = _cat == c;
    return InkWell(
      onTap: () {
        _saveCat(c);
        setState(() => _expanded = false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.3) : null,
          border: c == _InsightCat.sleep
              ? null
              : Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
        ),
        child: Row(
          children: [
            Icon(
              _getCatIcon(c),
              size: 20,
              color: selected ? const Color(0xFF1D9E75) : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Text(
              _getCatLabel(c),
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? const Color(0xFF1D9E75) : scheme.onSurface,
              ),
            ),
            if (selected) ...[
              const Spacer(),
              const Icon(Icons.check_rounded, size: 18, color: Color(0xFF1D9E75)),
            ],
          ],
        ),
      ),
    );
  }

  String _getCatLabel(_InsightCat cat) {
    switch (cat) {
      case _InsightCat.fast: return 'Fasting';
      case _InsightCat.nutrition: return 'Nutrition';
      case _InsightCat.weight: return 'Weight';
      case _InsightCat.training: return 'Workouts';
      case _InsightCat.steps: return 'Steps';
      case _InsightCat.sleep: return 'Sleep';
    }
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final scheme = Theme.of(context).colorScheme;

    // Stats is a premium feature — free users see the upsell instead.
    if (!context.watch<PurchaseProvider>().isPremium) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insights_rounded, size: 48, color: scheme.primary),
              const SizedBox(height: 16),
              Text(
                'Insights is a Premium feature',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'See your longest fast, averages, calorie intake and '
                'deficit by month, quarter or year.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('Unlock Premium'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PaywallScreen()),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final (start, end, label) = _range();

    // A fast counts toward the period it ended in.
    final filtered = widget.records
        .where((r) => !r.endTime.isBefore(start) && r.endTime.isBefore(end))
        .toList();

    // Calorie intake in the period, grouped per day with logged meals.
    final fp = context.watch<FastingProvider>();
    final burn = pp.effectiveTdee;
    final kcalPerDay = <DateTime, double>{};
    final mealsInRange = fp.meals
        .where((m) => !m.time.isBefore(start) && m.time.isBefore(end))
        .toList();
    for (final m in mealsInRange) {
      final day = DateTime(m.time.year, m.time.month, m.time.day);
      kcalPerDay[day] = (kcalPerDay[day] ?? 0) + m.calories;
    }
    final insights = MealInsightsService.analyze(mealsInRange);
    final daysLogged = kcalPerDay.length;
    final avgIntake = daysLogged == 0
        ? null
        : kcalPerDay.values.reduce((a, b) => a + b) / daysLogged;
    // Deficit only counts days with logged meals, against that day's
    // burn. Workout burn is added per day only in 'per workout' mode.
    final workoutMode = pp.burnMode == 'workout';
    final totalDeficit = (burn == null || daysLogged == 0)
        ? null
        : kcalPerDay.entries.fold<double>(
            0,
            (sum, e) =>
                sum +
                (burn +
                    (workoutMode ? fp.workoutBurnOnDay(e.key) : 0) -
                    e.value));

    final total = filtered.length;
    final totalHours = filtered.fold<double>(
        0, (sum, r) => sum + r.duration.inMinutes / 60.0);
    final avgH = total == 0 ? 0.0 : totalHours / total;
    final longestH = filtered.isEmpty
        ? 0.0
        : filtered
            .map((r) => r.duration.inMinutes / 60.0)
            .reduce((a, b) => a > b ? a : b);

    return ListView(
      // Bottom padding keeps the FAB below the content when scrolled
      // to the end.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // 1. Period filter on top
        SegmentedButton<_StatsPeriod>(
          segments: const [
            ButtonSegment(value: _StatsPeriod.week, label: Text('Week')),
            ButtonSegment(value: _StatsPeriod.month, label: Text('Month')),
            ButtonSegment(value: _StatsPeriod.quarter, label: Text('Quarter')),
            ButtonSegment(value: _StatsPeriod.year, label: Text('Year')),
          ],
          selected: {_period},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() {
            _period = s.first;
            _offset = 0;
          }),
        ),
        const SizedBox(height: 12),

        // 2. Category selection below
        _categorySelector(context, scheme),
        const SizedBox(height: 4),
        if (!_expanded) ...[
          Text(
            'Tap to view other insights',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF1D9E75),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _offset--),
            ),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed:
                  _offset < 0 ? () => setState(() => _offset++) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_cat == _InsightCat.weight)
          _WeightSection(start: start, end: end, period: _period, fp: fp),
        if (_cat == _InsightCat.training)
          _TrainingSection(start: start, end: end, period: _period, fp: fp),
        if (_cat == _InsightCat.steps)
          _StepsSection(start: start, end: end, period: _period, fp: fp),
        if (_cat == _InsightCat.sleep)
          _SleepSection(start: start, end: end, period: _period, fp: fp),
        if (_cat == _InsightCat.fast)
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No completed fasts in this period.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          else ...[
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.tag_rounded,
                  value: '$total',
                  label: 'Fasts',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.hourglass_bottom_rounded,
                  value: '${totalHours.round()}h',
                  label: 'Total hours',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.timeline_rounded,
                  value: '${avgH.toStringAsFixed(1)}h',
                  label: 'Average',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.emoji_events_rounded,
                  value: '${longestH.toStringAsFixed(1)}h',
                  label: 'Longest',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'TREND',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          _PeriodLineChart(
            perDay: _hoursPerDay(filtered, start, end),
            start: start,
            end: end,
            period: _period,
            lineColor: scheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'FASTED HOURS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 8),
          _FastBarChart(
            records: filtered,
            start: start,
            end: end,
            period: _period,
          ),
        ],
        if (_cat == _InsightCat.nutrition && daysLogged > 0) ...[
          const SizedBox(height: 4),
          Text(
            'NUTRITION · $daysLogged day${daysLogged == 1 ? '' : 's'} logged',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.local_fire_department_rounded,
                  value: '${avgIntake!.round()}',
                  label: 'Avg intake (kcal/day)',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: totalDeficit == null
                      ? Icons.person_outline
                      : totalDeficit >= 0
                          ? Icons.trending_down_rounded
                          : Icons.trending_up_rounded,
                  value: totalDeficit == null
                      ? '—'
                      : '${totalDeficit.abs().round()}',
                  label: totalDeficit == null
                      ? 'Set up profile for deficit'
                      : totalDeficit >= 0
                          ? 'Total deficit (kcal)'
                          : 'Total surplus (kcal)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'TREND',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          _PeriodLineChart(
            perDay: kcalPerDay,
            start: start,
            end: end,
            period: _period,
            lineColor: const Color(0xFFBA7517),
          ),
          const SizedBox(height: 20),
          Text(
            'INTAKE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 8),
          _PeriodBarChart(
            perDay: kcalPerDay,
            start: start,
            end: end,
            period: _period,
            barColor: const Color(0xFFBA7517),
            unit: ' kcal',
            emptyText: 'No intake to chart in this period.',
          ),
        ],
        if (_cat == _InsightCat.nutrition && insights.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'PATTERNS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 8),
          for (final insight in insights) _InsightCard(insight: insight),
          Text(
            'Based on your meal descriptions and macros — an indication, '
            'not medical advice.',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
        if (_cat == _InsightCat.nutrition) ...[
        const SizedBox(height: 20),
        Text(
          'NUTRIENTS · BETA',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
        ),
        const SizedBox(height: 8),
        if (_nutriReady == false)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'See which vitamins and minerals your logged meals may '
                  'be missing. Uses the official Norwegian food table '
                  '(Matvaretabellen) — a one-time download, then fully '
                  'offline.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  icon: _nutriBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_nutriBusy
                      ? 'Downloading…'
                      : 'Enable nutrient insights'),
                  onPressed: _nutriBusy ? null : _downloadNutritionTable,
                ),
              ],
            ),
          )
        else if (_nutriReady == true)
          FutureBuilder<List<MealInsight>>(
            future: MicroInsightsService.analyze(mealsInRange),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              final micro = snap.data!;
              if (micro.isEmpty) {
                return Text(
                  'Not enough analysed meals in this period yet — log a '
                  'few more days and check back.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final insight in micro) _InsightCard(insight: insight),
                  Text(
                    'Estimated from AI-extracted foods matched against '
                    'Matvaretabellen (Mattilsynet). Counts only days with '
                    'analysed meals — an estimate, not medical advice.',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _WeightSection extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final _StatsPeriod period;
  final FastingProvider fp;
  const _WeightSection(
      {required this.start,
      required this.end,
      required this.period,
      required this.fp});

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final isImperial = pp.unitSystem == UnitSystem.imperial;
    final unit = isImperial ? 'lbs' : 'kg';

    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final endCapped = end.isAfter(now) ? now : end;

    final step = switch (period) {
      _StatsPeriod.week => const Duration(days: 1),
      _StatsPeriod.month => const Duration(days: 1),
      _StatsPeriod.quarter => const Duration(days: 7),
      _StatsPeriod.year => const Duration(days: 30),
    };
    final days = <DateTime>[];
    var d = DateTime(start.year, start.month, start.day);
    while (!d.isAfter(endCapped) && days.length < 370) {
      days.add(d);
      d = d.add(step);
    }
    final lastDay =
        DateTime(endCapped.year, endCapped.month, endCapped.day);
    if (days.isNotEmpty && days.last != lastDay) days.add(lastDay);

    final values = [for (final day in days) fp.weightOnDay(day)];
    final actualIdx = <int>{};
    for (var i = 0; i < days.length; i++) {
      final bucketStart =
          i == 0 ? days[i].subtract(step) : days[i - 1];
      final bucketEnd = days[i].add(const Duration(days: 1));
      if (fp.weights.any((w) =>
          w.time.isAfter(bucketStart) && w.time.isBefore(bucketEnd))) {
        actualIdx.add(i);
      }
    }

    final known = values.whereType<double>().toList();
    if (known.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'Log your weight (Journal → +) to see the trend here. '
            'Weights from Health Connect count too.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final first = known.first;
    final last = known.last;
    final change = last - first;
    
    final displayLast = isImperial ? last / 0.45359237 : last;
    final displayChange = isImperial ? change / 0.45359237 : change;
    
    final changeStr =
        '${change >= 0 ? '+' : ''}${displayChange.toStringAsFixed(1)} $unit';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.monitor_weight_outlined,
                value: '${displayLast.toStringAsFixed(1)} $unit',
                label: 'Latest',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: change <= 0
                    ? Icons.trending_down_rounded
                    : Icons.trending_up_rounded,
                value: changeStr,
                label: 'This period',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          width: double.infinity,
          child: CustomPaint(
            painter: _WeightChartPainter(
              values: values,
              actualIdx: actualIdx,
              isImperial: isImperial,
              lineColor: const Color(0xFF1D9E75),
              gridColor: scheme.outlineVariant.withValues(alpha: 0.5),
              labelColor: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(DateFormat('d MMM').format(days.first),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            Text(DateFormat('d MMM').format(days.last),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Dots mark days you logged a weight; between them the last known '
          'weight carries forward.',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  final List<double?> values;
  final Set<int> actualIdx;
  final bool isImperial;
  final Color lineColor;
  final Color gridColor;
  final Color labelColor;

  _WeightChartPainter({
    required this.values,
    required this.actualIdx,
    required this.isImperial,
    required this.lineColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final knownRaw = values.whereType<double>().toList();
    if (knownRaw.length < 2) return;
    
    final known = [for (final v in knownRaw) isImperial ? v / 0.45359237 : v];
    final displayValues = [for (final v in values) v == null ? null : (isImperial ? v / 0.45359237 : v)];

    var minV = known.reduce((a, b) => a < b ? a : b);
    var maxV = known.reduce((a, b) => a > b ? a : b);
    if ((maxV - minV) < 1) {
      minV -= 0.5;
      maxV += 0.5;
    } else {
      final pad = (maxV - minV) * 0.15;
      minV -= pad;
      maxV += pad;
    }

    const leftPad = 38.0;
    final chartW = size.width - leftPad;
    final chartH = size.height;

    double x(int i) => values.length == 1
        ? leftPad
        : leftPad + chartW * i / (values.length - 1);
    double y(double v) => chartH - chartH * (v - minV) / (maxV - minV);

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final v in [maxV, minV]) {
      final yy = y(v).clamp(8.0, chartH - 8.0);
      canvas.drawLine(Offset(leftPad, yy), Offset(size.width, yy), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: v.toStringAsFixed(1),
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, yy - tp.height / 2));
    }

    final path = Path();
    var started = false;
    for (var i = 0; i < displayValues.length; i++) {
      final v = displayValues[i];
      if (v == null) continue;
      final p = Offset(x(i), y(v));
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    final dot = Paint()..color = lineColor;
    for (final i in actualIdx) {
      final v = displayValues[i];
      if (v == null) continue;
      canvas.drawCircle(Offset(x(i), y(v)), 4, dot);
    }
  }

  @override
  bool shouldRepaint(_WeightChartPainter old) =>
      old.values != values ||
      old.actualIdx != actualIdx ||
      old.isImperial != isImperial ||
      old.lineColor != lineColor;
}

class _TrainingSection extends StatefulWidget {
  final DateTime start;
  final DateTime end;
  final _StatsPeriod period;
  final FastingProvider fp;
  const _TrainingSection({required this.start, required this.end, required this.period, required this.fp});

  @override
  State<_TrainingSection> createState() => _TrainingSectionState();
}

class _TrainingSectionState extends State<_TrainingSection> {
  String? _selectedExercise;
  bool _expanded = false;

  double _estimate1RM(double kg, int reps) {
    if (reps <= 1) return kg;
    // Brzycki Formula: Weight / (1.0278 - (0.0278 * Reps))
    // Simplification for UI: Weight * (36 / (37 - Reps))
    return kg * (36 / (37 - reps.clamp(1, 36)));
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final isImperial = pp.unitSystem == UnitSystem.imperial;
    final unit = isImperial ? 'lbs' : 'kg';

    final scheme = Theme.of(context).colorScheme;
    final inRange = widget.fp.workouts
        .where((w) =>
            !w.startTime.isBefore(widget.start) && w.startTime.isBefore(widget.end))
        .toList();

    if (inRange.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No workouts in this period.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final allExerciseNames = <String>{};
    for (final w in inRange) {
      allExerciseNames.addAll(w.exerciseNames);
    }
    final sortedNames = allExerciseNames.toList()..sort();

    // Stats calculations
    int totalWorkouts = 0;
    int totalReps = 0;
    int totalSets = 0;
    double bestEst1RM = 0;
    double absoluteMaxLift = 0;
    final chartData = <DateTime, double>{};

    for (final w in inRange) {
      final day = DateTime(w.startTime.year, w.startTime.month, w.startTime.day);
      bool workoutHasEx = false;
      double dailyMaxLift = 0;

      try {
        final list = jsonDecode(w.exercisesJson ?? '[]') as List;
        for (final e in list) {
          if (e is! Map) continue;
          final name = e['n'] as String?;
          final sets = e['sets'];
          if (name == null || sets is! List) continue;

          if (_selectedExercise == null || name == _selectedExercise) {
            workoutHasEx = true;
            for (final s in sets) {
              if (s is! Map) continue;
              final kg = (s['kg'] as num?)?.toDouble() ?? 0;
              final reps = (s['reps'] as num?)?.toInt() ?? 0;

              totalReps += reps;
              totalSets++;
              
              if (kg > absoluteMaxLift) absoluteMaxLift = kg;
              if (kg > dailyMaxLift) dailyMaxLift = kg;

              final e1rm = _estimate1RM(kg, reps);
              if (e1rm > bestEst1RM) bestEst1RM = e1rm;
              
              // For "All exercises", chart shows volume
              if (_selectedExercise == null) {
                chartData[day] = (chartData[day] ?? 0) + (kg * reps);
              }
            }
          }
        }
      } catch (_) {}

      if (workoutHasEx) {
        totalWorkouts++;
        if (_selectedExercise != null && dailyMaxLift > 0) {
          // For specific exercise, chart shows real Max Lift (KG)
          chartData[day] = dailyMaxLift;
        }
      }
    }

    final avgReps = totalSets == 0 ? 0.0 : totalReps / totalSets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _exerciseSelector(context, scheme, sortedNames),
        const SizedBox(height: 16),
        
        // 5 Summary Tiles Grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            _StatCard(
              icon: Icons.fitness_center_rounded,
              value: '$totalWorkouts',
              label: 'Workouts',
            ),
            _StatCard(
              icon: Icons.repeat_rounded,
              value: '$totalReps',
              label: 'Total Reps',
            ),
            _StatCard(
              icon: Icons.bolt_rounded,
              value: '${(isImperial ? bestEst1RM / 0.45359237 : bestEst1RM).round()} $unit',
              label: 'Est. 1RM',
            ),
            _StatCard(
              icon: Icons.upload_rounded,
              value: '${(isImperial ? absoluteMaxLift / 0.45359237 : absoluteMaxLift).round()} $unit',
              label: 'Max Lift',
            ),
            _StatCard(
              icon: Icons.analytics_outlined,
              value: avgReps.toStringAsFixed(1),
              label: 'Avg. Reps',
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        Text(
          _selectedExercise == null ? 'VOLUME TREND' : 'STRENGTH TREND: $_selectedExercise',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
        ),
        const SizedBox(height: 8),
        _PeriodLineChart(
          perDay: chartData.map((k, v) => MapEntry(k, isImperial ? v / 0.45359237 : v)),
          start: widget.start,
          end: widget.end,
          period: widget.period,
          lineColor: scheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          _selectedExercise == null 
            ? 'Total volume in $unit moved across all exercises.'
            : 'Reell vektøkning i styrke (maks løft per økt i $unit).',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _exerciseSelector(BuildContext context, ColorScheme scheme, List<String> sortedNames) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: _expanded
                  ? const BorderRadius.vertical(top: Radius.circular(12))
                  : BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF1D9E75),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Color(0xFF1D9E75), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filter by exercise',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      Text(
                        _selectedExercise ?? 'All exercises',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border.all(
                color: const Color(0xFF1D9E75),
                width: 1.5,
              ),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                _exerciseItem(context, scheme, null),
                for (final name in sortedNames)
                  _exerciseItem(context, scheme, name),
              ],
            ),
          ),
      ],
    );
  }

  Widget _exerciseItem(BuildContext context, ColorScheme scheme, String? name) {
    final selected = _selectedExercise == name;
    return InkWell(
      onTap: () => setState(() {
        _selectedExercise = name;
        _expanded = false;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.3) : null,
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              name ?? 'All exercises',
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? const Color(0xFF1D9E75) : scheme.onSurface,
              ),
            ),
            if (selected) ...[
              const Spacer(),
              const Icon(Icons.check_rounded, size: 18, color: Color(0xFF1D9E75)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepsSection extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final _StatsPeriod period;
  final FastingProvider fp;
  const _StepsSection({required this.start, required this.end, required this.period, required this.fp});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stepsInRange = <DateTime, double>{
      for (final e in fp.stepsPerDay.entries)
        if (!e.key.isBefore(start) && e.key.isBefore(end)) e.key: e.value.toDouble(),
    };
    if (stepsInRange.isEmpty) return const Center(child: Text('No steps data.'));
    // Average only over days that actually have step data — a day with no
    // recorded steps (before tracking started, or just not synced yet)
    // shouldn't drag the average down as if it were a real 0-step day.
    final daysWithSteps = stepsInRange.values.where((v) => v > 0);
    final avgSteps = daysWithSteps.isEmpty
        ? 0.0
        : daysWithSteps.reduce((a, b) => a + b) / daysWithSteps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _StatCard(icon: Icons.directions_walk_rounded, value: '${avgSteps.round()}', label: 'Avg steps/day')),
        const SizedBox(height: 16),
        Text('TREND', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1)),
        _PeriodLineChart(perDay: stepsInRange, start: start, end: end, period: period, lineColor: const Color(0xFF378ADD)),
        const SizedBox(height: 20),
        Text('STEPS', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1)),
        _PeriodBarChart(perDay: stepsInRange, start: start, end: end, period: period, barColor: const Color(0xFF378ADD), unit: '', emptyText: 'No steps data.'),
      ],
    );
  }
}

class _SleepSection extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final _StatsPeriod period;
  final FastingProvider fp;
  const _SleepSection({required this.start, required this.end, required this.period, required this.fp});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sleepInRange = <DateTime, double>{
      for (final e in fp.sleepMinutesPerDay.entries)
        if (!e.key.isBefore(start) && e.key.isBefore(end)) e.key: e.value / 60.0,
    };
    if (sleepInRange.isEmpty) return const Center(child: Text('No sleep data.'));
    final avgSleepH = sleepInRange.values.reduce((a, b) => a + b) / sleepInRange.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: _StatCard(icon: Icons.bedtime_rounded, value: '${avgSleepH.toStringAsFixed(1)}h', label: 'Avg sleep/night')),
        const SizedBox(height: 16),
        Text('TREND', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1)),
        _PeriodLineChart(perDay: sleepInRange, start: start, end: end, period: period, lineColor: const Color(0xFF7F77DD)),
        const SizedBox(height: 20),
        Text('SLEEP (HOURS)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1)),
        _PeriodBarChart(perDay: sleepInRange, start: start, end: end, period: period, barColor: const Color(0xFF7F77DD), unit: 'h', emptyText: 'No sleep data.'),
      ],
    );
  }
}

class _FastBarChart extends StatelessWidget {
  final List<FastRecord> records;
  final DateTime start;
  final DateTime end;
  final _StatsPeriod period;
  const _FastBarChart({required this.records, required this.start, required this.end, required this.period});

  Map<DateTime, double> _hoursPerDay(List<FastRecord> records, DateTime start, DateTime end) {
    final map = <DateTime, double>{};
    for (final r in records) {
      var cursor = r.startTime.isBefore(start) ? start : r.startTime;
      final stop = r.endTime.isAfter(end) ? end : r.endTime;
      while (cursor.isBefore(stop)) {
        final day = DateTime(cursor.year, cursor.month, cursor.day);
        final nextMidnight = day.add(const Duration(days: 1));
        final segmentEnd = stop.isBefore(nextMidnight) ? stop : nextMidnight;
        map[day] = (map[day] ?? 0) + segmentEnd.difference(cursor).inMinutes / 60.0;
        cursor = segmentEnd;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final perDay = _hoursPerDay(records, start, end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TREND', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1)),
        _PeriodLineChart(perDay: perDay, start: start, end: end, period: period, lineColor: scheme.primary),
        const SizedBox(height: 16),
        Text('DETAILS', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold, letterSpacing: 1)),
        _PeriodBarChart(perDay: perDay, start: start, end: end, period: period, barColor: scheme.primary, unit: 'h', emptyText: 'No fasts.'),
      ],
    );
  }
}

(List<double>, List<String>) _bucketize(Map<DateTime, double> perDay, DateTime start, DateTime end, _StatsPeriod period) {
  final values = <double>[];
  final labels = <String>[];
  switch (period) {
    case _StatsPeriod.week:
    case _StatsPeriod.month:
      var d = DateTime(start.year, start.month, start.day);
      while (d.isBefore(end)) {
        values.add(perDay[d] ?? 0);
        labels.add(DateFormat(period == _StatsPeriod.week ? 'E d/M' : 'd MMM').format(d));
        d = d.add(const Duration(days: 1));
      }
    case _StatsPeriod.quarter:
      var weekStart = DateTime(start.year, start.month, start.day);
      while (weekStart.isBefore(end)) {
        var sum = 0.0;
        for (var i = 0; i < 7; i++) {
          final day = weekStart.add(Duration(days: i));
          if (!day.isBefore(end)) break;
          sum += perDay[DateTime(day.year, day.month, day.day)] ?? 0;
        }
        values.add(sum);
        labels.add('wk ${DateFormat('d/M').format(weekStart)}');
        weekStart = weekStart.add(const Duration(days: 7));
      }
    case _StatsPeriod.year:
      for (var m = 1; m <= 12; m++) {
        final monthStart = DateTime(start.year, m);
        final monthEnd = DateTime(start.year, m + 1);
        var sum = 0.0;
        perDay.forEach((day, h) { if (!day.isBefore(monthStart) && day.isBefore(monthEnd)) sum += h; });
        values.add(sum);
        labels.add(DateFormat('MMM').format(monthStart));
      }
  }
  return (values, labels);
}

class _PeriodLineChart extends StatelessWidget {
  final Map<DateTime, double> perDay;
  final DateTime start;
  final DateTime end;
  final _StatsPeriod period;
  final Color lineColor;
  const _PeriodLineChart({required this.perDay, required this.start, required this.end, required this.period, required this.lineColor});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (values, _) = _bucketize(perDay, start, end, period);
    if (values.every((v) => v == 0)) return const SizedBox.shrink();
    return Container(height: 100, width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), child: CustomPaint(painter: _LineChartPainter(values: values, lineColor: lineColor, gridColor: scheme.outlineVariant.withValues(alpha: 0.3))));
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  _LineChartPainter({required this.values, required this.lineColor, required this.gridColor});
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final range = (maxV - minV) < 1 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      points.add(Offset(i * dx, size.height - (size.height * (values[i] - minV) / range)));
    }
    final paint = Paint()..color = lineColor..strokeWidth = 3..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);
    final dotPaint = Paint()..color = lineColor;
    for (final p in points) {
      canvas.drawCircle(p, 3, dotPaint);
    }
  }
  @override
  bool shouldRepaint(_LineChartPainter old) => old.values != values;
}

class _PeriodBarChart extends StatelessWidget {
  final Map<DateTime, double> perDay;
  final DateTime start;
  final DateTime end;
  final _StatsPeriod period;
  final Color barColor;
  final String unit;
  final String emptyText;
  const _PeriodBarChart({required this.perDay, required this.start, required this.end, required this.period, required this.barColor, required this.unit, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (values, labels) = _bucketize(perDay, start, end, period);
    if (values.every((v) => v == 0)) return Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(emptyText, style: TextStyle(color: scheme.onSurfaceVariant)));
    const rowPx = 24.0;
    final chartHeight = (values.length * rowPx).clamp(96.0, 900.0);
    return SizedBox(height: chartHeight, width: double.infinity, child: CustomPaint(painter: _BarChartPainter(values: values, labels: labels, barColor: barColor, gridColor: scheme.outlineVariant.withValues(alpha: 0.5), labelColor: scheme.onSurfaceVariant, unit: unit)));
  }
}

class _BarChartPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color barColor;
  final Color gridColor;
  final Color labelColor;
  final String unit;
  _BarChartPainter({required this.values, required this.labels, required this.barColor, required this.gridColor, required this.labelColor, this.unit = ''});

  static String _fmtNum(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final rawMax = values.reduce((a, b) => a > b ? a : b);
    final maxV = rawMax < 1.0 ? 1.0 : rawMax;
    final labelPainters = [for (final l in labels) TextPainter(text: TextSpan(text: l, style: TextStyle(color: labelColor, fontSize: 11)), textDirection: ui.TextDirection.ltr)..layout()];
    var labelW = 0.0;
    for (final tp in labelPainters) {
      if (tp.width > labelW) labelW = tp.width;
    }
    final leftPad = (labelW + 10).clamp(24.0, 96.0);
    final valuePainters = [for (final v in values) TextPainter(text: TextSpan(text: v > 0 ? '${_fmtNum(v)}$unit' : '', style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.w600)), textDirection: ui.TextDirection.ltr)..layout()];
    var valueW = 0.0;
    for (final tp in valuePainters) {
      if (tp.width > valueW) valueW = tp.width;
    }
    final rightPad = valueW + 8;
    final barMaxW = (size.width - leftPad - rightPad).clamp(1.0, size.width);
    final n = values.length;
    final rowH = size.height / n;
    final barH = (rowH * 0.55).clamp(5.0, 16.0);
    final radius = Radius.circular(barH / 2);
    final trackPaint = Paint()..color = gridColor.withValues(alpha: 0.35);
    final barPaint = Paint()..color = barColor;
    for (var i = 0; i < n; i++) {
      final cy = rowH * i + rowH / 2;
      final top = cy - barH / 2;
      final lp = labelPainters[i];
      lp.paint(canvas, Offset(leftPad - 6 - lp.width, cy - lp.height / 2));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(leftPad, top, barMaxW, barH), radius), trackPaint);
      final v = values[i];
      if (v > 0) {
        final w = (barMaxW * v / maxV).clamp(barH, barMaxW);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(leftPad, top, w, barH), radius), barPaint);
        final vp = valuePainters[i];
        vp.paint(canvas, Offset(size.width - vp.width, cy - vp.height / 2));
      }
    }
  }
  @override
  bool shouldRepaint(_BarChartPainter old) => old.values != values || old.barColor != barColor;
}

class _InsightCard extends StatelessWidget {
  final MealInsight insight;
  const _InsightCard({required this.insight});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = insight.positive ? const Color(0xFF1D9E75) : const Color(0xFFBA7517);
    return Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: accent.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: 0.25))), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(insight.icon, size: 20, color: accent), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(insight.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: accent)), const SizedBox(height: 3), Text(insight.body, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface, height: 1.4))]))]));
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value, label;
  const _StatCard({required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16), decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(20), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4))), child: Column(children: [Icon(icon, color: scheme.primary, size: 22), const SizedBox(height: 8), Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))]));
  }
}

class _FastTile extends StatelessWidget {
  final FastRecord record;
  final DateTime day;
  final VoidCallback? onEdit;
  const _FastTile({required this.record, required this.day, required this.onEdit});
  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm');

    final scheme = Theme.of(context).colorScheme;
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final segStart = record.startTime.isAfter(dayStart) ? record.startTime : dayStart;
    final segEnd = record.endTime.isBefore(dayEnd) ? record.endTime : dayEnd;
    final hoursOnDay = segEnd.isAfter(segStart) ? segEnd.difference(segStart).inMinutes / 60.0 : 0.0;
    final spansOtherDays = record.startTime.isBefore(dayStart) || record.endTime.isAfter(dayEnd);
    final ongoing = onEdit == null;
    return ListTile(leading: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Text(record.protocol, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))), title: Text('Fast · ${hoursOnDay.toStringAsFixed(1)}h this day${ongoing ? ' · ongoing' : ''}'), subtitle: Text('${fmt.format(record.startTime)} – ${ongoing ? 'now' : fmt.format(record.endTime)}${spansOtherDays ? '  ·  ${record.formattedDuration} total' : ''}'), trailing: ongoing ? Icon(Icons.hourglass_top_rounded, size: 18, color: scheme.primary) : const Icon(Icons.edit_outlined, size: 18), onTap: onEdit);
  }
}

class _MealTile extends StatelessWidget {
  final MealRecord meal;
  final VoidCallback onEdit;
  const _MealTile({required this.meal, required this.onEdit});
  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm');

    final scheme = Theme.of(context).colorScheme;
    final macros = <String>[if (meal.protein != null) 'P ${meal.protein!.round()}g', if (meal.carbs != null) 'C ${meal.carbs!.round()}g', if (meal.fat != null) 'F ${meal.fat!.round()}g'].join(' · ');
    return ListTile(leading: CircleAvatar(backgroundColor: scheme.tertiaryContainer, child: const Icon(Icons.restaurant, size: 18)), title: Text(meal.name, maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: Text('${fmt.format(meal.time)} · ${meal.calories.round()} kcal${macros.isNotEmpty ? '  ·  $macros' : ''}'), trailing: const Icon(Icons.edit_outlined, size: 18), onTap: onEdit);
  }
}
