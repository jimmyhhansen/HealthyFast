import 'package:hive/hive.dart';

part 'meal_record.g.dart';

/// A logged meal, stored locally and (optionally) mirrored to Health Connect.
@HiveType(typeId: 1)
class MealRecord extends HiveObject {
  @HiveField(0)
  late DateTime time;

  @HiveField(1)
  late String name;

  @HiveField(2)
  late double calories;

  @HiveField(3)
  double? protein;

  @HiveField(4)
  double? carbs;

  @HiveField(5)
  double? fat;

  /// Health Connect MealType.name (e.g. "BREAKFAST", "LUNCH").
  @HiveField(6)
  late String mealType;

  /// JSON array of foods the AI extracted from the description, e.g.
  /// [{"n":"laks","g":150},{"n":"brokkoli","g":100}]. Filled in
  /// asynchronously after logging; null when extraction isn't available.
  @HiveField(7)
  String? foodsJson;

  /// Stable id for cloud sync (Firestore document id). Null on records
  /// created before sync existed — assigned lazily on first sync.
  @HiveField(8)
  String? syncId;

  MealRecord({
    required this.time,
    required this.name,
    required this.calories,
    this.protein,
    this.carbs,
    this.fat,
    required this.mealType,
    this.foodsJson,
    this.syncId,
  });
}
