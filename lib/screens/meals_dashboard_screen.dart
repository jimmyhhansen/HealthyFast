import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/meal_record.dart';
import '../providers/fasting_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/purchase_provider.dart';
import '../widgets/meal_editor.dart';
import '../widgets/settings_action.dart';
import '../widgets/app_bar_title.dart';
import 'meals_screen.dart';
import 'paywall_screen.dart';
import 'profile_wizard_screen.dart';

/// The Meals tab: today's intake against estimated burn, macros, and the
/// day's logged meals. Logging itself lives behind the + button
/// (MealsScreen). Offers the energy-profile wizard on first visit.
class MealsDashboardScreen extends StatefulWidget {
  const MealsDashboardScreen({super.key});

  @override
  State<MealsDashboardScreen> createState() => _MealsDashboardScreenState();
}

class _MealsDashboardScreenState extends State<MealsDashboardScreen> {
  static const _wizardOfferedKey = 'profile_wizard_offered';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferWizard());
  }

  Future<void> _maybeOfferWizard() async {
    if (!mounted) return;
    // The energy profile only makes sense alongside meal logging, which is
    // premium — so the wizard is offered only to premium users.
    if (!context.read<PurchaseProvider>().isPremium) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_wizardOfferedKey) ?? false) return;
    if (!mounted) return;
    if (context.read<ProfileProvider>().isComplete) {
      await prefs.setBool(_wizardOfferedKey, true);
      return;
    }
    await prefs.setBool(_wizardOfferedKey, true);
    if (!mounted) return;

    final start = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set up your energy profile?'),
        content: const Text(
          'Six quick questions estimate your daily calorie burn, so meals '
          'you log show how far under or over you are. Takes under a '
          'minute — stored only on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start'),
          ),
        ],
      ),
    );
    if (start == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileWizardScreen()),
      );
    }
  }

  List<MealRecord> _todaysMeals(List<MealRecord> meals) {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return meals
        .where((m) => m.time.isAfter(dayStart) && m.time.isBefore(dayEnd))
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    final pp = context.watch<ProfileProvider>();
    final scheme = Theme.of(context).colorScheme;

    final meals = _todaysMeals(fp.meals);
    final kcal = meals.fold<double>(0, (s, m) => s + m.calories);
    final protein = meals.fold<double>(0, (s, m) => s + (m.protein ?? 0));
    final carbs = meals.fold<double>(0, (s, m) => s + (m.carbs ?? 0));
    final fat = meals.fold<double>(0, (s, m) => s + (m.fat ?? 0));
    // Daily burn + a low-end estimate for today's workouts — but only in
    // 'per workout' burn mode (weekly mode bakes training into the TDEE).
    final workoutBurn = pp.burnMode == 'workout'
        ? fp.workoutBurnOnDay(DateTime.now())
        : 0;
    final burn =
        pp.effectiveTdee == null ? null : pp.effectiveTdee! + workoutBurn;

    return Scaffold(
      appBar: AppBar(
        title: const HealthyFastTitle(),
        actions: [settingsAction(context)],
      ),
      floatingActionButton: FloatingActionButton(
        // Explicit tag: bottom-nav tab kept mounted via IndexedStack (see
        // root_screen.dart) alongside the other tabs' own FABs, which all
        // share the default hero tag otherwise — causes a "multiple heroes
        // share the same tag" crash-log at runtime (non-fatal but noisy).
        heroTag: 'fab_meals',
        tooltip: 'Log a meal',
        // Theme's primaryContainer (the look the FAB had by default) — the
        // Fast tab's Stop button uses the same, so the two primary actions
        // match. Elevation 0 removes the surfaceTint overlay that would
        // otherwise shift this color slightly relative to FilledButton.
        elevation: 0,
        onPressed: () {
          // Browsing is free; logging a meal (the "+") requires premium.
          if (!context.read<PurchaseProvider>().isPremium) {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PaywallScreen()));
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MealsScreen()),
          );
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
          children: [
            // ── Today: intake vs estimated burn ───────────────────────────
            _card(
              scheme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TODAY',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
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
                          burn == null
                              ? 'kcal logged'
                              : '/ ${burn.round()} kcal daily burn'
                                  '${workoutBurn > 0 ? ' (incl. $workoutBurn workout)' : ''}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (burn != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (kcal / burn).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kcal > burn
                              ? scheme.error
                              : const Color(0xFF1D9E75),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      kcal > burn
                          ? '${(kcal - burn).round()} kcal over estimated burn'
                          : '${(burn - kcal).round()} kcal left of estimated burn',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: kcal > burn
                                ? scheme.error
                                : const Color(0xFF0F6E56),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ] else
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        if (!context.read<PurchaseProvider>().isPremium) {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PaywallScreen()));
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfileWizardScreen()),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.person_outline,
                                size: 18, color: scheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Set up your energy profile to compare '
                                'intake with your daily burn.',
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
            const SizedBox(height: 12),

            // ── Macros ─────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _macroCard(scheme, 'Protein', protein,
                      const Color(0xFF7F77DD)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _macroCard(
                      scheme, 'Carbs', carbs, const Color(0xFF378ADD)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child:
                      _macroCard(scheme, 'Fat', fat, const Color(0xFFEF9F27)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Today's meals ──────────────────────────────────────────────
            Text(
              "TODAY'S MEALS",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
            ),
            const SizedBox(height: 4),
            if (meals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Nothing logged yet today. Tap + to log your first meal.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              for (final m in meals) _mealTile(context, scheme, m),
          ],
        ),
      ),
    );
  }

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

  Widget _macroCard(
      ColorScheme scheme, String label, double grams, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            '${grams.round()}g',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _mealTile(BuildContext context, ColorScheme scheme, MealRecord m) {
    final macros = <String>[
      if (m.protein != null) 'P ${m.protein!.round()}g',
      if (m.carbs != null) 'C ${m.carbs!.round()}g',
      if (m.fat != null) 'F ${m.fat!.round()}g',
    ].join(' · ');
    final fp = context.read<FastingProvider>();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: scheme.tertiaryContainer,
        child: const Icon(Icons.restaurant, size: 18),
      ),
      title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${DateFormat('HH:mm').format(m.time)} · ${m.calories.round()} kcal'
        '${macros.isNotEmpty ? '  ·  $macros' : ''}',
      ),
      // Tap to edit/delete — same editor as the Journal.
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () => showMealEditor(context, fp, m),
    );
  }
}
