import 'package:hive/hive.dart';

part 'fast_record.g.dart';

@HiveType(typeId: 0)
class FastRecord extends HiveObject {
  @HiveField(0)
  late DateTime startTime;

  @HiveField(1)
  late DateTime endTime;

  @HiveField(2)
  late String protocol;

  /// Stable id for cloud sync (Firestore document id). Null on records
  /// created before sync existed — assigned lazily on first sync.
  @HiveField(3)
  String? syncId;

  FastRecord({
    required this.startTime,
    required this.endTime,
    required this.protocol,
    this.syncId,
  });

  Duration get duration => endTime.difference(startTime);

  String get formattedDuration {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }
}
