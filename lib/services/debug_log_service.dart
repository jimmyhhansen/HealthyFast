import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in diagnostic logging, off by default for every user. Enabled by
/// tapping "Version" in Settings 7 times (see settings_screen.dart) — the
/// same discoverability pattern as Android's own developer options, so it
/// doesn't clutter the UI for the people who never need it.
///
/// Built specifically to chase the "meal photo cloud AI silently fails on
/// non-flagship phones" class of bug: MealEstimatorService.describePhoto
/// and CloudAiService._call both swallow most errors into a bare `null`
/// (by design, so a normal user just sees "describe it in text instead"
/// rather than a stack trace) — which also means today there's no way to
/// see *why* a scan failed on a real user's device. Once enabled, the
/// on-device and cloud photo/estimate paths call [log] at each step so a
/// full trace can be pulled off the device and emailed back to us.
///
/// Persisted to a file, not just memory, so a trace survives even if the
/// app is killed right after the failure and before the user gets back to
/// Settings to look at it.
class DebugLogService {
  DebugLogService._();

  static const _enabledKey = 'debug_log_enabled';
  static const _maxLines = 1000;
  static const _fileName = 'debug_log.txt';

  static bool? _enabledCache;
  static File? _fileCache;

  static Future<bool> isEnabled() async {
    if (_enabledCache != null) return _enabledCache!;
    final prefs = await SharedPreferences.getInstance();
    _enabledCache = prefs.getBool(_enabledKey) ?? false;
    return _enabledCache!;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    _enabledCache = value;
    if (value) {
      await log('DebugLog', 'Logging enabled.');
      await _logDeviceInfo();
    }
  }

  /// Device model/manufacturer/OS version is exactly the context needed to
  /// spot a "non-flagship" pattern across multiple users' logs, so it's
  /// captured once per enable rather than left for the user to type in a
  /// bug report.
  static Future<void> _logDeviceInfo() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      await log(
        'Device',
        'brand=${info.brand} model=${info.model} manufacturer=${info.manufacturer} '
            'sdkInt=${info.version.sdkInt} release=${info.version.release}',
      );
    } catch (e) {
      await log('Device', 'could not read device info: $e');
    }
  }

  static Future<File> _file() async {
    if (_fileCache != null) return _fileCache!;
    final dir = await getApplicationDocumentsDirectory();
    _fileCache = File('${dir.path}/$_fileName');
    return _fileCache!;
  }

  /// No-ops instantly (no file I/O) when logging is off, so this is cheap
  /// enough to sprinkle liberally through the AI paths without worrying
  /// about it affecting normal users who never enable it.
  static Future<void> log(String tag, String message) async {
    if (!(await isEnabled())) return;
    final line = '${DateTime.now().toIso8601String()} [$tag] $message';
    debugPrint('[DebugLog]$line');
    try {
      final file = await _file();
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      await _trimIfNeeded(file);
    } catch (e) {
      debugPrint('[DebugLog] could not write to log file: $e');
    }
  }

  /// Keeps the file from growing unbounded over a long debugging session —
  /// keeps only the most recent [_maxLines] lines.
  static Future<void> _trimIfNeeded(File file) async {
    final lines = await file.readAsLines();
    if (lines.length <= _maxLines) return;
    final trimmed = lines.sublist(lines.length - _maxLines);
    await file.writeAsString('${trimmed.join('\n')}\n');
  }

  static Future<String> readAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return '';
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.writeAsString('');
    } catch (_) {}
  }
}
