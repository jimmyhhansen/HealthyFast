import 'dart:io' show Platform;
import 'package:flutter/material.dart';

/// What the user wants HealthyFast to help them with first.
///
/// Picked once during onboarding and stored in ProfileProvider. It never
/// restricts anything — it only decides which capabilities get shown first,
/// and how the calorie target is framed. The user can change it any time in
/// Settings.
enum FitnessGoal { loseFat, buildMuscle, metabolicHealth, everything }

extension FitnessGoalInfo on FitnessGoal {
  String get title => switch (this) {
        FitnessGoal.loseFat => 'Lose fat',
        FitnessGoal.buildMuscle => 'Build strength',
        FitnessGoal.metabolicHealth => 'Feel better',
        FitnessGoal.everything => 'All of it',
      };

  /// The outcome, in the user's words — not the feature.
  String get subtitle => switch (this) {
        FitnessGoal.loseFat =>
          'Lean out without counting every gram or guessing at portions',
        FitnessGoal.buildMuscle =>
          'Get stronger on a real programme, and eat enough to back it up',
        FitnessGoal.metabolicHealth =>
          'Steadier energy, better sleep, fewer crashes through the day',
        FitnessGoal.everything =>
          'Fasting, food and training working together — the full system',
      };

  IconData get icon => switch (this) {
        FitnessGoal.loseFat => Icons.trending_down_rounded,
        FitnessGoal.buildMuscle => Icons.fitness_center_rounded,
        FitnessGoal.metabolicHealth => Icons.favorite_rounded,
        FitnessGoal.everything => Icons.auto_awesome_rounded,
      };

  /// Calorie target as a fraction of daily burn. Deliberately conservative:
  /// a modest deficit or surplus, never an aggressive one.
  double get calorieFactor => switch (this) {
        FitnessGoal.loseFat => 0.80,
        FitnessGoal.buildMuscle => 1.10,
        FitnessGoal.metabolicHealth => 1.00,
        FitnessGoal.everything => 0.90,
      };

  /// One line explaining the target above, shown next to the number.
  String get targetExplainer => switch (this) {
        FitnessGoal.loseFat =>
          'About 20% under your burn — a steady rate most people can hold.',
        FitnessGoal.buildMuscle =>
          'A small surplus so training has something to build with.',
        FitnessGoal.metabolicHealth =>
          'Roughly matching your burn — the aim is rhythm, not restriction.',
        FitnessGoal.everything =>
          'A gentle deficit that still supports training.',
      };

  /// Call to action on the plan summary. Phrased around what they get, not
  /// around paying.
  String get upgradeCta => switch (this) {
        FitnessGoal.loseFat => 'Unlock meal tracking',
        FitnessGoal.buildMuscle => 'Unlock training programmes',
        FitnessGoal.metabolicHealth => 'Unlock the full picture',
        FitnessGoal.everything => 'Unlock everything',
      };

  /// Headline for the plan summary at the end of onboarding.
  String get planHeadline => switch (this) {
        FitnessGoal.loseFat => 'Your fat-loss setup is ready',
        FitnessGoal.buildMuscle => 'Your strength setup is ready',
        FitnessGoal.metabolicHealth => 'Your metabolic setup is ready',
        FitnessGoal.everything => 'Your full setup is ready',
      };

  static FitnessGoal fromIndex(int? i) =>
      (i == null || i < 0 || i >= FitnessGoal.values.length)
          ? FitnessGoal.everything
          : FitnessGoal.values[i];
}

/// One thing the app can do for the user, described as an outcome.
///
/// Single source of truth shared by onboarding and the paywall, so the two
/// can never drift apart and promise different things.
class AppCapability {
  final IconData icon;
  final String title;

  /// What it does *for them*. Concrete, no marketing adjectives.
  final String proof;
  final bool premium;

  /// Goals this capability is most relevant to. [FitnessGoal.everything]
  /// matches all of them.
  final Set<FitnessGoal> goals;

  const AppCapability({
    required this.icon,
    required this.title,
    required this.proof,
    required this.premium,
    required this.goals,
  });

