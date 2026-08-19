import 'package:flutter/services.dart';

/// Asks the paired Wear OS watch to open this app's Play Store listing
/// so the user can install the companion app on the watch.
class WearInstallService {
  WearInstallService._();

  static const _channel = MethodChannel('healthyfast/wear');

  /// Returns the number of paired watches the request was sent to.
  /// Throws a [PlatformException] on failure.
  static Future<int> installOnWatch() async {
    final count = await _channel.invokeMethod<int>('installOnWatch');
    return count ?? 0;
  }
}
