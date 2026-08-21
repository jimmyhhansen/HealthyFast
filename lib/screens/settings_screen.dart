import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/purchase_provider.dart';
import '../services/debug_log_service.dart';
import '../services/notification_service.dart';
import '../services/wear_install_service.dart';

import 'cloud_ai_settings_screen.dart';
import 'debug_log_screen.dart';
import 'general_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'paywall_screen.dart';
import 'workout_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _feedbackEmail = 'northernappdev@gmail.com';

  bool _debugLogEnabled = false;
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  /// Hidden gesture — mirrors Android's own "tap build number 7 times"
  /// pattern. Taps more than 2s apart don't accumulate, so casually
  /// tapping Version a couple of times over a session can't trigger it
  /// by accident.
  Future<void> _handleVersionTap() async {
    final now = DateTime.now();
    if (_lastVersionTap == null ||
        now.difference(_lastVersionTap!) > const Duration(seconds: 2)) {
      _versionTapCount = 0;
    }
    _lastVersionTap = now;
    _versionTapCount++;
    if (_versionTapCount < 7) return;
    _versionTapCount = 0;

    final newValue = !_debugLogEnabled;
    await DebugLogService.setEnabled(newValue);
    if (!mounted) return;
    setState(() => _debugLogEnabled = newValue);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newValue
            ? 'Debug logging enabled — see "Debug log" below'
            : 'Debug logging disabled'),
      ),
    );
  }

  /// Prefilled with the version/build so bug reports arrive with the
  /// context needed to reproduce, without asking the user to dig for it.
  Future<void> _sendFeedback() async {
    final info = await PackageInfo.fromPlatform();
    final uri = Uri(
      scheme: 'mailto',
      path: _feedbackEmail,
      query: Uri(queryParameters: {
        'subject': 'HealthyFast feedback',
        'body': '\n\n—\nv${info.version} (${info.buildNumber})',
      }).query,
    );
    try {
      final opened = await launchUrl(uri);
      if (!opened && mounted) {
        _showNoMailAppDialog();
      }
    } catch (_) {
      if (mounted) _showNoMailAppDialog();
    }
  }

  void _showNoMailAppDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No email app found'),
        content: const Text(
          'You can reach us directly at $_feedbackEmail.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Request notification permissions on app start or settings entry
    NotificationService.requestPermissions();
    DebugLogService.isEnabled().then((v) {
      if (mounted) setState(() => _debugLogEnabled = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<PurchaseProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('General settings'),
            subtitle: const Text('Units, energy profile and personal info'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GeneralSettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.fitness_center_rounded),
            title: const Text('Workout settings'),
            subtitle: const Text('Manage programs, exercises and bulk import'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WorkoutSettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Cloud & AI'),
            subtitle: Text(Platform.isAndroid
                ? 'Backup, Health Connect and Meal AI'
                : 'Backup, Apple Health and Cloud AI'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CloudAiSettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Fasting milestone alerts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              );
            },
          ),
          if (Platform.isAndroid) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.watch_rounded),
              title: const Text('Install on Watch'),
              subtitle: const Text('Open Play Store on your paired Wear OS watch'),
              trailing: const Icon(Icons.open_in_new_rounded, size: 20),
              onTap: () async {
                // Wear OS sync is a premium feature.
                if (!context.read<PurchaseProvider>().isPremium) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PaywallScreen()),
                  );
                  return;
                }
                try {
                  final count = await WearInstallService.installOnWatch();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(count > 0 ? 'Notification sent' : 'No paired watches found'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to open Play Store: $e')),
                    );
                  }
                }
              },
            ),
          ],
          const Divider(),
          ListTile(
            leading: Icon(Icons.workspace_premium, color: pp.isPremium ? Colors.amber : null),
            title: const Text('HealthyFast Premium'),
            subtitle: Text(pp.isPremium ? 'Active — thank you for supporting the app!' : 'Not active'),
            trailing: pp.isPremium ? const Icon(Icons.check_circle, color: Colors.green) : null,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore Purchases'),
            onTap: () async {
              await pp.restore();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Purchases restored')),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.star_outline_rounded),
            title: Text(Platform.isAndroid ? 'Rate on Google Play' : 'Rate on the App Store'),
            subtitle: const Text('HealthyFast is an indie project — your review means a lot!'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 20),
            onTap: () async {
              try {
                if (await InAppReview.instance.isAvailable()) {
                  await InAppReview.instance.openStoreListing();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not open store listing: $e')),
                  );
                }
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.mail_outline_rounded),
            title: const Text('Send feedback'),
            subtitle: const Text(
                'Want to send suggestions or report errors? I would love '
                'to hear from you!'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 20),
            onTap: _sendFeedback,
          ),
          if (_debugLogEnabled) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Debug log'),
              subtitle: const Text('Diagnostic trace for AI/cloud sync issues'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final disabled = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const DebugLogScreen()),
                );
                if (disabled == true && mounted) {
                  setState(() => _debugLogEnabled = false);
                }
              },
            ),
          ],
          const Divider(),
          // Read from the build itself so it can never go stale again.
          // Tapping this 7 times toggles the hidden debug log (see
          // _handleVersionTap) — same discoverability pattern as Android's
          // own "tap build number to enable developer options".
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final info = snap.data;
              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                trailing: Text(
                  info == null ? '…' : '${info.version} (${info.buildNumber})',
                ),
                onTap: _handleVersionTap,
              );
            },
          ),
        ],
      ),
    );
  }
}
