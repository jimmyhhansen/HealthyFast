import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/fasting_provider.dart';
import '../providers/purchase_provider.dart';
import '../services/cloud_ai_consent_service.dart';
import '../services/cloud_backup_service.dart';
import '../services/health_sync_service.dart';
import '../services/meal_estimator_service.dart';
import '../widgets/cloud_ai_consent_sheet.dart';
import 'paywall_screen.dart';

class CloudAiSettingsScreen extends StatefulWidget {
  const CloudAiSettingsScreen({super.key});

  @override
  State<CloudAiSettingsScreen> createState() => _CloudAiSettingsScreenState();
}

class _CloudAiSettingsScreenState extends State<CloudAiSettingsScreen> {
  bool _healthSyncEnabled = false;
  bool _healthBusy = false;
  NanoStatus _nanoStatus = NanoStatus.unavailable;
  bool _nanoBusy = false;
  bool _importBusy = false;
  bool _cloudEnabled = false;
  bool _cloudBusy = false;
  String? _cloudEmail;

  CloudAiConsent _cloudAiConsent = CloudAiConsent.notAsked;
  bool _preferCloud = false;

  @override
  void initState() {
    super.initState();
    HealthSyncService.isEnabled().then((v) {
      if (mounted) setState(() => _healthSyncEnabled = v);
    });
    _refreshCloud();
    MealEstimatorService.checkStatus().then((s) {
      if (mounted) setState(() => _nanoStatus = s);
    });
    _refreshCloudAiConsent();
  }

  Future<void> _refreshCloudAiConsent() async {
    final consent = await CloudAiConsentService.get();
    final prefer = await CloudAiConsentService.getPreferCloud();
    if (mounted) {
      setState(() {
        _cloudAiConsent = consent;
        _preferCloud = prefer;
      });
    }
  }

  Future<void> _refreshCloud() async {
    final enabled = await CloudBackupService.instance.isEnabled();
    if (!mounted) return;
    setState(() {
      _cloudEnabled = enabled && CloudBackupService.instance.isSignedIn;
      _cloudEmail = CloudBackupService.instance.accountEmail;
    });
  }

  /// Platform-neutral name for the phone's health app — "Health Connect" on
  /// Android, "Apple Health" on iOS (the `health` package backs both under
  /// one API).
  String get _healthAppName =>
      Platform.isAndroid ? 'Health Connect' : 'Apple Health';

  String get _nanoSubtitle => switch (_nanoStatus) {
        NanoStatus.available => 'Ready — powers meal estimates and voice logging',
        NanoStatus.downloadable => 'Tap to download the on-device AI model',
        NanoStatus.downloading => 'Model is downloading…',
        NanoStatus.unavailable => 'Not supported on this phone',
      };

  Future<void> _handleNanoTap() async {
    if (_nanoStatus == NanoStatus.available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meal AI is ready.')));
      return;
    }
    if (_nanoStatus != NanoStatus.downloadable || _nanoBusy) return;
    setState(() => _nanoBusy = true);
    final ok = await MealEstimatorService.downloadModel();
    final status = await MealEstimatorService.checkStatus();
    if (!mounted) return;
    setState(() {
      _nanoBusy = false;
      _nanoStatus = status;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Meal AI downloaded.' : 'Download failed.')));
  }

  Future<void> _toggleHealthSync(bool value) async {
    if (!context.read<PurchaseProvider>().isPremium) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }
    setState(() => _healthBusy = true);
    if (value) {
      final granted = await HealthSyncService.enable();
      if (mounted) {
        setState(() {
          _healthSyncEnabled = granted;
          _healthBusy = false;
        });
      }
    } else {
      await HealthSyncService.disable();
      if (mounted) {
        setState(() {
          _healthSyncEnabled = false;
          _healthBusy = false;
        });
      }
    }
  }

  Future<void> _importFromHealth() async {
    if (!context.read<PurchaseProvider>().isPremium) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }
    setState(() => _importBusy = true);
    final granted = await HealthSyncService.ensureReadPermissions();
    if (!granted) {
      if (mounted) setState(() => _importBusy = false);
      return;
    }
    if (!mounted) return;
    final fp = context.read<FastingProvider>();
    final meals = await fp.importMealsFromHealth();
    final weights = await fp.importWeightsFromHealth();
    final workouts = await fp.importWorkoutsFromHealth();
    if (!mounted) return;
    setState(() => _importBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Imported $meals meals, $weights weights and $workouts workouts.')));
  }

  /// Turns "Always use cloud AI" on/off. This is the premium upsell path —
  /// unlike the plain fallback (below), it applies even on phones that
  /// already have on-device AI. Requires premium, and requires consent
  /// (asked with the sell-oriented copy — see showCloudAiConsentSheet's
  /// `upsell` flag) before it can be switched on for the first time.
  Future<void> _handleAlwaysCloudToggle(bool value) async {
    if (!context.read<PurchaseProvider>().isPremium) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }
    if (value) {
      var consent = _cloudAiConsent;
      if (consent != CloudAiConsent.accepted) {
        final accept = await showCloudAiConsentSheet(context,
            feature: 'meal estimates and AI programs', upsell: true);
        if (accept != true) return;
        await CloudAiConsentService.set(CloudAiConsent.accepted);
      }
      if (!mounted) return;
      final signedIn = await ensureCloudSignIn(context);
      if (!signedIn) return;
      await CloudAiConsentService.setPreferCloud(true);
    } else {
      await CloudAiConsentService.setPreferCloud(false);
    }
    await _refreshCloudAiConsent();
  }

