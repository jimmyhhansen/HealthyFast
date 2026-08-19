import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fasting_zone.dart';
import '../providers/fasting_provider.dart';
import '../widgets/fasting_ring_widget.dart';
import '../widgets/settings_action.dart';
import '../widgets/zone_strip_widget.dart';
import '../widgets/app_bar_title.dart';

class HomeScreen extends StatefulWidget {
  final String? targetZone;
  const HomeScreen({super.key, this.targetZone});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scrollController = ScrollController();
  final _tipsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.targetZone != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTips();
      });
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetZone != null && widget.targetZone != oldWidget.targetZone) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToTips();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTips() {
    final ctx = _tipsKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const HealthyFastTitle(),
        actions: [settingsAction(context)],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The ring, zones, protocol chips and start/stop controls always
            // fit within the first "page"; the tips live below the fold and
            // are reachable by scrolling on any screen size.
            //
            // The fixed controls are text-dominated, so their height grows
            // roughly linearly with the system font scale. Reserve room for
            // them (~300 logical px at scale 1.0) plus the ring's minimum
            // (200) — when that exceeds the viewport, the first page itself
            // scrolls and the overflow simply moves into the scroll instead
            // of squeezing the ring or overlapping text.
            final textScale =
                MediaQuery.textScalerOf(context).scale(16.0) / 16.0;
            final firstPageHeight =
                math.max(constraints.maxHeight, 300.0 * textScale + 220.0);

            return SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  SizedBox(
                    height: firstPageHeight,
                    child: Column(
                      children: [
                        // Ring absorbs all the space the controls leave over,
                        // so it grows on tall screens and shrinks on small.
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) {
                              final size = math
                                  .min(box.maxWidth - 40, box.maxHeight - 8)
                                  .clamp(200.0, 420.0)
                                  .toDouble();
                              return Center(
                                child: FastingRingWidget(size: size),
                              );
                            },
                          ),
                        ),

                        // Zone strip
                        const ZoneStripWidget(),
                        const SizedBox(height: 14),

                        // Protocol selector — ONE compact, horizontally
                        // scrollable line, so the ring gets the space the
                        // second chip row used to take.
                        SizedBox(
                          height: 40,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                for (final p in FastingProtocol.presets) ...[
                                  ChoiceChip(
                                    label: Text(p.label),
                                    visualDensity: VisualDensity.compact,
                                    labelStyle:
                                        const TextStyle(fontSize: 12.5),
                                    selected: fp.protocol == p,
                                    onSelected: fp.isFasting
                                        ? null
                                        : (_) => fp.setProtocol(p),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                ChoiceChip(
                                  avatar: fp.protocol.isCustom
                                      ? null
                                      : const Icon(Icons.tune, size: 14),
                                  label: Text(fp.protocol.isCustom
                                      ? 'Custom: ${fp.protocol.label}'
                                      : 'Custom'),
                                  visualDensity: VisualDensity.compact,
                                  labelStyle: const TextStyle(fontSize: 12.5),
                                  selected: fp.protocol.isCustom,
                                  onSelected: fp.isFasting
                                      ? null
                                      : (_) =>
                                          _showCustomFastDialog(context, fp),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Start / Stop button (+ edit start time while fasting)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (fp.isFasting) const SizedBox(width: 48),
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(200, 54),
                                // primaryContainer in both states — the same
                                // color as the Meals + button, so the app's
                                // primary actions share one identity.
                                backgroundColor: scheme.primaryContainer,
                                foregroundColor: scheme.onPrimaryContainer,
                              ),
                              onPressed: fp.isFasting
                                  ? () => _confirmStop(context, fp)
                                  : fp.startFast,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  fp.isFasting ? 'Stop Fast' : 'Start Fast',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                            ),
                            if (fp.isFasting)
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit fast',
                                onPressed: () => _showEditSheet(context, fp),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Calm, static one-liner — the dynamic tip teaser
                        // took more vertical space than it earned.
                        _MoreInfoHint(
                          label: fp.isFasting
                              ? 'Information about this fast zone'
                              : 'Information about the fast zones',
                          onTap: _scrollToTips,
                        ),
                        const SizedBox(height: 2),
                      ],
                    ),
                  ),

                  // ── Below the fold: zone tips ────────────────────────────
                  _TipsSection(key: _tipsKey, targetZone: widget.targetZone),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showCustomFastDialog(
      BuildContext context, FastingProvider fp) async {
    // All fasting types — including custom — are free.
    final totalHours = await _pickCustomHours(context, fp);
    if (totalHours != null) fp.setCustomProtocol(totalHours);
  }

  /// Shows the day/hour stepper dialog and returns the chosen total hours.
  Future<int?> _pickCustomHours(
      BuildContext context, FastingProvider fp) async {
    var days = fp.customHours ~/ 24;
    var hours = fp.customHours % 24;

    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final total = days * 24 + hours;
          return AlertDialog(
            title: const Text('Custom fast'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _NumberStepper(
                        label: 'Days',
                        value: days,
                        min: 0,
                        max: 14,
                        onChanged: (v) => setState(() => days = v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _NumberStepper(
                        label: 'Hours',
                        value: hours,
                        min: 0,
                        max: 23,
                        onChanged: (v) => setState(() => hours = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  total > 0 ? 'Goal: $total hours total' : 'Set a duration',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: total > 0 ? () => Navigator.pop(ctx, total) : null,
                child: const Text('Set'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditSheet(BuildContext context, FastingProvider fp) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Edit start time'),
              subtitle: const Text('Adjust when this fast actually began'),
              onTap: () => Navigator.pop(ctx, 'time'),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Change goal'),
              subtitle: Text('Currently ${fp.protocol.label}'),
              onTap: () => Navigator.pop(ctx, 'goal'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action == 'time') {
      await _editStartTime(context, fp);
    } else if (action == 'goal') {
      await _editGoal(context, fp);
    }
  }

  Future<void> _editGoal(BuildContext context, FastingProvider fp) async {
    final selected = await showModalBottomSheet<FastingProtocol>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Change goal',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in FastingProtocol.presets)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: fp.protocol == p,
                    onSelected: (_) => Navigator.pop(ctx, p),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.tune, size: 16),
                  label: const Text('Custom'),
                  onPressed: () => Navigator.pop(ctx, FastingProtocol.custom(-1)),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    // Sentinel hours == -1 means "open the custom day/hour picker".
    if (selected.hours == -1) {
      // All fasting types — including custom — are free.
      final total = await _pickCustomHours(context, fp);
      if (total != null) await fp.updateGoalDuringFast(FastingProtocol.custom(total));
    } else {
      await fp.updateGoalDuringFast(selected);
    }
  }

  Future<void> _editStartTime(BuildContext context, FastingProvider fp) async {
    final current = fp.startTime;
    if (current == null) return;
    final now = DateTime.now();
    final firstDate = now.subtract(const Duration(days: 14));

    final date = await showDatePicker(
      context: context,
      initialDate: current.isBefore(firstDate) ? firstDate : current,
      firstDate: firstDate,
      lastDate: now,
      helpText: 'When did you actually start fasting?',
    );
    if (date == null || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'Start time',
    );
    if (time == null || !context.mounted) return;

    final newStart =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (newStart.isAfter(now)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Start time cannot be in the future.'),
      ));
      return;
    }
    await fp.editStartTime(newStart);
  }

  Future<void> _confirmStop(
      BuildContext context, FastingProvider fp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop fast?'),
        content: Text(
          'You have been fasting for ${fp.formatDuration(fp.elapsed)}. Stop and save this fast?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final elapsed = fp.elapsed;
      await fp.stopFast();
      if (context.mounted) await _maybeAskForRating(context, elapsed);
    }
  }

  /// One-time, friendly rating ask after the first real completed fast
  /// (at least 4 hours, so a quick test start/stop doesn't trigger it).
  Future<void> _maybeAskForRating(
      BuildContext context, Duration elapsed) async {
    if (elapsed.inHours < 4) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('rating_prompt_shown') ?? false) return;
    await prefs.setBool('rating_prompt_shown', true);
    if (!context.mounted) return;

    final goToStore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('You did it! 🎉'),
        content: const Text(
          'Congratulations on completing your first fast!\n\n'
          'HealthyFast is my very first app, and honest feedback means a '
          'lot — I read and consider every single review.\n\n'
          'If you\'d like to help, leaving a rating on Google Play makes a '
          'real difference. Thank you! :)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Maybe later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rate on Google Play'),
          ),
        ],
      ),
    );

    if (goToStore == true) {
      try {
        await InAppReview.instance.openStoreListing();
      } catch (_) {
        // Store not available (e.g. sideloaded build) — ignore.
      }
    }
  }
}

