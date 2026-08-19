import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'training_programs.dart';

/// User-created workout programs, stored locally as JSON. They share the
/// Program model with the bundled ones, so progression, the session
/// screen and the watch sync all work unchanged.
class CustomProgramsService {
  CustomProgramsService._();

  static const _key = 'custom_programs';

  static Future<List<Program>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final p in list)
          if (p is Map) Program.fromJson(p.cast<String, dynamic>()),
      ];
    } catch (e) {
      debugPrint('[TRAIN] custom programs load failed: $e');
      return [];
    }
  }

  static Future<void> saveAll(List<Program> programs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final p in programs) p.toJson()]));
  }

  /// Adds or replaces (by id) a custom program.
  static Future<void> upsert(Program program) async {
    final list = await load();
    list.removeWhere((p) => p.id == program.id);
    list.add(program);
    await saveAll(list);
  }

  static Future<void> delete(String id) async {
    final list = await load();
    list.removeWhere((p) => p.id == id);
    await saveAll(list);
  }

  static String newId() =>
      'custom_${DateTime.now().millisecondsSinceEpoch}';
}
