import 'package:flutter/material.dart';
import '../models/meal_record.dart';

/// One qualitative pattern found in the user's logged meals.
class MealInsight {
  const MealInsight({
    required this.icon,
    required this.title,
    required this.body,
    required this.positive,
  });

  final IconData icon;
  final String title;
  final String body;

  /// True = encouraging (green tint), false = worth attention (amber tint).
  final bool positive;
}

/// Rule-based pattern analysis of meal descriptions and macros.
/// Deliberately qualitative: keyword matching on the free-text names
/// (Norwegian + English) plus macro distribution — indications, not
/// diagnoses. Runs offline, no AI needed.
class MealInsightsService {
  MealInsightsService._();

  static const _veg = [
    'salat', 'grønnsak', 'gronnsak', 'brokkoli', 'blomkål', 'blomkal',
    'gulrot', 'tomat', 'agurk', 'paprika', 'spinat', 'kål', 'kal', 'løk',
    'lok', 'squash', 'avokado', 'bønner', 'bonner', 'linser', 'erter',
    'salad', 'vegetable', 'veggie', 'broccoli', 'cauliflower', 'carrot',
    'cucumber', 'pepper', 'spinach', 'kale', 'onion', 'avocado', 'beans',
    'lentil', 'peas',
  ];
  static const _fish = [
    'fisk', 'laks', 'torsk', 'makrell', 'sild', 'ørret', 'orret',
    'tunfisk', 'reker', 'sjømat', 'sjomat', 'fish', 'salmon', 'cod',
    'mackerel', 'herring', 'trout', 'tuna', 'shrimp', 'seafood',
  ];
  static const _sugary = [
    'brus', 'sjokolade', 'godteri', 'kake', 'bolle', 'dessert', 'sukker',
    'saft', 'kjeks', 'soda', 'chocolate', 'candy', 'cake', 'bun',
    'ice cream', 'iskrem', 'sugar', 'cookie', 'donut', 'muffin',
  ];

  static bool _mentions(String name, List<String> words) {
    final n = name.toLowerCase();
    return words.any(n.contains);
  }

  /// Returns up to 4 insights, or empty when there isn't enough data.
  static List<MealInsight> analyze(List<MealRecord> meals) {
    if (meals.length < 5) return const [];

    final total = meals.length;
    final vegN = meals.where((m) => _mentions(m.name, _veg)).length;
    final fishN = meals.where((m) => _mentions(m.name, _fish)).length;
    final sugarN = meals.where((m) => _mentions(m.name, _sugary)).length;
    final lateN = meals.where((m) => m.time.hour >= 21).length;

    final kcal = meals.fold<double>(0, (s, m) => s + m.calories);
    final proteinG = meals.fold<double>(0, (s, m) => s + (m.protein ?? 0));
    final hasProtein = meals.where((m) => m.protein != null).length;
    // Protein share of energy, only when enough meals carry macro data.
    final proteinShare = (kcal > 0 && hasProtein >= total / 2)
        ? (proteinG * 4 / kcal)
        : null;

    int pct(int n) => (n * 100 / total).round();

    final attention = <MealInsight>[];
    final praise = <MealInsight>[];

    if (proteinShare != null) {
      if (proteinShare < 0.15) {
        attention.add(MealInsight(
          icon: Icons.fitness_center_rounded,
          title: 'Protein looks low',
          body: 'About ${(proteinShare * 100).round()}% of logged energy is '
              'protein. 15–25% helps preserve muscle while fasting.',
          positive: false,
        ));
      } else if (proteinShare >= 0.25) {
        praise.add(MealInsight(
          icon: Icons.fitness_center_rounded,
          title: 'Strong protein intake',
          body: '${(proteinShare * 100).round()}% of logged energy is '
              'protein — good for keeping muscle during fasting.',
          positive: true,
        ));
      }
    }

    if (vegN * 4 < total) {
      attention.add(MealInsight(
        icon: Icons.eco_rounded,
        title: 'Few vegetables logged',
        body: 'Vegetables appear in ${pct(vegN)}% of your meals this '
            'period. More plants means more fibre and micronutrients.',
        positive: false,
      ));
    } else if (vegN * 2 >= total) {
      praise.add(MealInsight(
        icon: Icons.eco_rounded,
        title: 'Plenty of vegetables',
        body: 'Vegetables appear in ${pct(vegN)}% of your meals — keep it up.',
        positive: true,
      ));
    }

    if (fishN == 0 && total >= 10) {
      attention.add(const MealInsight(
        icon: Icons.set_meal_rounded,
        title: 'No fish logged',
        body: 'Health authorities recommend fish 2–3 times a week for '
            'omega-3 and vitamin D.',
        positive: false,
      ));
    } else if (fishN * 6 >= total) {
      praise.add(const MealInsight(
        icon: Icons.set_meal_rounded,
        title: 'Regular fish meals',
        body: 'Fish shows up steadily in your log — great source of '
            'omega-3 and vitamin D.',
        positive: true,
      ));
    }

    if (sugarN * 10 > total * 3) {
      attention.add(MealInsight(
        icon: Icons.icecream_rounded,
        title: 'Sweets show up often',
        body: 'Sugary items appear in ${pct(sugarN)}% of your meals. '
            'They make calorie goals harder and hunger swings bigger.',
        positive: false,
      ));
    }

    if (lateN * 100 > total * 35) {
      attention.add(MealInsight(
        icon: Icons.bedtime_rounded,
        title: 'Many late meals',
        body: '${pct(lateN)}% of meals are logged after 21:00. Eating '
            'earlier makes the overnight fast easier.',
        positive: false,
      ));
    }

    // Worth-attention first, then praise, capped at 4 total.
    return [...attention, ...praise].take(4).toList();
  }
}
