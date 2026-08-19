import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/debug_log_service.dart';

/// Only reachable via the hidden 7-tap gesture on "Version" in Settings
/// (see settings_screen.dart) — not a normal part of the app's navigation.
class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({super.key});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  String _log = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final text = await DebugLogService.readAll();
    if (!mounted) return;
    setState(() {
      _log = text;
      _loading = false;
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(
        ClipboardData(text: _log.isEmpty ? '(log is empty)' : _log));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log copied to clipboard')),
      );
    }
  }

  /// Mailto bodies are unreliable past a couple thousand characters across
  /// mail apps, so this sends the most recent slice. Copy above is the
  /// reliable way to get the whole thing into a bug report.
  Future<void> _emailLog() async {
    final info = await PackageInfo.fromPlatform();
    const maxChars = 3000;
    final body = _log.length > maxChars
        ? '…(truncated — use Copy for the full log)…\n'
            '${_log.substring(_log.length - maxChars)}'
        : _log;
    final uri = Uri(
      scheme: 'mailto',
      path: 'northernappdev@gmail.com',
      query: Uri(queryParameters: {
        'subject': 'HealthyFast debug log',
        'body': 'v${info.version} (${info.buildNumber})\n\n$body',
      }).query,
    );
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found — use Copy instead.')),
      );
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear log?'),
        content: const Text(
            'This deletes the on-device debug log. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    await DebugLogService.clear();
    await _load();
  }

  Future<void> _disable() async {
    await DebugLogService.setEnabled(false);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy log',
            onPressed: _log.isEmpty ? null : _copy,
          ),
          IconButton(
            icon: const Icon(Icons.mail_outline_rounded),
            tooltip: 'Email log',
            onPressed: _log.isEmpty ? null : _emailLog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Clear log',
            onPressed: _log.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _log.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No log entries yet. Try scanning a meal '
                              'photo, then come back here.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: SelectableText(
                            _log,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Disable debug logging'),
                      onPressed: _disable,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
