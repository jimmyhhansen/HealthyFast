import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fasting_zone.dart';

class NotificationService {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static const String _prefKey = 'notifications_enabled';
  static const String _disabledMilestonesKey = 'disabled_milestones';
  static const String _customMilestonesKey = 'custom_milestones';
  static const String _reminderEnabledKey = 'daily_reminder_enabled';
  static const String _reminderHourKey = 'daily_reminder_hour';
  static const String _reminderMinKey = 'daily_reminder_min';

  static Future<void> init() async {
    tz.initializeTimeZones();
    try {
      // Manual timezone set for Norway (GMT+1 / GMT+2)
      // This is a robust fallback for the user's current location.
      tz.setLocalLocation(tz.getLocation('Europe/Oslo'));
      debugPrint('[NOTIF] Timezone initialized for Europe/Oslo');
    } catch (e) {
      debugPrint('[NOTIF] Failed to set location: $e');
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Don't auto-prompt here — requestPermissions() asks explicitly once the
    // user reaches the relevant screen, same flow as Android.
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: ios);
    await _notifications.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onTap,
    );

    // Create the notification channel (required for Android 8+)
    const channel = AndroidNotificationChannel(
      'fasting_milestones',
      'Fasting Milestones',
      description: 'Alerts when you reach a new fasting zone or your goal',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    if (!value) {
      await cancelAll();
    }
  }

