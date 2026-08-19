import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Pending spoken meals on the watch, delivered reliably to the phone.
///
/// A meal is enqueued locally FIRST, then sent. It stays queued — and is
/// re-announced through the persisted application context on every sync
/// broadcast — until the phone acknowledges the id. This survives the
/// phone being unreachable, either app being killed, and repeated sends
/// (the phone dedupes on id).
class MealSyncQueue {
  MealSyncQueue._();

  static const _key = 'pending_meals';

  /// Set by WatchSyncService so queue changes trigger a re-broadcast.
  static void Function()? onChanged;

  static Future<List<Map<String, dynamic>>> pending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final e in list)
          if (e is Map) e.cast<String, dynamic>(),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(list));
  }

  static String _newId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 20)}';

  /// Queues a spoken meal; returns the queued item (with its id).
  static Future<Map<String, dynamic>> enqueue(String text) =>
      enqueueRaw({'text': text});

  /// Queues an arbitrary payload (meal or workout). Assigns an id when
  /// missing; returns the queued item.
  static Future<Map<String, dynamic>> enqueueRaw(
      Map<String, dynamic> payload) async {
    final item = <String, dynamic>{
      ...payload,
      'id': payload['id'] ?? _newId(),
      'ms': DateTime.now().millisecondsSinceEpoch,
    };
    final list = await pending();
    list.add(item);
    // Keep the queue sane if the phone is gone for days.
    while (list.length > 20) {
      list.removeAt(0);
    }
    await _save(list);
    onChanged?.call();
    return item;
  }

  /// Removes acknowledged ids. Returns true when anything was removed.
  static Future<bool> removeIds(Iterable<String> ids) async {
    final set = ids.toSet();
    final list = await pending();
    final before = list.length;
    list.removeWhere((e) => set.contains(e['id']));
    if (list.length == before) return false;
    await _save(list);
    onChanged?.call();
    return true;
  }
}
