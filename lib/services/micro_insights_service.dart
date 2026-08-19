import 'dart:convert';

import 'package:flutter/material.dart';
import '../models/meal_record.dart';
import 'meal_insights_service.dart';
import 'nutrition_data_service.dart';

/// Estimates micronutrient coverage from AI-extracted foods matched
/// against Matvaretabellen, and turns clear gaps into insights.
///
/// Conservative by design: only days that have analysed meals count,
/// only clear shortfalls (<50% of the daily reference) are flagged, and
/// everything is labelled an estimate.
class MicroInsightsService {
  MicroInsightsService._();

  /// key → (label, daily reference, unit). References follow the Nordic
  /// Nutrition Recommendations for adults; units match Matvaretabellen.
  static const _refs = <String, (String, double, String)>{
    'iron': ('Iron', 12, 'mg'),
    'calcium': ('Calcium', 900, 'mg'),
    'vitaminD': ('Vitamin D', 10, 'µg'),
    'folate': ('Folate', 350, 'µg'),
    'vitaminB12': ('Vitamin B12', 4, 'µg'),
    'vitaminC': ('Vitamin C', 90, 'mg'),
    'magnesium': ('Magnesium', 330, 'mg'),
    'fiber': ('Fibre', 30, 'g'),
    'omega3': ('Omega-3 (EPA+DHA)', 0.25, 'g'),
  };

  /// Returns up to 3 shortfall insights (or one all-clear), empty when
  /// there isn't enough analysed data or the table isn't downloaded.
  static Future<List<MealInsight>> analyze(List<MealRecord> meals) async {
    if (!await NutritionDataService.isReady()) return const [];

    final enriched = meals.where((m) => m.foodsJson != null).toList();
    final days = enriched
        .map((m) => DateTime(m.time.year, m.time.month, m.time.day))
        .toSet();
    if (days.length < 3) return const [];

    final totals = <String, double>{};
    var lookupsHit = 0;
    var lookupsTotal = 0;

    for (final meal in enriched) {
      List<dynamic> foods;
      try {
        foods = jsonDecode(meal.foodsJson!) as List;
      } catch (_) {
        continue;
      }
      for (final f in foods) {
        if (f is! Map) continue;
        final name = f['n'] as String?;
        final grams = (f['g'] as num?)?.toDouble();
        if (name == null || grams == null) continue;
        lookupsTotal++;
        final per100 = await NutritionDataService.lookup(name);
        if (per100 == null) continue;
        lookupsHit++;
        per100.forEach((key, v) {
          totals[key] = (totals[key] ?? 0) + v * grams / 100;
        });
      }
    }
    // If most foods didn't match the table, the estimate is worthless.
    if (lookupsTotal == 0 || lookupsHit * 2 < lookupsTotal) return const [];

    final coverage = <String, double>{};
    _refs.forEach((key, ref) {
      final avgPerDay = (totals[key] ?? 0) / days.length;
      coverage[key] = avgPerDay / ref.$2;
    });

    final lows = coverage.entries.where((e) => e.value < 0.5).toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    if (lows.isEmpty) {
      final allGood = coverage.values.every((c) => c >= 0.8);
      if (allGood) {
        return const [
          MealInsight(
            icon: Icons.verified_rounded,
            title: 'Micronutrients look covered',
            body: 'Your analysed meals roughly meet the daily references '
                'for the nutrients we track. Nice.',
            positive: true,
          ),
        ];
      }
      return const [];
    }

    return [
      for (final e in lows.take(3))
        MealInsight(
          icon: Icons.science_rounded,
          title: '${_refs[e.key]!.$1} may be low',
          body: 'Analysed meals cover roughly '
              '${(e.value * 100).clamp(0, 999).round()}% of the daily '
              'reference (${_trim(_refs[e.key]!.$2)} ${_refs[e.key]!.$3}), '
              'averaged over ${days.length} days with data.',
          positive: false,
        ),
    ];
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}
