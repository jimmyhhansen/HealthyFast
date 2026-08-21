import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wearable_rotary/wearable_rotary.dart';

import 'number_wheel_picker.dart';

/// Full-screen number wheels for Wear OS, driven by the rotating crown or
/// bezel.
///
/// Replaces the old +/- steppers on the watch. Those needed one tap per
/// 2.5 kg on a ~30px target, so going 20 kg → 60 kg meant sixteen taps at
/// arm's length, mid-set. A wheel gets there in one turn of the crown, and
/// the digits stay big enough to read without stopping.
///
/// Deliberately one value per screen: with two wheels side by side there is
/// no unambiguous answer to "which one does the crown drive", and guessing
/// wrong on a watch is worse than one extra tap.

/// Picks a weight, in kg. Returns null if the user swipes back.
Future<double?> showWearWeightPicker(
  BuildContext context, {
  required String exerciseName,
  required double kg,
  required bool isImperial,
}) async {
  final scale = WeightScale(isImperial: isImperial);
  final index = await Navigator.push<int>(
    context,
    MaterialPageRoute(
      builder: (_) => _WearWheelScreen(
        title: exerciseName,
        unit: scale.unit,
        itemCount: scale.count,
        initialIndex: scale.indexFor(kg),
        labelAt: scale.labelAt,
      ),
    ),
  );
  return index == null ? null : scale.kgAt(index);
}

/// Picks a rep count. Returns null if the user swipes back.
Future<int?> showWearRepsPicker(
  BuildContext context, {
  required String exerciseName,
  required int reps,
}) {
  return Navigator.push<int>(
    context,
    MaterialPageRoute(
      builder: (_) => _WearWheelScreen(
        title: exerciseName,
        unit: 'reps',
        itemCount: kMaxReps + 1,
        initialIndex: reps.clamp(0, kMaxReps),
        labelAt: (i) => '$i',
      ),
    ),
  );
}

class _WearWheelScreen extends StatefulWidget {
  const _WearWheelScreen({
    required this.title,
    required this.unit,
    required this.itemCount,
    required this.initialIndex,
    required this.labelAt,
  });

  final String title;
  final String unit;
  final int itemCount;
  final int initialIndex;
  final String Function(int index) labelAt;

  @override
  State<_WearWheelScreen> createState() => _WearWheelScreenState();
}

class _WearWheelScreenState extends State<_WearWheelScreen> {
  late final FixedExtentScrollController _ctrl =
      FixedExtentScrollController(initialItem: widget.initialIndex);
  StreamSubscription<RotaryEvent>? _rotary;

  late int _index = widget.initialIndex;

  @override
  void initState() {
    super.initState();
    _rotary = rotaryEvents.listen(_onRotary);
  }

  @override
  void dispose() {
    _rotary?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// One detent of the crown moves exactly one notch.
  ///
  /// Jumps rather than animates on purpose: an in-flight animation makes
  /// `selectedItem` lag behind, so a fast spin would read a stale position
  /// and start walking backwards. Crown detents are already discrete, so
  /// snapping straight to the next item is both correct and crisper.
  void _onRotary(RotaryEvent event) {
    if (!mounted || !_ctrl.hasClients) return;
    final delta = event.direction == RotaryDirection.clockwise ? 1 : -1;
    final current = _ctrl.selectedItem;
    final next = (current + delta).clamp(0, widget.itemCount - 1);
    if (next == current) return;
    _ctrl.jumpToItem(next);
  }

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide;
    // Same bezel-safe convention as WearScrollView: keep everything clear of
    // the clipped corners on round displays.
    final inset = side * 0.14;
    // Sized so title + unit + three wheel rows + button still clear the
    // shortest side on a 192dp watch, with headroom for a bumped system
    // font scale. A Column that overflows on Wear shows the striped bar.
    final itemExtent = side * 0.17;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                widget.unit,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              SizedBox(height: side * 0.02),
              Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          height: itemExtent,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  NumberWheel(
                    controller: _ctrl,
                    itemCount: widget.itemCount,
                    labelAt: widget.labelAt,
                    onChanged: (i) => setState(() => _index = i),
                    width: side * 0.52,
                    height: itemExtent * 3,
                    itemExtent: itemExtent,
                    fontSize: side * 0.13,
                    color: Colors.white,
                  ),
                ],
              ),
              SizedBox(height: side * 0.03),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade800,
                  minimumSize: Size(side * 0.46, 38),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.pop(context, _index),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Set',
                      style: TextStyle(fontSize: 14, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
