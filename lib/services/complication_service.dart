import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Asks the Wear OS system to refresh the fasting complications
/// (elapsed / remaining time on the watch face) after a fast starts
/// or stops. No-op on phones, on iOS (no Wear OS channel there), and on
/// errors.
class ComplicationService {
  ComplicationService._();

  static const _channel = MethodChannel('healthyfast/wear');

  static Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('refreshComplications');
    } catch (_) {
      // Phone, or watch face has no fasting complication active — fine.
    }
  }
}
