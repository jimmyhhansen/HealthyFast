import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/fasting_provider.dart';
import 'home_screen.dart';
import 'meals_dashboard_screen.dart';
import 'train_screen.dart';
import 'journal_screen.dart';
import '../services/notification_service.dart';

class RootScreen extends StatefulWidget {
  final int initialIndex;
  const RootScreen({super.key, this.initialIndex = 0});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen>
    with WidgetsBindingObserver {
  late int _index;
  String? _targetZone;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    WidgetsBinding.instance.addObserver(this);
    // Prompt for notification permissions as soon as the user enters the app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.requestPermissions();
    });

    NotificationService.selectNotificationStream.stream.listen((payload) {
      if (payload == null) return;
      try {
        final data = jsonDecode(payload);
        if (data['type'] == 'zone_info') {
          setState(() {
            _index = 0; // Home tab
            _targetZone = data['zone'];
          });
        }
      } catch (e) {
        debugPrint('[NOTIF] Failed to parse payload: $e');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Health Connect can't push to us — resuming the app is the earliest
  /// moment we can notice new meals, workouts or weights logged in other
  /// apps. Throttled inside the provider (max every 15 min).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<FastingProvider>().maybeAutoImportFromHealth();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Consume target zone once
    final zone = _targetZone;
    _targetZone = null;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(targetZone: zone),
          const MealsDashboardScreen(),
          const TrainScreen(),
          const JournalScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          // All tabs are browsable for free. Premium is enforced at the
          // point of action instead: logging a meal or workout (the "+"),
          // Insights, and Health Connect.
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.hourglass_empty_rounded),
            selectedIcon: Icon(Icons.hourglass_full_rounded),
            label: 'Fast',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_outlined),
            selectedIcon: Icon(Icons.restaurant),
            label: 'Meals',
          ),
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Workout',
          ),
          // Journal stays rightmost by design.
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'Journal',
          ),
        ],
      ),
    );
  }
}
