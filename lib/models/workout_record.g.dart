// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkoutRecordAdapter extends TypeAdapter<WorkoutRecord> {
  @override
  final int typeId = 3;

  @override
  WorkoutRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkoutRecord(
      startTime: fields[0] as DateTime,
      endTime: fields[1] as DateTime,
      title: fields[2] as String,
      exercisesJson: fields[3] as String?,
      programId: fields[4] as String?,
      programDayIdx: fields[5] as int?,
      source: fields[6] as String,
      activityType: fields[7] as String?,
      intensity: fields[8] as String?,
      syncId: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, WorkoutRecord obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.startTime)
      ..writeByte(1)
      ..write(obj.endTime)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.exercisesJson)
      ..writeByte(4)
      ..write(obj.programId)
      ..writeByte(5)
      ..write(obj.programDayIdx)
      ..writeByte(6)
      ..write(obj.source)
      ..writeByte(7)
      ..write(obj.activityType)
      ..writeByte(8)
      ..write(obj.intensity)
      ..writeByte(9)
      ..write(obj.syncId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
