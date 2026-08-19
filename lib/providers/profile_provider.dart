import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/fitness_goal.dart';

/// Biological sex used by the BMR formula. "unspecified" uses the midpoint
/// of the male/female constants so the profile never forces a choice.
enum SexOption { male, female, unspecified }

/// Preferred unit system for height and weight.
enum UnitSystem { metric, imperial }

/// Optional body-composition hint that refines the estimate: muscle burns
/// more at rest, body fat less. Mifflin-St Jeor assumes average composition.
enum BodyType { lean, average, muscular, higherFat }

/// The user's energy profile: the inputs needed to estimate daily calorie
/// burn (TDEE), stored locally in SharedPreferences. Nothing leaves the
/// device.
///
/// BMR uses Mifflin-St Jeor:
///   10×weight(kg) + 6.25×height(cm) − 5×age + 5 (male) / −161 (female)
/// TDEE = BMR × activity factor, adjusted ±6.5% for body type.
class ProfileProvider extends ChangeNotifier {
  static const _kSex = 'profile_sex';
  static const _kAge = 'profile_age';
  static const _kHeight = 'profile_height_cm';
  static const _kWeight = 'profile_weight_kg';
  static const _kActivity = 'profile_activity_idx'; // legacy, 3 levels
  static const _kActivityV2 = 'profile_activity_idx_v2'; // 5 levels
  static const _kBodyType = 'profile_body_type';
  static const _kTdeeOverride = 'profile_tdee_override';
  static const _kBurnMode = 'profile_burn_mode';
  static const _kUnitSystem = 'profile_unit_system';
  static const _kGoal = 'profile_goal';

  /// Set once the welcome flow has been completed (or skipped). Also used
  /// by main() before the first frame, hence the public constant.
  static const kOnboardingDone = 'onboarding_complete_v1';

  /// Standard TDEE multipliers (sedentary → extra active).
  static const activityFactors = [1.2, 1.375, 1.55, 1.725, 1.9];
  static const activityLabels = [
    'Mostly sitting',
    'Light — walks or 1–2 workouts/week',
    'Moderate — active job or 3–5 workouts/week',
    'Very active — hard training most days',
    'Extra — physical job plus daily training',
  ];
  static const activityShortLabels = [
    'Mostly sitting',
    'Lightly active',
    'Moderately active',
    'Very active',
    'Extra active',
  ];

  SexOption _sex = SexOption.unspecified;
  int? _age;
  double? _heightCm;
  double? _weightKg;
  int _activityIdx = 2;
  BodyType _bodyType = BodyType.average;
  double? _tdeeOverride;
  UnitSystem _unitSystem = UnitSystem.metric;
  FitnessGoal _goal = FitnessGoal.everything;

  SexOption get sex => _sex;
  int? get age => _age;
  double? get heightCm => _heightCm;
  double? get weightKg => _weightKg;
  int get activityIdx => _activityIdx;
  BodyType get bodyType => _bodyType;
  UnitSystem get unitSystem => _unitSystem;

  /// What the user asked the app to help with. Shapes which capabilities
  /// onboarding leads with and how the calorie target is framed — never
  /// restricts access to anything.
  FitnessGoal get goal => _goal;

  /// Manual daily-burn override, if the user has set one.
  double? get tdeeOverride => _tdeeOverride;

  /// How training enters the burn — exactly one of:
  ///  'weekly'  — the activity level bakes training into the TDEE
  ///              (logged workouts do NOT add on top);
  ///  'workout' — TDEE uses a sedentary baseline (×1.2) and every
  ///              logged workout adds its own low-end estimate.
  /// Prevents double counting either way.
  String _burnMode = 'weekly';
  String get burnMode => _burnMode;