/// Small, calm affordance telling the user more content lives below the fold.
/// While fasting it shows the current zone's tip headline instead.
class _MoreInfoHint extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MoreInfoHint({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = scheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Text(
                label,
                key: ValueKey(label),
                // Wraps to a second line only when it truly doesn't fit
                // (extreme font sizes); normally stays on one line.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: textColor,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: textColor.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}

/// The zone tips below the fold. While fasting: only the CURRENT zone's
/// card, with the full timeline behind a "Show all zones" toggle. Idle:
/// the full timeline (that's what the hint promised).
class _TipsSection extends StatefulWidget {
  final String? targetZone;
  const _TipsSection({super.key, this.targetZone});

  @override
  State<_TipsSection> createState() => _TipsSectionState();
}

class _TipsSectionState extends State<_TipsSection> {
  bool _showAll = false;

  @override
  void didUpdateWidget(_TipsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetZone != null && widget.targetZone != oldWidget.targetZone) {
      final fp = context.read<FastingProvider>();
      final isCurrent = fp.isFasting && fp.currentZone.name == widget.targetZone;
      if (!isCurrent) {
        setState(() => _showAll = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    final scheme = Theme.of(context).colorScheme;
    final current = fp.isFasting ? fp.currentZone : null;
    
    // Auto-expand if the targeted zone isn't the current one
    final expandAll = current == null || _showAll || 
                     (widget.targetZone != null && widget.targetZone != current.name);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT HAPPENS IN YOUR BODY',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(height: 16),
          if (current != null) _ZoneTipCard(zone: current, isCurrent: true),
          if (expandAll)
            for (final zone in kFastingZones)
              if (current?.name != zone.name)
                _ZoneTipCard(zone: zone, isCurrent: false),
          if (current != null)
            TextButton.icon(
              icon: Icon(
                _showAll
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              label: Text(_showAll ? 'Hide other zones' : 'Show all zones'),
              onPressed: () => setState(() => _showAll = !_showAll),
            ),
        ],
      ),
    );
  }
}

class _ZoneTipCard extends StatelessWidget {
  final FastingZone zone;
  final bool isCurrent;

  const _ZoneTipCard({required this.zone, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: zone.color.withValues(alpha: isCurrent ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: zone.color.withValues(alpha: isCurrent ? 0.8 : 0.2),
          width: isCurrent ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(zone.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${zone.name} · ${zone.shortLabel}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: zone.color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              if (isCurrent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: zone.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'NOW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            zone.tip,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.science_outlined,
                  size: 13, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  zone.source,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  final String label;
  final int value, min, max;
  final ValueChanged<int> onChanged;

  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 32,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}
