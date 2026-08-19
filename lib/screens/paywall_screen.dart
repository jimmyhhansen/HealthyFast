import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fitness_goal.dart';
import '../providers/profile_provider.dart';
import '../providers/purchase_provider.dart';

/// Premium upsell. Shown contextually when a free user opens a premium
/// feature (Meals, Stats, Wear OS, Health Connect). The fasting timer,
/// zones, notifications and basic journal are always free. No ads, ever.
///
/// The feature list is generated from [kCapabilities] rather than written
/// here, so onboarding and the paywall can never promise different things.
/// Capabilities matching the user's chosen goal are listed first — the same
/// personalisation the welcome flow uses.
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<PurchaseProvider>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final canPop = Navigator.of(context).canPop();

    // Premium capabilities, the ones matching their goal first.
    final goal = context.watch<ProfileProvider>().goal;
    final premiumCaps = kCapabilities.where((c) => c.premium).toList()
      ..sort((a, b) {
        final am = a.matches(goal) ? 0 : 1;
        final bm = b.matches(goal) ? 0 : 1;
        return am.compareTo(bm);
      });

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canPop)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                const SizedBox(height: 8),
                Icon(Icons.workspace_premium_rounded,
                    size: 64, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  'HealthyFast Premium',
                  textAlign: TextAlign.center,
                  style: text.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'The fasting timer — all types — is free. '
                  'Premium unlocks everything else. No ads, ever.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                for (final c in premiumCaps)
                  _Feature(
                    icon: c.icon,
                    title: c.title,
                    label: c.proof,
                  ),
                const SizedBox(height: 24),
                _PlanCard(
                  highlighted: true,
                  title: 'Yearly',
                  price: '${pp.yearlyPrice ?? 'kr 200.00'} / year',
                  subtitle: 'Under kr 17/month · Cancel anytime',
                  badge: 'BEST VALUE',
                  onTap: pp.loading ? null : pp.buyYearly,
                ),
                const SizedBox(height: 12),
                _PlanCard(
                  highlighted: false,
                  title: 'Monthly',
                  price: '${pp.monthlyPrice ?? 'kr 25.00'} / month',
                  subtitle: 'Cancel anytime in Google Play',
                  onTap: pp.loading ? null : pp.buyMonthly,
                ),
                const SizedBox(height: 16),
                if (pp.loading)
                  const Center(child: CircularProgressIndicator()),
                if (pp.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      pp.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                  ),
                TextButton(
                  onPressed: pp.loading ? null : pp.restore,
                  child: const Text('Restore purchases'),
                ),
                // Kun synlig i debug- og tester-bygg (TESTER_BUILD=true).
                // debugUnlock er uansett no-op i produksjonsbygg.
                if (kDebugMode || PurchaseProvider.kTesterBuild)
                  TextButton(
                    onPressed: pp.debugUnlock,
                    child: const Text('LÅS OPP FOR TESTING (BYPASS)'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String title;
  final String label;
  const _Feature({
    required this.icon,
    required this.title,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
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

class _PlanCard extends StatelessWidget {
  final bool highlighted;
  final String title, price, subtitle;
  final String? badge;
  final VoidCallback? onTap;

  const _PlanCard({
    required this.highlighted,
    required this.title,
    required this.price,
    required this.subtitle,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: highlighted ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onPrimary),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                price,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