  Future<void> setBurnMode(String v) async {
    _burnMode = v == 'workout' ? 'workout' : 'weekly';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBurnMode, _burnMode);
  }

  /// True once age, height and weight are all set.
  bool get isComplete => _age != null && _heightCm != null && _weightKg != null;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sex = SexOption.values[
        (prefs.getInt(_kSex) ?? SexOption.unspecified.index)
            .clamp(0, SexOption.values.length - 1)];
    _age = prefs.getInt(_kAge);
    _heightCm = prefs.getDouble(_kHeight);
    _weightKg = prefs.getDouble(_kWeight);
    final v2 = prefs.getInt(_kActivityV2);
    if (v2 != null) {
      _activityIdx = v2.clamp(0, activityFactors.length - 1);
    } else {
      // Migrate from the old 3-level scale (×1.2 / ×1.55 / ×1.73).
      final legacy = prefs.getInt(_kActivity);
      _activityIdx = switch (legacy) {
        0 => 0, // sedentary → sedentary
        1 => 2, // moderate → moderate
        2 => 3, // hard → very active
        _ => 2,
      };
    }
    _bodyType = BodyType.values[
        (prefs.getInt(_kBodyType) ?? BodyType.average.index)
            .clamp(0, BodyType.values.length - 1)];
    _tdeeOverride = prefs.getDouble(_kTdeeOverride);
    _burnMode = prefs.getString(_kBurnMode) ?? 'weekly';
    _unitSystem = UnitSystem.values[
        (prefs.getInt(_kUnitSystem) ?? UnitSystem.metric.index)
            .clamp(0, UnitSystem.values.length - 1)];
    _goal = FitnessGoalInfo.fromIndex(prefs.getInt(_kGoal));
    notifyListeners();
  }

  Future<void> setGoal(FitnessGoal v) async {
    _goal = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGoal, v.index);
  }

  /// Marks the welcome flow as seen so it never reappears on launch.
  Future<void> markOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingDone, true);
  }

  /// Daily calorie target implied by the profile and the chosen goal, or
  /// null while the profile is incomplete.
  double? get goalCalorieTarget {
    final t = effectiveTdee;
    return t == null ? null : t * _goal.calorieFactor;
  }

  /// Any profile change invalidates a manual burn override — the fresh
  /// estimate wins until the user overrides it again.
  Future<void> _clearOverride(SharedPreferences prefs) async {
    if (_tdeeOverride == null) return;
    _tdeeOverride = null;
    await prefs.remove(_kTdeeOverride);
  }

  /// Sets (or clears, with null) the manual daily-burn override.
  Future<void> setTdeeOverride(double? v) async {
    _tdeeOverride = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_kTdeeOverride);
    } else {
      await prefs.setDouble(_kTdeeOverride, v);
    }
  }

  Future<void> setSex(SexOption v) async {
    _sex = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _clearOverride(prefs);
    await prefs.setInt(_kSex, v.index);
    notifyListeners();
  }

  Future<void> setAge(int? v) async {
    _age = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _clearOverride(prefs);
    if (v == null) {
      await prefs.remove(_kAge);
    } else {
      await prefs.setInt(_kAge, v);
    }
    notifyListeners();
  }

  Future<void> setHeightCm(double? v) async {
    _heightCm = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _clearOverride(prefs);
    if (v == null) {
      await prefs.remove(_kHeight);
    } else {
      await prefs.setDouble(_kHeight, v);
    }
    notifyListeners();
  }

  Future<void> setWeightKg(double? v) async {
    _weightKg = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _clearOverride(prefs);
    if (v == null) {
      await prefs.remove(_kWeight);
    } else {
      await prefs.setDouble(_kWeight, v);
    }
    notifyListeners();
  }

  Future<void> setActivityIdx(int v) async {
    _activityIdx = v.clamp(0, activityFactors.length - 1);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _clearOverride(prefs);
    await prefs.setInt(_kActivityV2, _activityIdx);
    notifyListeners();
  }

  Future<void> setBodyType(BodyType v) async {
    _bodyType = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await _clearOverride(prefs);
    await prefs.setInt(_kBodyType, v.index);
    notifyListeners();
  }

  Future<void> setUnitSystem(UnitSystem v) async {
    _unitSystem = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUnitSystem, v.index);
  }

  /// Basal metabolic rate (kcal/day), or null while the profile is
  /// incomplete.
  double? get bmr {
    if (!isComplete) return null;
    final base = 10 * _weightKg! + 6.25 * _heightCm! - 5 * _age!;
    final sexTerm = switch (_sex) {
      SexOption.male => 5.0,
      SexOption.female => -161.0,
      SexOption.unspecified => -78.0,
    };
    return base + sexTerm;
  }

  /// Estimated total daily energy expenditure (kcal/day), or null while
  /// the profile is incomplete.
  double? get tdee {
    final b = bmr;
    if (b == null) return null;
    final adj = switch (_bodyType) {
      BodyType.muscular => 1.065,
      BodyType.higherFat => 0.935,
      BodyType.lean || BodyType.average => 1.0,
    };
    // In 'workout' mode training is counted per logged workout instead,
    // so the base TDEE stays at the sedentary factor.
    final factor =
        _burnMode == 'workout' ? 1.2 : activityFactors[_activityIdx];
    return b * factor * adj;
  }

  /// Daily burn the app should use: the manual override when set,
  /// otherwise the estimate.
  double? get effectiveTdee => _tdeeOverride ?? tdee;
}
