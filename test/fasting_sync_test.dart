import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:healthyfast/models/fast_record.dart';
import 'package:healthyfast/providers/fasting_provider.dart';

/// Regression tests for [FastingProvider.syncFromRemote].
///
/// Bug: closing the app stopped an active fast. A stale/empty
/// "not fasting" state broadcast over the watch data layer was applied on
/// startup and cancelled the just-restored fast. A remote "stopped" decision
/// is only valid if it was made AFTER the local fast started.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  // The local_notifications plugin channel isn't registered in tests; stub it
  // so the fire-and-forget cancelAll() in stopFast() doesn't throw.
  const notifChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hf_sync_test');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FastRecordAdapter());
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, (call) async => null);
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifChannel, null);
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    // Notifications off so scheduleMilestones() returns early (no timezone/plugin work).
    SharedPreferences.setMockInitialValues({'notifications_enabled': false});
    if (Hive.isBoxOpen('fasts')) {
      await Hive.box<FastRecord>('fasts').clear();
    } else {
      await Hive.openBox<FastRecord>('fasts');
    }
  });

  group('syncFromRemote stop semantics', () {
    test('newer remote stop (changed after our last change) stops the fast',
        () async {
      final fp = FastingProvider();
      await fp.startFast();
      expect(fp.isFasting, isTrue);

      // Remote deliberately stopped AFTER our last change -> a genuine newer stop.
      final newerStopMs = fp.lastChangedMs! + 5000;
      final changed = await fp.syncFromRemote(
        isFasting: false,
        remoteStartTime: null,
        protocolHours: 16,
        protocolLabel: '16:8',
        isCustom: false,
        remoteChangedMs: newerStopMs,
      );

      expect(changed, isTrue);
      expect(fp.isFasting, isFalse);
      expect(fp.startTime, isNull);
      expect(fp.history.length, 1); // the completed fast was recorded

      fp.dispose();
    });

    test('stale remote stop (changed before our last change) keeps the fast',
        () async {
      final fp = FastingProvider();
      await fp.startFast();
      final startTimeBefore = fp.startTime;

      // Remote's last real change predates our fast -> outdated, must not win.
      final staleStopMs = fp.lastChangedMs! - 60000;
      final changed = await fp.syncFromRemote(
        isFasting: false,
        remoteStartTime: null,
        protocolHours: 16,
        protocolLabel: '16:8',
        isCustom: false,
        remoteChangedMs: staleStopMs,
      );

      expect(changed, isFalse);
      expect(fp.isFasting, isTrue);
      expect(fp.startTime, startTimeBefore);
      expect(fp.history, isEmpty);

      fp.dispose();
    });

    test('empty remote stop (no change timestamp) keeps the fast', () async {
      final fp = FastingProvider();
      await fp.startFast();

      // Default/empty context: not fasting, no start time, no change time.
      final changed = await fp.syncFromRemote(
        isFasting: false,
        remoteStartTime: null,
        protocolHours: 16,
        protocolLabel: '16:8',
        isCustom: false,
        remoteChangedMs: null,
      );

      expect(changed, isFalse);
      expect(fp.isFasting, isTrue);

      fp.dispose();
    });

    test(
        'REGRESSION: idle device re-broadcasting an old state must not stop a '
        'newer fast (this is the close-app bug)', () async {
      // Reproduces the real failure: the watch has an old "not fasting" state
      // whose change time predates the phone's current fast. Under the old
      // broadcast-time logic this carried a fresh "now" timestamp and wrongly
      // looked like a brand-new stop. With change-time semantics it must be
      // ignored.
      final fp = FastingProvider();
      await fp.startFast();
      final localStart = fp.startTime;

      // The other device's last *real* change was an hour before our fast.
      final oldRemoteChange = fp.lastChangedMs! - const Duration(hours: 1).inMilliseconds;
      final changed = await fp.syncFromRemote(
        isFasting: false,
        remoteStartTime: null,
        protocolHours: 16,
        protocolLabel: '16:8',
        isCustom: false,
        remoteChangedMs: oldRemoteChange,
      );

      expect(changed, isFalse);
      expect(fp.isFasting, isTrue, reason: 'fast must survive a stale remote state');
      expect(fp.startTime, localStart);

      fp.dispose();
    });
  });

  group('syncFromRemote start adoption', () {
    test('adopts an active fast started on the paired device', () async {
      final fp = FastingProvider();
      expect(fp.isFasting, isFalse);

      final remoteStart = DateTime.now().subtract(const Duration(hours: 2));
      final changed = await fp.syncFromRemote(
        isFasting: true,
        remoteStartTime: remoteStart,
        protocolHours: 18,
        protocolLabel: '18:6',
        isCustom: false,
        remoteChangedMs: DateTime.now().millisecondsSinceEpoch,
      );

      expect(changed, isTrue);
      expect(fp.isFasting, isTrue);
      expect(fp.startTime, remoteStart);
      expect(fp.protocol.hours, 18);

      fp.dispose();
    });
  });
}
