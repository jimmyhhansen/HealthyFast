import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exercise.dart';

/// User-created exercises, stored locally as JSON. They merge with the
/// built-in ones in ExerciseGuides.
class CustomExercisesService {
  CustomExercisesService._();

  static const _key = 'custom_exercises';

  static Future<List<Exercise>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return [
        for (final m in list)
          if (m is Map) Exercise.fromJson(m.cast<String, dynamic>()),
      ];
    } catch (e) {
      debugPrint('[TRAIN] custom exercises load failed: $e');
      return [];
    }
  }

  static Future<void> saveAll(List<Exercise> exercises) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode([for (final e in exercises) e.toJson()]));
  }

  /// Adds or replaces (by name) a custom exercise.
  static Future<void> upsert(Exercise exercise) async {
    final list = await load();
    list.removeWhere((e) => e.name == exercise.name);
    list.add(exercise);
    await saveAll(list);
  }

  static Future<void> delete(String name) async {
    final list = await load();
    list.removeWhere((e) => e.name == name);
    await saveAll(list);
  }
}
