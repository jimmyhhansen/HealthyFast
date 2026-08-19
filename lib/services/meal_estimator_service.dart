import 'dart:convert';
import 'package:flutter/services.dart';
import 'debug_log_service.dart';

/// Nutrition estimate produced by on-device Gemini Nano.
class MealEstimate {
  const MealEstimate({
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
  });

  final int calories;
  final int? protein;
  final int? carbs;
  final int? fat;
}

/// Availability of the on-device model.
enum NanoStatus { available, downloadable, downloading, unavailable }

/// Estimates meal nutrition with Gemini Nano running on the device
/// (ML Kit GenAI Prompt API). Free, offline, and private — but only
/// supported on newer devices (Pixel 8+, Galaxy S24+, ...).
class MealEstimatorService {
  MealEstimatorService._();

  static const _channel = MethodChannel('healthyfast/meal');

  static Future<NanoStatus> checkStatus() async {
    try {
      final s = await _channel.invokeMethod<String>('checkNanoStatus');
      final status = switch (s) {
        'available' => NanoStatus.available,
        'downloadable' => NanoStatus.downloadable,
        'downloading' => NanoStatus.downloading,
        _ => NanoStatus.unavailable,
      };
      await DebugLogService.log(
          'MealAI', 'checkNanoStatus: raw="$s" -> $status');
      return status;
    } catch (e) {
      await DebugLogService.log('MealAI', 'checkNanoStatus threw: $e');
      return NanoStatus.unavailable;
    }
  }

  /// Downloads the model. Returns true when it completes.
  static Future<bool> downloadModel() async {
    try {
      return await _channel.invokeMethod<bool>('downloadNano') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Extracts individual foods + gram estimates from a description, for
  /// nutrient lookup in Matvaretabellen. Returns null when unavailable
  /// or unparseable. Each entry is (Norwegian food name, grams).
  static Future<List<(String, double)>?> extractFoods(
      String description) async {
    try {
      final raw = await _channel.invokeMethod<String>(
        'extractFoods',
        {'description': description},
      );
      if (raw == null) return null;
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      if (start == -1 || end <= start) return null;
      final list = jsonDecode(raw.substring(start, end + 1));
      if (list is! List) return null;
      final foods = <(String, double)>[];
      for (final item in list) {
        if (item is! Map) continue;
        final name = item['n'];
        final grams = _toInt(item['g']);
        if (name is String && name.trim().isNotEmpty && grams != null) {
          // Sanity range: 1 g – 2 kg per item.
          if (grams >= 1 && grams <= 2000) {
            foods.add((name.trim(), grams.toDouble()));
          }
        }
      }
      return foods.isEmpty ? null : foods;
    } catch (_) {
      return null;
    }
  }

  /// Describes the food in a photo with multimodal Gemini Nano — the same
  /// on-device model family as [estimate], so it runs on the supported
  /// devices listed in the store. Returns the description text, or null when
  /// the device/model can't (no multimodal support, decode failure, ...), in
  /// which case the caller (see meals_screen.dart _scanPhoto) falls back to
  /// CloudAiService.describeMealPhoto if the user has consented to cloud AI,
  /// or text entry otherwise. On-device only — this method itself never
  /// leaves the phone.
  static Future<String?> describePhoto(String path) async {
    await DebugLogService.log(
        'MealAI', 'describePhoto: on-device call starting for $path');
    try {
      final text = await _channel.invokeMethod<String>(
        'describeImage',
        {'path': path},
      );
      final trimmed = text?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        await DebugLogService.log(
            'MealAI', 'describePhoto: on-device returned null/empty');
        return null;
      }
      await DebugLogService.log(
          'MealAI', 'describePhoto: on-device succeeded, length=${trimmed.length}');
      return trimmed;
    } catch (e) {
      await DebugLogService.log('MealAI', 'describePhoto: on-device threw: $e');
      return null;
    }
  }

  /// Returns an estimate, or null if the model output could not be parsed.
  static Future<MealEstimate?> estimate(String description) async {
    final raw = await _channel.invokeMethod<String>(
      'estimateMeal',
      {'description': description},
    );
    if (raw == null) return null;
    return parseEstimate(raw);
  }

  /// Extracts the first JSON object from the model output. Small on-device
  /// models occasionally wrap JSON in prose or code fences. Public so the
  /// cloud fallback (same prompt/output contract, see CloudAiService) can
  /// reuse it instead of duplicating the parsing.
  static MealEstimate? parseEstimate(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final map = jsonDecode(raw.substring(start, end + 1));
      if (map is! Map) return null;
      final calories = _toInt(map['calories']);
      if (calories == null || calories < 0 || calories > 10000) return null;
      return MealEstimate(
        calories: calories,
        protein: _toInt(map['protein']),
        carbs: _toInt(map['carbs']),
        fat: _toInt(map['fat']),
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
