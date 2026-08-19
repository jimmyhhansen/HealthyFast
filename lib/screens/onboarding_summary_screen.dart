import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fitness_goal.dart';
import '../providers/profile_provider.dart';
import '../providers/purchase_provider.dart';
import 'paywall_screen.dart';

/// The close of the welcome flow.
///
/// Deliberately value-first: it leads with the numbers the user just
/// produced, then shows the plan built on top of them — free items already
/// ticked, premium items listed as what the plan is *missing*. The upgrade
/// is an offer next to a working free app, never a wall.
class OnboardingSummaryScreen extends StatelessWidget {
  const OnboardingSummaryScreen({super.key, required this.onDone});

  /// Called when the user finishes. The welcome flow uses this to mark
  /// onboarding complete and drop into the app.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final premium = context.watch<PurchaseProvider>().isPremium;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final goal = pp.goal;
    final tdee = pp.effectiveTdee;
    final target = pp.goalCalorieTarget;

    final matched = kCapabilities.where((c) => c.matches(goal)).toList();
    final free = matched.where((c) => !c.premium).toList();
    final locked = matched.where((c) => c.premium).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onDone();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_rounded,
                            size: 30, color: scheme.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      goal.planHeadline,
                      textAlign: TextAlign.center,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Built from your numbers, not an average.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Their numbers ──────────────────────────────────
                    if (tdee != null && target != null)
                      _NumbersCard(
                        tdee: tdee,
                        target: target,
                        explainer: goal.targetExplainer,
                      ),
                    const SizedBox(height: 24),

                    Text(
                      'READY NOW',
                      style: text.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final c in free)
                      _CapabilityRow(capability: c, unlocked: true),

                    if (locked.isNotEmpty && !premium) ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            'ALSO BUILT FOR THIS GOAL',
                            style: text.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'PREMIUM',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimary,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final c in locked)
                        _CapabilityRow(capability: c, unlocked: false),
                    ],

                    if (premium) ...[
                      const SizedBox(height: 24),
                      for (final c in locked)
                        _CapabilityRow(capability: c, unlocked: true),
                    ],

                    const SizedBox(height: 20),
                    Text(
                      'No ads, ever. Your meals, weights and workouts stay '
                      'on your device.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Soft close ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  children: [
                    if (!premium)
                      FilledButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PaywallScreen()),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: Text(goal.upgradeCta),
                      ),
                    if (!premium) const SizedBox(height: 4),
                    TextButton(
                      onPressed: onDone,
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: Text(
                        premium ? 'Start' : 'Start free',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumbersCard extends StatelessWidget {
  const _NumbersCard({
    required this.tdee,
    required this.target,
    required this.explainer,
  });

  final double tdee;
  final double target;
  final String explainer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'YOU BURN',
                  value: '${tdee.round()}',
                  unit: 'kcal/day',
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: scheme.onSurface.withValues(alpha: 0.12),
              ),
              Expanded(
                child: _Stat(
                  label: 'YOUR TARGET',
                  value: '${target.round()}',
                  unit: 'kcal/day',
                  emphasised: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            explainer,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.unit,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          label,
          style: text.labelSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: emphasised ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: emphasised ? scheme.primary : null,
          ),
        ),
        Text(
          unit,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.capability, required this.unlocked});

  final AppCapability capability;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: unlocked
                  ? scheme.primary.withValues(alpha: 0.12)
                  : scheme.onSurface.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              capability.icon,
              size: 18,
              color: unlocked ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        capability.title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      unlocked
                          ? Icons.check_circle_rounded
                          : Icons.lock_outline_rounded,
                      size: 14,
                      color:
                          unlocked ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  capability.proof,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
