import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/fast_record.dart';
import '../models/meal_record.dart';
import '../models/weight_record.dart';
import '../models/workout_record.dart';
import '../providers/fasting_provider.dart';

/// Premium cloud backup (v2.1). Signs in with Google and mirrors the four
/// Hive boxes to Firestore as per-record documents under
/// `users/{uid}/{fasts|meals|weights|workouts}/{syncId}`.
///
/// Deliberately BACKUP semantics, not two-way realtime sync:
///  • "Back up" uploads every local record (assigning a stable [syncId]).
///  • "Restore" pulls the cloud records and MERGES them into local data,
///    de-duplicating on [syncId]. It never deletes local records — a backup
///    should not be able to wipe your data — so deletes don't propagate.
///
/// Per-record documents (not one big snapshot doc) keep us clear of
/// Firestore's 1 MB per-document limit no matter how long the history grows.
class CloudBackupService {
  CloudBackupService._();
  static final CloudBackupService instance = CloudBackupService._();

  static const _prefEnabled = 'cloud_backup_enabled';
  static bool _gsiInitialized = false;

  /// Web (client_type 3) OAuth client id from android/app/google-services.json.
  /// google_sign_in v7's Android implementation (Credential Manager-based)
  /// no longer auto-derives this from google-services.json the way the old
  /// plugin did — it must be passed explicitly, or initialize() throws
  /// GoogleSignInExceptionCode.clientConfigurationError ("serverClientId
  /// must be provided on Android"). This is the client Firebase Auth needs
  /// to validate the id token against, not a secret — safe to keep in code.
  /// Regenerate via `flutterfire configure` if the Firebase project changes.
  static const _serverClientId =
      '1093411081699-vdgk4akso28ttfsnqu4gvldq69rparrt.apps.googleusercontent.com';

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  bool get isSignedIn =>
      _auth.currentUser != null && !_auth.currentUser!.isAnonymous;
  String? get accountEmail => _auth.currentUser?.email;

  Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefEnabled) ?? false;
  }

  Future<void> _setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefEnabled, v);
  }

  // ── Auth ────────────────────────────────────────────────────────────

  /// Durable Google sign-in. Same uid across installs and devices, so the
  /// cloud tree is always reachable.
  Future<User> signIn() async {
    final gsi = GoogleSignIn.instance;
    if (!_gsiInitialized) {
      await gsi.initialize(serverClientId: _serverClientId);
      _gsiInitialized = true;
    }
    final account = await gsi.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw StateError(
          'Google sign-in returned no id token. Check that the Google '
          'provider is enabled in Firebase and that the SHA keys are '
          'registered.');
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final res = await _auth.signInWithCredential(credential);
    return res.user!;
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await _auth.signOut();
    await _setEnabled(false);
  }

  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _fs.collection('users').doc(_auth.currentUser!.uid).collection(name);

  // ── Backup (local → cloud) ──────────────────────────────────────────

  /// Uploads every local record. Assigns a [syncId] to any record missing
  /// one (persisted locally) so future backups and restores de-duplicate.
  /// Returns the number of records uploaded.
  Future<int> backupNow(FastingProvider fp) async {
    if (!isSignedIn) throw StateError('Not signed in.');
    await _setEnabled(true);
    var total = 0;
    total += await _push('fasts', fp.history, _fastToMap);
    total += await _push('meals', fp.meals, _mealToMap);
    total += await _push('weights', fp.weights, _weightToMap);
    total += await _push('workouts', fp.workouts, _workoutToMap);
    return total;
  }

  Future<int> _push<T extends HiveObject>(
    String coll,
    List<T> records,
    Map<String, dynamic> Function(T) toMap,
  ) async {
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final r in records) {
      final id = _ensureSyncId(r);
      entries.add(MapEntry(id, {
        ...toMap(r),
        'updatedAt': FieldValue.serverTimestamp(),
      }));
    }
    // Batched writes, max 450 ops per batch (Firestore limit is 500).
    for (var i = 0; i < entries.length; i += 450) {
      final batch = _fs.batch();
      for (final e in entries.skip(i).take(450)) {
        batch.set(_col(coll).doc(e.key), e.value);
      }
      await batch.commit();
    }
    return entries.length;
  }

  /// Reads the record's syncId, generating + persisting one if absent.
  String _ensureSyncId(HiveObject r) {
    String? id;
    if (r is FastRecord) id = r.syncId;
    if (r is MealRecord) id = r.syncId;
    if (r is WeightRecord) id = r.syncId;
    if (r is WorkoutRecord) id = r.syncId;
    if (id != null && id.isNotEmpty) return id;
    id = _uuid.v4();
    if (r is FastRecord) r.syncId = id;
    if (r is MealRecord) r.syncId = id;
    if (r is WeightRecord) r.syncId = id;
    if (r is WorkoutRecord) r.syncId = id;
    // Persist the assigned id back to the Hive box.
    r.save();
    return id;
  }

  // ── Restore (cloud → local) ─────────────────────────────────────────

  /// Pulls all cloud records and merges them into local data (de-duped on
  /// syncId). Returns the number of new records added locally.
  Future<int> restoreNow(FastingProvider fp) async {
    if (!isSignedIn) throw StateError('Not signed in.');
    final fasts = await _pull('fasts', _fastFromMap);
    final meals = await _pull('meals', _mealFromMap);
    final weights = await _pull('weights', _weightFromMap);
    final workouts = await _pull('workouts', _workoutFromMap);
    return fp.mergeCloudRecords(
      fasts: fasts,
      meals: meals,
      weights: weights,
      workouts: workouts,
    );
  }

  Future<List<T>> _pull<T>(
    String coll,
    T Function(String id, Map<String, dynamic>) fromMap,
  ) async {
    final snap = await _col(coll).get();
    return [for (final d in snap.docs) fromMap(d.id, d.data())];
  }

  // ── Delete (cloud data removal) ─────────────────────────────────────

  /// Permanently deletes every backed-up record for the signed-in account
  /// from Firestore (fasts, meals, weights, workouts), then the now-empty
  /// parent `users/{uid}` doc. Local data on this device is untouched —
  /// this only removes what was uploaded to the cloud. Does not sign the
  /// user out by itself; the Settings UI calls [signOut] right after (see
  /// cloud_ai_settings_screen.dart) so "delete" always leaves the account
  /// fully disconnected too.
  Future<void> deleteCloudData() async {
    if (!isSignedIn) throw StateError('Not signed in.');
    for (final coll in const ['fasts', 'meals', 'weights', 'workouts']) {
      await _deleteAllDocs(_col(coll));
    }
    await _fs.collection('users').doc(_auth.currentUser!.uid).delete();
  }

  /// Deletes docs in pages of 450 (Firestore's batch limit is 500) so this
  /// works no matter how long a user's backup history has grown.
  Future<void> _deleteAllDocs(
      CollectionReference<Map<String, dynamic>> col) async {
    while (true) {
      final snap = await col.limit(450).get();
      if (snap.docs.isEmpty) return;
      final batch = _fs.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  // ── Serialization ───────────────────────────────────────────────────

  Map<String, dynamic> _fastToMap(FastRecord r) => {
        'startTime': r.startTime.millisecondsSinceEpoch,
        'endTime': r.endTime.millisecondsSinceEpoch,
        'protocol': r.protocol,
      };

  FastRecord _fastFromMap(String id, Map<String, dynamic> m) => FastRecord(
        startTime: DateTime.fromMillisecondsSinceEpoch((m['startTime'] as num).toInt()),
        endTime: DateTime.fromMillisecondsSinceEpoch((m['endTime'] as num).toInt()),
        protocol: (m['protocol'] as String?) ?? 'Custom',
        syncId: id,
      );

  Map<String, dynamic> _mealToMap(MealRecord r) => {
        'time': r.time.millisecondsSinceEpoch,
        'name': r.name,
        'calories': r.calories,
        'protein': r.protein,
        'carbs': r.carbs,
        'fat': r.fat,
        'mealType': r.mealType,
        'foodsJson': r.foodsJson,
      };

  MealRecord _mealFromMap(String id, Map<String, dynamic> m) => MealRecord(
        time: DateTime.fromMillisecondsSinceEpoch((m['time'] as num).toInt()),
        name: (m['name'] as String?) ?? '',
        calories: ((m['calories'] as num?) ?? 0).toDouble(),
        protein: (m['protein'] as num?)?.toDouble(),
        carbs: (m['carbs'] as num?)?.toDouble(),
        fat: (m['fat'] as num?)?.toDouble(),
        mealType: (m['mealType'] as String?) ?? 'UNKNOWN',
        foodsJson: m['foodsJson'] as String?,
        syncId: id,
      );

  Map<String, dynamic> _weightToMap(WeightRecord r) => {
        'time': r.time.millisecondsSinceEpoch,
        'kg': r.kg,
      };

  WeightRecord _weightFromMap(String id, Map<String, dynamic> m) => WeightRecord(
        time: DateTime.fromMillisecondsSinceEpoch((m['time'] as num).toInt()),
        kg: ((m['kg'] as num?) ?? 0).toDouble(),
        syncId: id,
      );

  Map<String, dynamic> _workoutToMap(WorkoutRecord r) => {
        'startTime': r.startTime.millisecondsSinceEpoch,
        'endTime': r.endTime.millisecondsSinceEpoch,
        'title': r.title,
        'exercisesJson': r.exercisesJson,
        'programId': r.programId,
        'programDayIdx': r.programDayIdx,
        'source': r.source,
        'activityType': r.activityType,
        'intensity': r.intensity,
      };

  WorkoutRecord _workoutFromMap(String id, Map<String, dynamic> m) =>
      WorkoutRecord(
        startTime: DateTime.fromMillisecondsSinceEpoch((m['startTime'] as num).toInt()),
        endTime: DateTime.fromMillisecondsSinceEpoch((m['endTime'] as num).toInt()),
        title: (m['title'] as String?) ?? 'Workout',
        exercisesJson: m['exercisesJson'] as String?,
        programId: m['programId'] as String?,
        programDayIdx: (m['programDayIdx'] as num?)?.toInt(),
        source: (m['source'] as String?) ?? 'manual',
        activityType: m['activityType'] as String?,
        intensity: m['intensity'] as String?,
        syncId: id,
      );
}
