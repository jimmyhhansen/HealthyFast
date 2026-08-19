import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/meal_record.dart';
import '../providers/fasting_provider.dart';

/// Opens the meal editor as a bottom sheet. Shared by the Journal and the
/// Meals dashboard so a logged meal can be edited (or deleted) from either.
Future<void> showMealEditor(
  BuildContext context,
  FastingProvider fp,
  MealRecord meal,
) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: MealEditor(meal: meal, fp: fp),
    ),
  );
}

/// Editable form for an existing meal, shown in a bottom sheet.
class MealEditor extends StatefulWidget {
  final MealRecord meal;
  final FastingProvider fp;
  const MealEditor({super.key, required this.meal, required this.fp});

  @override
  State<MealEditor> createState() => _MealEditorState();
}

class _MealEditorState extends State<MealEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.meal.name);
  late final TextEditingController _kcal =
      TextEditingController(text: widget.meal.calories.round().toString());
  late final TextEditingController _protein = TextEditingController(
      text: widget.meal.protein?.round().toString() ?? '');
  late final TextEditingController _carbs =
      TextEditingController(text: widget.meal.carbs?.round().toString() ?? '');
  late final TextEditingController _fat =
      TextEditingController(text: widget.meal.fat?.round().toString() ?? '');
  late String _mealType = widget.meal.mealType;
  late DateTime _time = widget.meal.time;

  static const _types = {
    'BREAKFAST': 'Breakfast',
    'LUNCH': 'Lunch',
    'DINNER': 'Dinner',
    'SNACK': 'Snack',
  };

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (t == null) return;
    setState(() => _time =
        DateTime(_time.year, _time.month, _time.day, t.hour, t.minute));
  }

  Future<void> _save() async {
    final kcal = double.tryParse(_kcal.text.trim());
    if (_name.text.trim().isEmpty || kcal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Name and calories are required.')));
      return;
    }
    await widget.fp.updateMeal(
      widget.meal,
      name: _name.text.trim(),
      calories: kcal,
      protein: double.tryParse(_protein.text.trim()),
      carbs: double.tryParse(_carbs.text.trim()),
      fat: double.tryParse(_fat.text.trim()),
      mealType: _mealType,
      time: _time,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await widget.fp.deleteMeal(widget.meal);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Meal',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final e in _types.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _mealType == e.key,
                  onSelected: (_) => setState(() => _mealType = e.key),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.schedule,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(DateFormat('HH:mm').format(_time)),
              TextButton(onPressed: _pickTime, child: const Text('Change')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _num(_kcal, 'Calories')),
              const SizedBox(width: 8),
              Expanded(child: _num(_protein, 'Protein (g)')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _num(_carbs, 'Carbs (g)')),
              const SizedBox(width: 8),
              Expanded(child: _num(_fat, 'Fat (g)')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                icon: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                label: Text('Delete',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                onPressed: _delete,
              ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
}
