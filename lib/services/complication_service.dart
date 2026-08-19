import 'package:flutter/services.dart';

/// Asks the Wear OS system to refresh the fasting complications
/// (elapsed / remaining time on the watch face) after a fast starts
/// or stops. No-op on phones and on errors.
class ComplicationService {
  ComplicationService._();

  static const _channel = MethodChannel('healthyfast/wear');

  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod('refreshComplications');
    } catch (_) {
      // Phone, or watch face has no fasting complication active — fine.
    }
  }
}