  static Future<List<String>> getDisabledMilestones() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_disabledMilestonesKey) ?? [];
  }

  static Future<void> toggleMilestone(String milestoneName, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final disabled = await getDisabledMilestones();
    if (enabled) {
      disabled.remove(milestoneName);
    } else {
      if (!disabled.contains(milestoneName)) {
        disabled.add(milestoneName);
      }
    }
    await prefs.setStringList(_disabledMilestonesKey, disabled);
  }

  static Future<Map<String, int>> getCustomMilestones() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_customMilestonesKey) ?? [];
    final map = <String, int>{};
    for (final item in list) {
      final parts = item.split('|');
      if (parts.length == 2) {
        map[parts[0]] = int.tryParse(parts[1]) ?? 0;
      }
    }
    return map;
  }

  static Future<void> addCustomMilestone(String name, int hours) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_customMilestonesKey) ?? [];
    list.add('$name|$hours');
    await prefs.setStringList(_customMilestonesKey, list);
  }

  static Future<void> deleteCustomMilestone(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_customMilestonesKey) ?? [];
    list.removeWhere((item) => item.startsWith('$name|'));
    await prefs.setStringList(_customMilestonesKey, list);
  }

  static final StreamController<String?> selectNotificationStream =
      StreamController<String?>.broadcast();

  static void _onTap(NotificationResponse details) {
    selectNotificationStream.add(details.payload);
  }

  static Future<void> scheduleMilestones(DateTime startTime, int goalHours) async {
    final enabled = await isEnabled();
    final allowed = await areNotificationsEnabled();
    debugPrint('[NOTIF] scheduleMilestones: enabled=$enabled allowed=$allowed '
        'startTime=$startTime goalHours=$goalHours');

    if (!enabled || !allowed) {
      debugPrint('[NOTIF] Notifications disabled or not permitted. Skipping.');
      return;
    }

    await cancelAll();
    // Re-schedule the daily reminder so it stays in the queue even if we
    // clear all milestone alarms.
    await scheduleDailyReminder();

    final now = DateTime.now();
    final disabled = await getDisabledMilestones();
    final custom = await getCustomMilestones();

    debugPrint('[NOTIF] Current time: $now');

    // iOS caps an app at 64 pending local notifications total, and the
    // daily reminder scheduled above already uses one slot. Android has no
    // such limit, so the cap only applies there.
    final iosBudget = Platform.isIOS ? 62 : null;
    var iosScheduledCount = 0;
    bool budgetLeft() => iosBudget == null || iosScheduledCount < iosBudget;

    // Standard zones
    for (int i = 1; i < kFastingZones.length; i++) {
      if (!budgetLeft()) {
        debugPrint('[NOTIF] iOS notification budget reached, skipping remaining zones.');
        break;
      }
      final zone = kFastingZones[i];
      if (disabled.contains(zone.name)) {
        debugPrint('[NOTIF] Zone ${zone.name} is disabled by user.');
        continue;
      }

      final scheduledTime = startTime.add(Duration(hours: zone.fromHour));

      if (scheduledTime.isAfter(now)) {
        debugPrint('[NOTIF] Scheduling Zone: ${zone.name} at $scheduledTime');
        await _schedule(
          id: i,
          title: 'Good job! You have entered stage: ${zone.name}',
          body: '${zone.emoji} ${zone.tip} Read more...',
          scheduledDate: scheduledTime,
          payload: jsonEncode({'type': 'zone_info', 'zone': zone.name}),
        );
        iosScheduledCount++;
      } else {
        debugPrint('[NOTIF] Skipping Zone: ${zone.name} (already in the past: $scheduledTime)');
      }
    }

    // Custom milestones
    int idCounter = 200;
    for (final entry in custom.entries) {
      if (!budgetLeft()) {
        debugPrint('[NOTIF] iOS notification budget reached, skipping remaining custom milestones.');
        break;
      }
      final name = entry.key;
      final hours = entry.value;
      if (disabled.contains(name)) continue;

      final scheduledTime = startTime.add(Duration(hours: hours));
      if (scheduledTime.isAfter(now)) {
        debugPrint('[NOTIF] Scheduling Custom: $name at $scheduledTime');
        await _schedule(
          id: idCounter++,
          title: 'Good job! Milestone Reached: $name',
          body: 'You have been fasting for $hours hours! Read more...',
          scheduledDate: scheduledTime,
        );
        iosScheduledCount++;
      }
    }

    // Goal reached notification
    if (!disabled.contains('Goal Reached') && budgetLeft()) {
      final goalTime = startTime.add(Duration(hours: goalHours));
      if (goalTime.isAfter(now)) {
        debugPrint('[NOTIF] Scheduling Goal: $goalHours hours at $goalTime');
        await _schedule(
          id: 100,
          title: 'Good job! Goal Reached!',
          body: 'Congratulations! You have reached your fasting goal of $goalHours hours. Read more...',
          scheduledDate: goalTime,
        );
        iosScheduledCount++;
      }
    }
  }

  static Future<bool> isReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_reminderEnabledKey) ?? false;
  }

  static Future<void> setReminderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reminderEnabledKey, value);
    if (value) {
      await scheduleDailyReminder();
    } else {
      await _notifications.cancel(id: 7777); // daily reminder id
    }
  }

  static Future<(int, int)> getReminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    final h = prefs.getInt(_reminderHourKey) ?? 20;
    final m = prefs.getInt(_reminderMinKey) ?? 0;
    return (h, m);
  }

  static Future<void> setReminderTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_reminderHourKey, hour);
    await prefs.setInt(_reminderMinKey, minute);
    if (await isReminderEnabled()) {
      await scheduleDailyReminder();
    }
  }

  /// Schedules a recurring daily reminder. It fires every day at the
  /// chosen time.
  static Future<void> scheduleDailyReminder() async {
    final enabled = await isReminderEnabled();
    if (!enabled) return;

    final (h, m) = await getReminderTime();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    debugPrint('[NOTIF] Scheduling DAILY REMINDER at $scheduled (ID 7777)');
    await _notifications.zonedSchedule(
      id: 7777,
      title: 'Time to start your fast? ⏳',
      body: 'Consistent habits are key to success. Start your fast now to reach your goal tomorrow!',
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminders',
          'Daily Reminders',
          channelDescription: 'Reminds you to start your fast at a set time each day',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: await _scheduleMode(),
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    try {
      final mode = await _scheduleMode();
      debugPrint('[NOTIF] Scheduling id=$id at $scheduledDate mode=$mode');
      await _notifications.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'fasting_milestones',
            'Fasting Milestones',
            channelDescription: 'Alerts when you reach a new fasting zone or your goal',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: mode,
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NOTIF] Error scheduling notification $id: $e');
    }
  }

  static Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  /// Requests only the POST_NOTIFICATIONS permission (Android 13+ / Wear OS
  /// 4+). Used on the watch, where the ongoing-activity indicator is an
  /// ongoing notification and the exact-alarm settings screen from
  /// [requestPermissions] would be intrusive.
  static Future<void> requestNotificationsPermission() async {
    if (Platform.isIOS) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      try {
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      } on Exception catch (e) {
        debugPrint('[NOTIF] iOS requestNotificationsPermission error: $e');
      }
      return;
    }
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await android?.requestNotificationsPermission();
    } on Exception catch (e) {
      debugPrint('[NOTIF] requestNotificationsPermission error: $e');
    }
  }

  static Future<void> requestPermissions() async {
    if (Platform.isIOS) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      try {
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      } on Exception catch (e) {
        debugPrint('[NOTIF] iOS requestPermissions error: $e');
      }
      return;
    }
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      // Request basic notification permission (the popup you see)
      await android?.requestNotificationsPermission();
      // Request exact-alarm permission so scheduled milestones fire on time.
      // On Android 14+ this opens the system "Alarms & reminders" screen; if the
      // user declines we silently fall back to inexact scheduling.
      if (!(await android?.canScheduleExactNotifications() ?? false)) {
        await android?.requestExactAlarmsPermission();
      }
    } on Exception catch (e) {
      debugPrint('[NOTIF] requestPermissions error: $e');
    }
  }

  /// Picks exact scheduling when the OS allows it, otherwise inexact so the
  /// notification is still delivered (just possibly delayed in Doze).
  static Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canExact = await android?.canScheduleExactNotifications() ?? false;
    return canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Whether the OS currently allows this app to post notifications.
  /// Returns false if the user denied the POST_NOTIFICATIONS permission.
  static Future<bool> areNotificationsEnabled() async {
    if (Platform.isIOS) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final settings = await ios?.checkPermissions();
      return settings?.isEnabled ?? false;
    }
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  /// Shows an immediate notification. Used to verify the pipeline (channel +
  /// permission) works without waiting hours for the first milestone.
  static Future<void> showNow({
    String title = 'HealthyFast',
    String body = 'Hvis du ser dette, virker varslene 🎉',
  }) async {
    await _notifications.show(
      id: 9999,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'fasting_milestones',
          'Fasting Milestones',
          channelDescription:
              'Alerts when you reach a new fasting zone or your goal',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// Schedules a test notification to fire in exactly 60 seconds.
  static Future<void> testSchedule() async {
    final now = DateTime.now();
    final scheduledTime = now.add(const Duration(seconds: 60));
    debugPrint('[NOTIF] Scheduling TEST in 60s: $scheduledTime');
    await _schedule(
      id: 8888,
      title: 'Planlagt varsel virker! 🎉',
      body: 'Dette varselet ble planlagt for 1 minutt siden.',
      scheduledDate: scheduledTime,
    );
  }
}