  bool matches(FitnessGoal goal) =>
      goal == FitnessGoal.everything || goals.contains(goal);
}

/// Everything HealthyFast does except Wear OS and health sync (those two are
/// platform-dependent — see [kCapabilities]), ordered roughly by how
/// impressive it is on first contact. Free capabilities first so the value
/// is real before the ask.
const _baseCapabilities = <AppCapability>[
  AppCapability(
    icon: Icons.hourglass_full_rounded,
    title: 'Fasting timer & 7 body zones',
    proof: 'Every protocol from 16:8 to multi-day — and what is actually '
        'happening in your body at each hour, with the research behind it.',
    premium: false,
    goals: {
      FitnessGoal.loseFat,
      FitnessGoal.metabolicHealth,
      FitnessGoal.buildMuscle,
    },
  ),
  AppCapability(
    icon: Icons.local_fire_department_rounded,
    title: 'Your own calorie number',
    proof: 'A daily burn worked out from your body and your week — not a '
        'generic 2000 kcal handed to everyone.',
    premium: false,
    goals: {FitnessGoal.loseFat, FitnessGoal.buildMuscle},
  ),
  AppCapability(
    icon: Icons.auto_awesome_rounded,
    title: 'AI meal logging',
    proof: 'Photograph a plate or just describe it — calories and macros '
        'back in seconds. Nothing leaves your phone.',
    premium: true,
    goals: {FitnessGoal.loseFat, FitnessGoal.metabolicHealth},
  ),
  AppCapability(
    icon: Icons.fitness_center_rounded,
    title: 'Strength programmes that progress',
    proof: 'Proven programmes with guided sessions — weights go up on their '
        'own as you get stronger, so you never have to plan a session.',
    premium: true,
    goals: {FitnessGoal.buildMuscle},
  ),
  AppCapability(
    icon: Icons.insights_rounded,
    title: 'Insights that show the trend',
    proof: 'Longest, average and totals by month, quarter or year — so you '
        'can see progress on the weeks it does not feel like progress.',
    premium: true,
    goals: {
      FitnessGoal.loseFat,
      FitnessGoal.buildMuscle,
      FitnessGoal.metabolicHealth,
    },
  ),
];

/// Wear OS companion — Android only, no Apple Watch app in v1 (see
/// IOS_LAUNCH_CHECKLIST.md section 10).
const _wearCapability = AppCapability(
  icon: Icons.watch_rounded,
  title: 'Wear OS companion',
  proof: 'Your fast, your zone and your next set on your wrist, live — no '
      'phone needed mid-session.',
  premium: true,
  goals: {FitnessGoal.buildMuscle, FitnessGoal.metabolicHealth},
);

const _healthCapabilityAndroid = AppCapability(
  icon: Icons.favorite_rounded,
  title: 'Health Connect sync',
  proof: 'Meals, workouts and fasts flow both ways with the rest of your '
      'health data. Log it once, anywhere.',
  premium: true,
  goals: {FitnessGoal.loseFat, FitnessGoal.metabolicHealth},
);

/// Names Apple Health explicitly rather than a vague "health app" — the
/// intro/paywall should say plainly what it syncs with.
const _healthCapabilityIOS = AppCapability(
  icon: Icons.favorite_rounded,
  title: 'Apple Health sync',
  proof: 'Meals, workouts and fasts flow both ways with Apple Health — log '
      'it once, anywhere.',
  premium: true,
  goals: {FitnessGoal.loseFat, FitnessGoal.metabolicHealth},
);

/// Public, platform-filtered capability list shared by onboarding and the
/// paywall. No Wear OS card on iOS, and the health-sync card names the
/// actual app per platform (Health Connect on Android, Apple Health on
/// iOS) instead of a generic "health app".
List<AppCapability> get kCapabilities => [
      ..._baseCapabilities,
      if (Platform.isAndroid) _wearCapability,
      Platform.isAndroid ? _healthCapabilityAndroid : _healthCapabilityIOS,
    ];
