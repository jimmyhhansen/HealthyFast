import 'package:hive/hive.dart';

part 'weight_record.g.dart';

/// A logged body weight. The journal treats weight as carry-forward:
/// a day shows the most recent weight logged on or before that day.
@HiveType(typeId: 2)
class WeightRecord extends HiveObject {
  @HiveField(0)
  late DateTime time;

  @HiveField(1)
  late double kg;

  /// Stable id for cloud sync (Firestore document id). Null on records
  /// created before sync existed — assigned lazily on first sync.
  @HiveField(2)
  String? syncId;

  WeightRecord({required this.time, required this.kg, this.syncId});
}
