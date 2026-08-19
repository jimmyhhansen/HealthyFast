import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/cloud_ai_service.dart';
import '../services/custom_programs_service.dart';
import '../services/exercise_guides.dart';
import '../services/training_programs.dart';

/// Generates a custom workout program from a free-text description using
/// the same on-device Gemini Nano model as meal estimation (ML Kit GenAI
/// Prompt API) — offline, no API key, nothing leaves the device.
///
/// Model availability/download uses the same channel and status enum as
/// [MealEstimatorService] (it's the same underlying model) — callers can
/// reuse `MealEstimatorService.checkStatus()` / `.downloadModel()`.
class TrainingAiService {
  TrainingAiService._();

  static const _channel = MethodChannel('healthyfast/meal');

  /// Generates a program, or null if the model output couldn't be parsed
  /// into anything usable. Only picks exercises from
  /// [ExerciseGuides.muscles] — the curated, guide-backed set — so every
  /// exercise the AI names actually has step-by-step instructions.
  static Future<Program?> generateProgram(String description) async {
    final vocab = ExerciseGuides.muscles.keys.toList();
    String? raw;
    try {
      raw = await _channel.invokeMethod<String>('generateProgram', {
        'description': description,
        'exerciseNames': vocab,
      });
    } catch (_) {
      return null;
    }
    if (raw == null) return null;
    return _parse(raw, description, vocab.toSet());
  }

  /// Parses raw model output into a Program, same contract as the
  /// on-device path — reused by the cloud fallback (see CloudAiService)
  /// so both paths share one parser/validator.
  static Program? parseGenerated(String raw, String description) =>
      _parse(raw, description, ExerciseGuides.muscles.keys.toSet());

  /// Cloud fallback: same prompt/vocabulary as [generateProgram], but
  /// processed by Gemini via the Firebase Cloud Function instead of
  /// on-device Nano. Returns raw model text — pass it to [parseGenerated].
  static Future<String?> generateProgramCloudRaw(String description) =>
      CloudAiService.generateProgram(
          description, ExerciseGuides.muscles.keys.toList());

  static Program? _parse(
      String raw, String description, Set<String> allowedNames) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final map = jsonDecode(raw.substring(start, end + 1));
      if (map is! Map) return null;

      final rawDays = map['days'];
      if (rawDays is! List || rawDays.isEmpty) return null;

      final allowedLower = {
        for (final n in allowedNames) n.toLowerCase(): n,
      };

      final days = <ProgramDay>[];
      for (final d in rawDays) {
        if (d is! Map) continue;
        final title = (d['title'] as String?)?.trim();
        final rawExercises = d['exercises'];
        if (title == null || title.isEmpty || rawExercises is! List) continue;

        final exercises = <ProgramExercise>[];
        for (final e in rawExercises) {
          if (e is! Map) continue;
          final rawName = (e['name'] as String?)?.trim();
          if (rawName == null || rawName.isEmpty) continue;
          // The model is asked to copy names verbatim, but small on-device
          // models sometimes drift — match case-insensitively and skip
          // anything that isn't in our curated, guide-backed list rather
          // than saving an exercise with no instructions.
          final matched = allowedLower[rawName.toLowerCase()];
          if (matched == null) continue;

          final sets = (_toInt(e['sets']) ?? 3).clamp(1, 10).toInt();
          final reps = (_toInt(e['reps']) ?? 8).clamp(1, 30).toInt();
          // No way to know the user's actual strength from text alone —
          // a light, empty-bar-ish default the user adjusts once in the
          // editor (same as manually creating a custom program).
          exercises.add(ProgramExercise(
            name: matched,
            sets: sets,
            reps: reps,
            startKg: 20,
            incrementKg: 2.5,
          ));
        }
        if (exercises.isEmpty) continue;
        days.add(ProgramDay(title: title, exercises: exercises));
      }
      if (days.isEmpty) return null;

      final name = (map['programName'] as String?)?.trim();
      final daysPerWeek = (map['daysPerWeek'] as String?)?.trim();

      return Program(
        id: CustomProgramsService.newId(),
        name: (name == null || name.isEmpty) ? 'AI program' : name,
        daysPerWeek: (daysPerWeek == null || daysPerWeek.isEmpty)
            ? '${days.length} days/week'
            : daysPerWeek,
        experience: 'Custom',
        description: description.trim(),
        source: 'Generated on-device with AI — review before saving',
        days: days,
      );
    } catch (_) {
      return null;
    }
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v.replaceAll(RegExp(r'[^\d]'), ''));
    return null;
  }
}
