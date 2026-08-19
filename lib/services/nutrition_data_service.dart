import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads, slims and caches the Norwegian food composition table
/// (Matvaretabellen, Mattilsynet — matvaretabellen.no) and answers
/// nutrient lookups for extracted foods.
///
/// The table updates yearly and explicitly allows caching. We keep only
/// the nutrients we analyse, per 100 g, keyed by lowercase food name.
class NutritionDataService {
  NutritionDataService._();

  static const _sourceUrl = 'https://www.matvaretabellen.no/api/nb/foods.json';
  static const _cacheFile = 'matvaretabellen_slim.json';

  /// nutrientId candidates in the source data → our key.
  /// Units follow the table: mg for minerals, µg for D/folate/B12, g for
  /// fibre and fatty acids.
  static const _nutrients = <String, List<String>>{
    'iron': ['Fe'],
    'calcium': ['Ca'],
    'vitaminD': ['CHOCAL', 'VitD'],
    'folate': ['Folat'],
    'vitaminB12': ['B12', 'VitB12'],
    'vitaminC': ['C', 'VitC'],
    'magnesium': ['Mg'],
    'fiber': ['Fiber'],
    // Marine omega-3: EPA + DHA (grams).
    'omega3': [
      'C20:5n-3Eikosapentaensyre',
      'C22:6n-3Dokosaheksaensyre',
    ],
  };

  static Map<String, Map<String, double>>? _table;

  /// True when the slimmed table is cached locally.
  static Future<bool> isReady() async {
    if (_table != null) return true;
    final f = await _file();
    return f.existsSync();
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_cacheFile');
  }

  /// Downloads and slims the table (~10 MB down, ~1 MB kept). Returns
  /// true on success.
  static Future<bool> download() async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(_sourceUrl));
      final res = await req.close();
      if (res.statusCode != 200) return false;
      final body = await res.transform(utf8.decoder).join();
      client.close();

      final data = jsonDecode(body);
      final foods = (data is Map ? data['foods'] : data) as List?;
      if (foods == null || foods.isEmpty) return false;

      final slim = <String, Map<String, double>>{};
      for (final food in foods) {
        if (food is! Map) continue;
        final name = (food['foodName'] as String?)?.toLowerCase().trim();
        if (name == null || name.isEmpty) continue;
        final constituents = food['constituents'];
        if (constituents is! List) continue;

        final byId = <String, double>{};
        for (final c in constituents) {
          if (c is! Map) continue;
          final id = c['nutrientId'] as String?;
          final q = c['quantity'];
          if (id != null && q is num) byId[id] = q.toDouble();
        }

        final values = <String, double>{};
        _nutrients.forEach((key, candidates) {
          double sum = 0;
          var found = false;
          for (final id in candidates) {
            final v = byId[id];
            if (v != null) {
              sum += v;
              found = true;
            }
          }
          if (found) values[key] = sum;
        });
        if (values.isNotEmpty) slim[name] = values;
      }
      if (slim.length < 100) return false; // sanity: parse went wrong

      final f = await _file();
      await f.writeAsString(jsonEncode(slim));
      _table = slim;
      debugPrint('[NUTRI] Cached ${slim.length} foods');
      return true;
    } catch (e) {
      debugPrint('[NUTRI] download failed: $e');
      return false;
    }
  }

  static Future<Map<String, Map<String, double>>?> _load() async {
    if (_table != null) return _table;
    try {
      final f = await _file();
      if (!f.existsSync()) return null;
      final data = jsonDecode(await f.readAsString());
      if (data is! Map) return null;
      _table = data.map((k, v) => MapEntry(
            k as String,
            (v as Map).map((nk, nv) =>
                MapEntry(nk as String, (nv as num).toDouble())),
          ));
      return _table;
    } catch (_) {
      return null;
    }
  }

  /// Nutrients per 100 g for the best-matching food, or null.
  /// Match order: exact → starts-with → first-word contains.
  static Future<Map<String, double>?> lookup(String foodName) async {
    final table = await _load();
    if (table == null) return null;
    final q = foodName.toLowerCase().trim();
    if (q.isEmpty) return null;

    final exact = table[q];
    if (exact != null) return exact;

    String? best;
    var bestScore = 0;
    final qFirst = q.split(' ').first;
    for (final name in table.keys) {
      int score;
      if (name.startsWith('$q,') || name.startsWith('$q ')) {
        score = 3;
      } else if (name.split(RegExp(r'[ ,]')).first == qFirst) {
        score = 2;
      } else if (name.contains(q)) {
        score = 1;
      } else {
        continue;
      }
      // Prefer shorter names (more generic entries) at equal score.
      if (score > bestScore ||
          (score == bestScore && name.length < (best?.length ?? 1 << 20))) {
        best = name;
        bestScore = score;
      }
    }
    return best == null ? null : table[best];
  }
}
