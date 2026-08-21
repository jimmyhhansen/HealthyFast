import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// Asks the paired Wear OS watch to open this app's Play Store listing
/// so the user can install the companion app on the watch.
///
/// Android/Wear OS only — the "Install on Watch" row is hidden on iOS (see
/// settings_screen.dart), and this guard is a second line of defense.
class WearInstallService {
  WearInstallService._();

  static const _channel = MethodChannel('healthyfast/wear');

  /// Returns the number of paired watches the request was sent to.
  /// Throws a [PlatformException] on failure. Returns 0 on iOS.
  static Future<int> installOnWatch() async {
    if (!Platform.isAndroid) return 0;
    final count = await _channel.invokeMethod<int>('installOnWatch');
    return count ?? 0;
  }
}
