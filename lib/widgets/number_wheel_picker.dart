import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Kilograms in one pound. Weight is stored in kg everywhere in the app and
/// converted only for display, so imperial wheels count whole pounds and
/// convert on the way back out.
const double kgPerLb = 0.45359237;

/// The ladder of values a weight wheel offers, in *display* units.
///
/// Half-kilo (or single-pound) steps: fine enough for microplates, coarse
/// enough that one flick still crosses the whole useful range. The ceiling is
/// deliberately generous — leg press and hip thrust numbers get large.
class WeightScale {
  const WeightScale({required this.isImperial});

  final bool isImperial;

  double get step => isImperial ? 1.0 : 0.5;

  /// 0–1300 lbs, or 0–600 kg. Rendered lazily, so the length is free.
  int get count => isImperial ? 1301 : 1201;

  double displayAt(int index) => index * step;

  /// Nearest wheel position for a stored kg value.
  int indexFor(double kg) {
    final display = isImperial ? kg / kgPerLb : kg;
    return (display / step).round().clamp(0, count - 1);
  }

  /// Stored kg value for a wheel position.
  double kgAt(int index) =>
      isImperial ? displayAt(index) * kgPerLb : displayAt(index);

  String labelAt(int index) {
    final v = displayAt(index);
    return v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  }

  String get unit => isImperial ? 'lbs' : 'kg';
}

/// Highest reps the wheel offers. Past this you are not counting reps.
const int kMaxReps = 100;

/// One scrollable column of numbers.
///
/// Used by the phone sheet below and by the Wear picker in
/// `wear_number_picker.dart`, so the two platforms spin identically.
class NumberWheel extends StatelessWidget {
  const NumberWheel({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.labelAt,
    required this.onChanged,
    this.width = 108,
    this.height = 176,
    this.itemExtent = 44,
    this.fontSize = 26,
    this.color,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final String Function(int index) labelAt;
  final ValueChanged<int> onChanged;
  final double width;
  final double height;
  final double itemExtent;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: width,
      height: height,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: itemExtent,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.35,
        diameterRatio: 1.6,
        perspective: 0.004,
        onSelectedItemChanged: (i) {
          // The tick under the thumb is what makes a wheel feel mechanical
          // rather than like a list that happens to snap.
          HapticFeedback.selectionClick();
          onChanged(i);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: itemCount,
          builder: (ctx, i) => Center(
            // Scale-capped so large system font settings can't overflow the
            // fixed item height and clip the digits.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                labelAt(i),
                style: TextStyle(
                  color: fg,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for one number with the keyboard. The escape hatch from the wheel:
/// spinning is quicker for the nudges you make every set, but nobody wants
/// to flick 240 notches to jump from 20 kg to 140 kg.
Future<double?> promptForNumber(
  BuildContext context, {
  required String title,
  required String initial,
  required bool allowDecimal,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType:
            TextInputType.numberWithOptions(decimal: allowDecimal, signed: false),
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        decoration: const InputDecoration(border: OutlineInputBorder()),
        // Comma is the decimal separator on a Norwegian keyboard, and
        // double.parse only accepts a dot.
        onSubmitted: (v) =>
            Navigator.pop(ctx, double.tryParse(v.replaceAll(',', '.'))),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
              ctx, double.tryParse(ctrl.text.replaceAll(',', '.'))),
          child: const Text('OK'),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

/// Weight + reps for one set, chosen by spinning two wheels.
///
/// Returns null if dismissed. Weight comes back in **kg** regardless of the
/// unit the wheel displayed.
Future<({double kg, int reps})?> showSetPicker(
  BuildContext context, {
  required String title,
  required double kg,
  required int reps,
  required bool isImperial,
}) {
  return showModalBottomSheet<({double kg, int reps})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SetPickerSheet(
      title: title,
      kg: kg,
      reps: reps,
      isImperial: isImperial,
    ),
  );
}

class _SetPickerSheet extends StatefulWidget {
  const _SetPickerSheet({
    required this.title,
    required this.kg,
    required this.reps,
    required this.isImperial,
  });

  final String title;
  final double kg;
  final int reps;
  final bool isImperial;

  @override
  State<_SetPickerSheet> createState() => _SetPickerSheetState();
}

class _SetPickerSheetState extends State<_SetPickerSheet> {
  static const double _itemExtent = 44;
  static const double _wheelWidth = 108;
  static const double _gap = 12;

  late final WeightScale _scale = WeightScale(isImperial: widget.isImperial);
  late final FixedExtentScrollController _kgCtrl =
      FixedExtentScrollController(initialItem: _scale.indexFor(widget.kg));
  late final FixedExtentScrollController _repsCtrl =
      FixedExtentScrollController(initialItem: widget.reps.clamp(0, kMaxReps));

  late double _kg = widget.kg;
  late int _reps = widget.reps;

  @override
  void dispose() {
    _kgCtrl.dispose();
    _repsCtrl.dispose();
    super.dispose();
  }

  void _spinTo(FixedExtentScrollController ctrl, int index) {
    ctrl.animateToItem(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _typeWeight() async {
    final entered = await promptForNumber(
      context,
      title: 'Weight (${_scale.unit})',
      initial: _scale.labelAt(_scale.indexFor(_kg)),
      allowDecimal: true,
    );
    if (entered == null || !mounted) return;
    final asKg = widget.isImperial ? entered * kgPerLb : entered;
    final index = _scale.indexFor(asKg);
    _spinTo(_kgCtrl, index);
    setState(() => _kg = _scale.kgAt(index));
  }

  Future<void> _typeReps() async {
    final entered = await promptForNumber(
      context,
      title: 'Reps',
      initial: '$_reps',
      allowDecimal: false,
    );
    if (entered == null || !mounted) return;
    final index = entered.round().clamp(0, kMaxReps);
    _spinTo(_repsCtrl, index);
    setState(() => _reps = index);
  }

  /// Header sits OUTSIDE the wheel Stack on purpose. When the label row was
  /// inside it, the Stack's height was label + wheel, so centring the
  /// selection band in the Stack put it half a label-height above the row it
  /// was meant to highlight. Matching the wheel width here keeps each label
  /// over its own column without needing the band to know about them.
  Widget _headerLabel(String label, VoidCallback onType) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _wheelWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 2),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 17,
            tooltip: 'Type a number',
            icon: Icon(Icons.keyboard_rounded, color: scheme.primary),
            onPressed: onType,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _headerLabel(_scale.unit.toUpperCase(), _typeWeight),
                const SizedBox(width: _gap),
                _headerLabel('REPS', _typeReps),
              ],
            ),
            Stack(
              children: [
                // Selection band behind the centre row, so it reads as
                // "this is the chosen value" rather than "these are all
                // equally live". Only the wheels size this Stack, so the
                // band lands exactly on the selected item.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        height: _itemExtent,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NumberWheel(
                      controller: _kgCtrl,
                      itemCount: _scale.count,
                      width: _wheelWidth,
                      itemExtent: _itemExtent,
                      labelAt: _scale.labelAt,
                      onChanged: (i) => setState(() => _kg = _scale.kgAt(i)),
                    ),
                    const SizedBox(width: _gap),
                    NumberWheel(
                      controller: _repsCtrl,
                      itemCount: kMaxReps + 1,
                      width: _wheelWidth,
                      itemExtent: _itemExtent,
                      labelAt: (i) => '$i',
                      onChanged: (i) => setState(() => _reps = i),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, (kg: _kg, reps: _reps)),
                    child: const Text('Set'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
