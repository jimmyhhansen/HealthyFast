import 'package:shared_preferences/shared_preferences.dart';

/// Whether the user has agreed to send AI prompts (meal descriptions,
/// workout requests) to Google's cloud Gemini API when on-device Gemini
/// Nano isn't available on their phone. Never defaults to "on" — this is
/// always an explicit, informed choice (see CloudAiConsentSheet).
enum CloudAiConsent { notAsked, accepted, declined }

class CloudAiConsentService {
  CloudAiConsentService._();

  static const _key = 'cloud_ai_consent';
  static const _preferKey = 'cloud_ai_prefer';

  static Future<CloudAiConsent> get() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_key)) {
      'accepted' => CloudAiConsent.accepted,
      'declined' => CloudAiConsent.declined,
      _ => CloudAiConsent.notAsked,
    };
  }

  static Future<void> set(CloudAiConsent consent) async {
    final prefs = await SharedPreferences.getInstance();
    switch (consent) {
      case CloudAiConsent.accepted:
        await prefs.setString(_key, 'accepted');
      case CloudAiConsent.declined:
        await prefs.setString(_key, 'declined');
      case CloudAiConsent.notAsked:
        await prefs.remove(_key);
    }
  }

  /// "Always use cloud AI" — a premium upsell, not just a fallback: forces
  /// cloud AI even on phones where on-device Nano is available, for users
  /// who want Google's more capable cloud model instead. Gated behind
  /// PurchaseProvider.isPremium and only takes effect once cloud AI has
  /// been consented to (see [get]) — exposed as a toggle in Settings →
  /// Cloud & AI (see CloudAiSettingsScreen).
  static Future<bool> getPreferCloud() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_preferKey) ?? false;
  }

  static Future<void> setPreferCloud(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_preferKey, value);
  }
}
