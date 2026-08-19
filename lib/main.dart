import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'models/fast_record.dart';
import 'models/meal_record.dart';
import 'models/weight_record.dart';
import 'models/workout_record.dart';
import 'providers/fasting_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/purchase_provider.dart';
import 'providers/training_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/root_screen.dart';
import 'screens/watch_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/watch_sync_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> _initHive() async {
  await Hive.initFlutter();
  Hive.registerAdapter(FastRecordAdapter());
  Hive.registerAdapter(MealRecordAdapter());
  Hive.registerAdapter(WeightRecordAdapter());
  Hive.registerAdapter(WorkoutRecordAdapter());
  await Hive.openBox<FastRecord>('fasts');
  await Hive.openBox<MealRecord>('meals');
  await Hive.openBox<WeightRecord>('weights');
  await Hive.openBox<WorkoutRecord>('workouts');
}

/// True when the welcome flow should run before the app opens.
///
/// Only genuinely new installs see it: anyone who already has a profile or
/// a logged fast is silently marked as onboarded, so an app update never
/// drops an existing user back into a setup wizard.
Future<bool> _needsWelcome() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(ProfileProvider.kOnboardingDone) ?? false) return false;

  final existingUser = prefs.containsKey('profile_age') ||
      Hive.box<FastRecord>('fasts').isNotEmpty;
  if (existingUser) {
    await prefs.setBool(ProfileProvider.kOnboardingDone, true);
    return false;
  }
  return true;
}

/// Detects whether we're running on a Wear OS watch.
Future<bool> _detectWatch() async {
  if (!Platform.isAndroid) return false;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return info.systemFeatures.contains('android.hardware.type.watch');
  } catch (_) {
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = await Future.wait([_initHive(), _detectWatch()]);
  final isWatch = results[1] as bool;

  // Hive must be open before this — it inspects the fasts box.
  final showWelcome = isWatch ? false : await _needsWelcome();

  // Firebase powers the premium cloud sync (phone only). Best-effort:
  // failure must never block app start.
  if (!isWatch) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase init failed: $e');
    }
  }

  await NotificationService.init();

  final fastingProvider = FastingProvider();
  final profileProvider = ProfileProvider();
  final trainingProvider = TrainingProvider();
  unawaited(profileProvider.init());
  unawaited(trainingProvider.init());
  unawaited(fastingProvider.init().then((_) =>
      WatchSyncService(fastingProvider, profileProvider, trainingProvider)
          .init()));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PurchaseProvider()..init()),
        ChangeNotifierProvider.value(value: profileProvider),
        ChangeNotifierProvider.value(value: trainingProvider),
        ChangeNotifierProvider.value(value: fastingProvider),
      ],
      child: HealthyFastApp(isWatch: isWatch, showWelcome: showWelcome),
    ),
  );
}

class HealthyFastApp extends StatelessWidget {
  const HealthyFastApp({
    super.key,
    this.isWatch = false,
    this.showWelcome = false,
  });

  final bool isWatch;
  final bool showWelcome;

  @override
  Widget build(BuildContext context) {
    // Freemium: the app itself is always open (timer, zones, basic journal).
    // Premium features gate themselves and push the PaywallScreen.
    return MaterialApp(
      title: 'HealthyFast',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: isWatch
          ? const WatchScreen()
          : showWelcome
              ? const WelcomeScreen()
              : const RootScreen(),
    );
  }
}
