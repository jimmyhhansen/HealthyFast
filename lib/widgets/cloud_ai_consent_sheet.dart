import 'package:flutter/material.dart';
import '../services/cloud_ai_consent_service.dart';
import '../services/cloud_backup_service.dart';
import '../services/meal_estimator_service.dart' show NanoStatus;

/// Which AI path a screen should use for the next request.
enum AiPath { onDevice, cloud, manual }

/// Single source of truth for "on-device, cloud, or manual" across every
/// AI feature (meal estimate, AI program builder, ...).
///
/// - Nano available and cloud not forced → on-device (default, free,
///   private).
/// - Nano available but "prefer cloud" testing toggle is on AND the user
///   has already consented → cloud, so both paths can be exercised on one
///   device while testing.
/// - Nano unavailable → the normal consent flow: use the stored choice,
///   or ask (see [resolveCloudAiUsage]).
Future<AiPath> resolveAiPath(
  BuildContext context,
  NanoStatus status, {
  String feature = 'this',
}) async {
  if (status == NanoStatus.available) {
    final preferCloud = await CloudAiConsentService.getPreferCloud();
    if (!preferCloud) return AiPath.onDevice;
    final consent = await CloudAiConsentService.get();
    // Never force cloud before the user has actually consented — the
    // testing toggle only switches between two already-approved paths.
    if (consent != CloudAiConsent.accepted) return AiPath.onDevice;
    if (!context.mounted) return AiPath.onDevice;
    // Cloud AI requires a real Google sign-in (see ensureCloudSignIn) —
    // on-device is still a perfectly good fallback here since we know
    // Nano is available in this branch.
    final signedIn = await ensureCloudSignIn(context);
    return signedIn ? AiPath.cloud : AiPath.onDevice;
  }
  final useCloud = await resolveCloudAiUsage(context, feature: feature);
  return useCloud ? AiPath.cloud : AiPath.manual;
}

/// Cloud AI requires a real (non-anonymous) Google sign-in — see
/// CloudAiService._ensureSignedIn, and the matching server-side check in
/// functions/index.js's generateAiText. Reuses Cloud Backup's Google
/// Sign-In flow rather than a separate account system: signing in here
/// does NOT turn on Cloud Backup itself (that's still the explicit toggle
/// in Settings → Cloud & AI), it only establishes the account identity
/// Cloud AI's abuse-prevention quota is keyed on.
///
/// Every AI-capable screen is already Premium-gated, so this doesn't add
/// friction for a free tier that never reaches it.
Future<bool> ensureCloudSignIn(BuildContext context) async {
  if (CloudBackupService.instance.isSignedIn) return true;
  try {
    await CloudBackupService.instance.signIn();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Google sign-in is required for Cloud AI: $e')),
      );
    }
    return false;
  }
}

/// Shows the one-time (well — until they change their mind in Settings)
/// consent sheet for sending AI prompts to Google's cloud Gemini API on
/// phones that can't run Gemini Nano on-device. Returns:
///  - true  → user tapped "Turn on cloud AI"
///  - false → user tapped "Enter manually"
///  - null  → dismissed without choosing (swipe/tap outside) — treated as
///            "not now" for this one request, but NOT persisted as a
///            decline, so they're asked again next time.
///
/// [upsell] switches the copy: when true, this isn't explaining why
/// on-device AI is unavailable — it's offering cloud AI as a paid upgrade
/// for more accurate results on phones that already have on-device AI.
Future<bool?> showCloudAiConsentSheet(BuildContext context,
    {String feature = 'this', bool upsell = false}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _CloudAiConsentSheet(feature: feature, upsell: upsell),
  );
}

/// Resolves whether to use cloud AI for this request: checks the stored
/// choice first, and only shows the sheet the first time. Only call this
/// when on-device Gemini Nano has already been confirmed unavailable.
Future<bool> resolveCloudAiUsage(BuildContext context, {String feature = 'this'}) async {
  final consent = await CloudAiConsentService.get();
  if (consent == CloudAiConsent.accepted) {
    if (!context.mounted) return false;
    return ensureCloudSignIn(context);
  }
  if (consent == CloudAiConsent.declined) return false;
  if (!context.mounted) return false;
  final choice = await showCloudAiConsentSheet(context, feature: feature);
  if (choice != null) {
    await CloudAiConsentService.set(
        choice ? CloudAiConsent.accepted : CloudAiConsent.declined);
  }
  if (choice != true) return false;
  if (!context.mounted) return false;
  return ensureCloudSignIn(context);
}

class _CloudAiConsentSheet extends StatelessWidget {
  const _CloudAiConsentSheet({required this.feature, this.upsell = false});
  final String feature;
  final bool upsell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    upsell ? Icons.auto_awesome_rounded : Icons.cloud_outlined,
                    color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    upsell
                        ? 'Try smarter cloud AI'
                        : 'This phone can\'t run AI on-device',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              upsell
                  ? 'Your phone can already run AI on-device — but Google\'s '
                      'full-size cloud model is more capable and gives more '
                      'accurate results, especially for longer or more '
                      'detailed $feature.'
                  : 'Your phone unfortunately doesn\'t support Google\'s '
                      'private on-device AI (Gemini Nano) — it only runs on '
                      'select flagship phones.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              upsell
                  ? 'Turning this on means:'
                  : 'To still get AI help with $feature, cloud AI must be '
                      'turned on. This means:',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
            ),
            const SizedBox(height: 8),
            _bullet(context,
                'The text you type or dictate — or the meal photo you '
                'scan — is sent to Google\'s Gemini API for processing.'),
            _bullet(context,
                'Google does not use this text to train their models — it\'s '
                'processed via Vertex AI, not the free consumer tier.'),
            _bullet(context,
                'Requires signing in with your Google account, so we can '
                'stop the shared AI quota from being abused — no health '
                'data or other logs are sent.'),
            _bullet(context,
                upsell
                    ? 'Applies to every AI feature (meal estimates and AI '
                        'programs), on every device — you can turn it off '
                        'again anytime in Settings → Cloud & AI.'
                    : 'You can turn this off again anytime in Settings → '
                        'Cloud & AI.'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(upsell ? 'Not now' : 'Enter manually'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(upsell ? 'Use smarter AI' : 'Turn on cloud AI'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
