import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../services/training_programs.dart';

/// Full detail view of a training program: description, source and all
/// day types in the split with their exercise lists.
class ProgramDetailsScreen extends StatelessWidget {
  final Program program;
  const ProgramDetailsScreen({super.key, required this.program});

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final isImperial = pp.unitSystem == UnitSystem.imperial;
    final unit = isImperial ? 'lbs' : 'kg';

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(program.name)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () => Navigator.pop(context, program.id),
            child: const Text('Change to this program'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _infoCard(context, scheme),
          const SizedBox(height: 20),
          Text(
            'SPLIT DETAILS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < program.days.length; i++)
            _dayCard(context, scheme, program.days[i], i + 1, isImperial, unit),
        ],
      ),
    );
  }

  Widget _infoCard(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _pill(context, scheme, program.experience),
              const SizedBox(width: 8),
              _pill(context, scheme, program.daysPerWeek),
            ],
          ),
          const SizedBox(height: 12),
          Text(program.description, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            'Source: ${program.source}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _dayCard(BuildContext context, ColorScheme scheme, ProgramDay day, int number, bool isImperial, String unit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              CircleAvatar(
                radius: 12,
                child: Text('$number', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Text(day.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 12),
          for (final e in day.exercises)
            Builder(
              builder: (context) {
                final displayStart = isImperial ? e.startKg / 0.45359237 : e.startKg;
                final displayInc = isImperial ? e.incrementKg / 0.45359237 : e.incrementKg;

                final startStr = displayStart == displayStart.roundToDouble() ? displayStart.round().toString() : displayStart.toStringAsFixed(1);
                final incStr = displayInc == displayInc.roundToDouble() ? displayInc.round().toString() : displayInc.toStringAsFixed(1);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${e.name}: ${e.sets}×${e.reps} @ $startStr$unit (+$incStr$unit)',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
            ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, ColorScheme scheme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: scheme.primary),
      ),
    );
  }
}
