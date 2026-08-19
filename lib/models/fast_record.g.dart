// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'fast_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FastRecordAdapter extends TypeAdapter<FastRecord> {
  @override
  final int typeId = 0;

  @override
  FastRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FastRecord(
      startTime: fields[0] as DateTime,
      endTime: fields[1] as DateTime,
      protocol: fields[2] as String,
      syncId: fields[3] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FastRecord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.startTime)
      ..writeByte(1)
      ..write(obj.endTime)
      ..writeByte(2)
      ..write(obj.protocol)
      ..writeByte(3)
      ..write(obj.syncId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FastRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