  /// Shared by the "Change" button and the first-time tap on the Cloud AI
  /// row. Accepting requires a real Google sign-in (see ensureCloudSignIn)
  /// before the consent is actually recorded as accepted — otherwise a
  /// user could accept here, then hit CloudAiService's sign-in assertion
  /// on their very next request with no clear way back to this screen.
  Future<void> _changeCloudAiConsent() async {
    final accept = await showCloudAiConsentSheet(context);
    if (accept == null) return;
    if (accept) {
      if (!mounted) return;
      final signedIn = await ensureCloudSignIn(context);
      if (!signedIn) return;
    }
    await CloudAiConsentService.set(
        accept ? CloudAiConsent.accepted : CloudAiConsent.declined);
    await _refreshCloudAiConsent();
  }

  Future<void> _toggleCloud(bool value) async {
    if (!context.read<PurchaseProvider>().isPremium) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
      return;
    }
    final fp = context.read<FastingProvider>();
    setState(() => _cloudBusy = true);
    try {
      if (value) {
        if (Platform.isIOS) {
          final provider = await _chooseSignInProvider();
          if (provider == null) return;
          if (provider == 'apple') {
            await CloudBackupService.instance.signInWithApple();
          } else {
            await CloudBackupService.instance.signIn();
          }
        } else {
          await CloudBackupService.instance.signIn();
        }
        await CloudBackupService.instance.backupNow(fp);
      } else {
        await CloudBackupService.instance.signOut();
      }
    } catch (e) {
      // Previously uncaught: signInWithApple() (or signIn()) throwing here
      // — e.g. the still-unresolved firebase_auth/invalid-credential case —
      // propagated past this function with no `catch`, so in a release
      // build (TestFlight, no attached debugger) it just looked like
      // nothing happened after Face ID. Surface it instead.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not turn on Cloud Backup: $e')),
        );
      }
    } finally {
      await _refreshCloud();
      if (mounted) setState(() => _cloudBusy = false);
    }
  }

  /// Google/Apple picker shown before sign-in on iOS (Apple requires this
  /// choice wherever Google sign-in is offered — App Store Review Guideline
  /// 4.8). Returns 'google', 'apple', or null if dismissed.
  Future<String?> _chooseSignInProvider() {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.g_mobiledata_rounded),
              title: const Text('Continue with Google'),
              onTap: () => Navigator.pop(ctx, 'google'),
            ),
            ListTile(
              leading: const Icon(Icons.apple_rounded),
              title: const Text('Continue with Apple'),
              onTap: () => Navigator.pop(ctx, 'apple'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Distinct from [_toggleCloud]'s "off" path: turning the switch off
  /// only disconnects the account (data stays in the cloud in case the
  /// user reconnects). This is the explicit, confirmed action that
  /// actually erases what was uploaded — see CloudBackupService.deleteCloudData.
  Future<void> _deleteCloudData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete cloud backup data?'),
        content: const Text(
            'This permanently deletes your fasts, meals, weights and '
            'workouts stored in the cloud. Data on this device is not '
            'affected. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _cloudBusy = true);
    try {
      await CloudBackupService.instance.deleteCloudData();
      await CloudBackupService.instance.signOut();
    } finally {
      await _refreshCloud();
      if (mounted) setState(() => _cloudBusy = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud backup data deleted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud & AI')),
      body: ListView(
        children: [
          if (Platform.isAndroid) ...[
            _sectionLabel('On-device AI'),
            ListTile(
              leading: _nanoBusy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.auto_awesome, color: _nanoStatus == NanoStatus.available ? Colors.green : null),
              title: const Text('Meal AI'),
              subtitle: Text(_nanoSubtitle),
              trailing: _nanoStatus == NanoStatus.available ? const Icon(Icons.check_circle, color: Colors.green) : null,
              onTap: _handleNanoTap,
            ),
            const Divider(),
          ],
          _sectionLabel('Cloud AI'),
          ListTile(
            leading: Icon(Icons.cloud_outlined,
                color: _cloudAiConsent == CloudAiConsent.accepted ? Colors.green : null),
            title: const Text('Cloud AI'),
            // Framed by what the user gets, not by which engine failed.
            // "Fallback" tells them about our plumbing, not their benefit.
            subtitle: Text(switch (_cloudAiConsent) {
              CloudAiConsent.accepted =>
                'On — sharper meal estimates and AI programs',
              CloudAiConsent.declined =>
                'Off — estimates stay on this device only',
              CloudAiConsent.notAsked =>
                'Want more accurate results? Turn on Cloud AI',
            }),
            trailing: _cloudAiConsent == CloudAiConsent.notAsked
                ? null
                : TextButton(
                    onPressed: () => _changeCloudAiConsent(),
                    child: const Text('Change'),
                  ),
            onTap: _cloudAiConsent == CloudAiConsent.notAsked
                ? () => _changeCloudAiConsent()
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_rounded),
            title: const Text('Always use cloud AI'),
            subtitle: const Text(
                'Use Google\'s most accurate model for every estimate, on '
                'any phone (Premium)'),
            value: _preferCloud,
            onChanged: _handleAlwaysCloudToggle,
          ),
          const Divider(),
          _sectionLabel(_healthAppName),
          SwitchListTile(
            secondary: const Icon(Icons.favorite_outline),
            title: Text('Sync to $_healthAppName'),
            subtitle: Text('Mirror logs to $_healthAppName'),
            value: _healthSyncEnabled,
            onChanged: _healthBusy ? null : _toggleHealthSync,
          ),
          ListTile(
            leading: _importBusy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
            title: Text('Fetch from $_healthAppName'),
            subtitle: const Text('Import logs from other apps'),
            onTap: _importBusy ? null : _importFromHealth,
          ),
          const Divider(),
          _sectionLabel('Cloud Backup'),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Cloud backup'),
            subtitle: Text(_cloudEnabled && _cloudEmail != null ? 'On · $_cloudEmail' : 'Back up data to your Google account'),
            value: _cloudEnabled,
            onChanged: _cloudBusy ? null : _toggleCloud,
          ),
          if (_cloudEnabled) ...[
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Back up now'),
              onTap: _cloudBusy ? null : () async {
                setState(() => _cloudBusy = true);
                await CloudBackupService.instance.backupNow(context.read<FastingProvider>());
                if (mounted) setState(() => _cloudBusy = false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('Restore from cloud'),
              onTap: _cloudBusy ? null : () async {
                setState(() => _cloudBusy = true);
                await CloudBackupService.instance.restoreNow(context.read<FastingProvider>());
                if (mounted) setState(() => _cloudBusy = false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete cloud backup data',
                  style: TextStyle(color: Colors.red)),
              subtitle: const Text(
                  'Permanently removes your backed-up data from the cloud'),
              onTap: _cloudBusy ? null : () => _deleteCloudData(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
        ),
      );
}
