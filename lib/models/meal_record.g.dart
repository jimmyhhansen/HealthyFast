// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meal_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MealRecordAdapter extends TypeAdapter<MealRecord> {
  @override
  final int typeId = 1;

  @override
  MealRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MealRecord(
      time: fields[0] as DateTime,
      name: fields[1] as String,
      calories: fields[2] as double,
      protein: fields[3] as double?,
      carbs: fields[4] as double?,
      fat: fields[5] as double?,
      mealType: fields[6] as String,
      foodsJson: fields[7] as String?,
      syncId: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MealRecord obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.time)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.calories)
      ..writeByte(3)
      ..write(obj.protein)
      ..writeByte(4)
      ..write(obj.carbs)
      ..writeByte(5)
      ..write(obj.fat)
      ..writeByte(6)
      ..write(obj.mealType)
      ..writeByte(7)
      ..write(obj.foodsJson)
      ..writeByte(8)
      ..write(obj.syncId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MealRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
