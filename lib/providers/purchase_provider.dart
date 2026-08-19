import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Premium entitlement via Google Play Billing.
///
/// Two ways to unlock premium:
///  - [yearlyId]: yearly subscription (200 NOK/year)
///  - [monthlyId]: monthly subscription (25 NOK/month)
///
/// Both product IDs must be created in Play Console with matching IDs.
/// Free tier: fasting timer, zones, notifications and basic journal.
/// Premium: AI meal logging, stats, Wear OS sync, Health Connect.
class PurchaseProvider extends ChangeNotifier {
  static const String yearlyId = 'healthyfast_yearly';
  static const String monthlyId = 'healthyfast_monthly';

  /// True only when the app is built with --dart-define=TESTER_BUILD=true.
  /// Lets internal testers skip the paywall. Production builds omit the
  /// flag, so the hard paywall stays intact for real users.
  static const bool kTesterBuild = bool.fromEnvironment('TESTER_BUILD');

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool _isPremium = false;
  bool _loading = false;
  bool _storeAvailable = false;
  String? _error;
  ProductDetails? _yearly;
  ProductDetails? _monthly;

  bool get isPremium => _isPremium;
  bool get loading => _loading;
  bool get storeAvailable => _storeAvailable;
  String? get error => _error;

  /// Store-localized price strings; null until products load.
  String? get yearlyPrice => _yearly?.price;
  String? get monthlyPrice => _monthly?.price;

  Future<void> init() async {
    // Cached entitlement so the app opens instantly for paying users.
    final prefs = await SharedPreferences.getInstance();
    _isPremium = prefs.getBool('is_premium') ?? false;
    notifyListeners();

    _sub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        _error = e.toString();
        _loading = false;
        notifyListeners();
      },
    );

    try {
      _storeAvailable = await _iap.isAvailable();
      if (_storeAvailable) {
        final resp =
            await _iap.queryProductDetails({yearlyId, monthlyId});
        for (final p in resp.productDetails) {
          if (p.id == yearlyId) _yearly = p;
          if (p.id == monthlyId) _monthly = p;
        }
        // Refresh entitlement from the store (emits on purchaseStream).
        await _iap.restorePurchases();
      }
    } catch (e) {
      debugPrint('PurchaseProvider.init failed: $e');
    }
    notifyListeners();
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.productID == yearlyId || p.productID == monthlyId) {
            await _setPremium(true);
          }
        case PurchaseStatus.error:
          _error = p.error?.message ?? 'Purchase failed';
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> _setPremium(bool value) async {
    _isPremium = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', value);
  }

  /// Yearly subscription, 200 NOK/year.
  Future<void> buyYearly() => _buy(_yearly);

  /// Monthly subscription, 25 NOK/month.
  Future<void> buyMonthly() => _buy(_monthly);

  Future<void> _buy(ProductDetails? product) async {
    if (product == null) {
      _error = _storeAvailable
          ? 'Product not available yet. Try again later.'
          : 'Google Play is not available on this device.';
      notifyListeners();
      return;
    }
    _error = null;
    _loading = true;
    notifyListeners();
    try {
      // Subscriptions and non-consumables both use buyNonConsumable.
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> restore() async {
    _error = null;
    _loading = true;
    notifyListeners();
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  /// Unlocks the app in debug builds or tester builds, for development
  /// and internal testing. No-op in production builds.
  Future<void> debugUnlock() async {
    if (!kDebugMode && !kTesterBuild) return;
    await _setPremium(true);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
