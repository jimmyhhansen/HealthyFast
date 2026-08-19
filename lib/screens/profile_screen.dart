import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';

/// Energy profile: the inputs used to estimate daily calorie burn (TDEE),
/// with a live estimate at the bottom. Everything is optional except age,
/// height and weight; data never leaves the device.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _ageCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _ftCtrl;
  late final TextEditingController _inCtrl;
  late final TextEditingController _lbsCtrl;
  late final TextEditingController _overrideCtrl;

  @override
  void initState() {
    super.initState();
    final pp = context.read<ProfileProvider>();
    _ageCtrl = TextEditingController(text: pp.age?.toString() ?? '');
    _heightCtrl = TextEditingController(
        text: pp.heightCm == null ? '' : _trim(pp.heightCm!));
    _weightCtrl = TextEditingController(
        text: pp.weightKg == null ? '' : _trim(pp.weightKg!));
    _overrideCtrl = TextEditingController(
        text: pp.tdeeOverride == null ? '' : pp.tdeeOverride!.round().toString());

    _ftCtrl = TextEditingController();
    _inCtrl = TextEditingController();
    _lbsCtrl = TextEditingController();
    _updateControllersFromProvider(pp);
  }

  void _updateControllersFromProvider(ProfileProvider pp) {
    if (pp.heightCm != null) {
      _heightCtrl.text = _trim(pp.heightCm!);
      double totalInches = pp.heightCm! / 2.54;
      int feet = (totalInches / 12).floor();
      int inches = (totalInches % 12).round();
      if (inches == 12) {
        feet++;
        inches = 0;
      }
      _ftCtrl.text = feet.toString();
      _inCtrl.text = inches.toString();
    }
    if (pp.weightKg != null) {
      _weightCtrl.text = _trim(pp.weightKg!);
      _lbsCtrl.text = (pp.weightKg! / 0.45359237).round().toString();
    }
  }

  void _updateHeightImperial(ProfileProvider pp) {
    _profileChanged();
    final ft = double.tryParse(_ftCtrl.text.trim()) ?? 0;
    final inch = double.tryParse(_inCtrl.text.trim()) ?? 0;
    if (ft > 0 || inch > 0) {
      pp.setHeightCm((ft * 12 + inch) * 2.54);
    } else {
      pp.setHeightCm(null);
    }
  }

  void _updateWeightImperial(ProfileProvider pp) {
    _profileChanged();
    final lbs = double.tryParse(_lbsCtrl.text.trim());
    if (lbs != null && lbs > 0) {
      pp.setWeightKg(lbs * 0.45359237);
    } else {
      pp.setWeightKg(null);
    }
  }

  /// The provider clears a manual burn override whenever the profile
  /// changes; mirror that in the override text field.
  void _profileChanged() {
    if (_overrideCtrl.text.isNotEmpty) _overrideCtrl.clear();
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  @override
  void dispose() {
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _ftCtrl.dispose();
    _inCtrl.dispose();
    _lbsCtrl.dispose();
    _overrideCtrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label, String suffix) => InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        isDense: true,
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 18),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final scheme = Theme.of(context).colorScheme;
    final tdee = pp.tdee;

    return Scaffold(
      appBar: AppBar(title: const Text('Energy profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Used to estimate your daily calorie burn, so the Journal can '
              'show intake against burn. Stored only on this device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),

            _sectionLabel('Sex (for the formula)'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SexOption>(
                segments: const [
                  ButtonSegment(value: SexOption.male, label: Text('Male')),
                  ButtonSegment(value: SexOption.female, label: Text('Female')),
                  ButtonSegment(
                      value: SexOption.unspecified, label: Text('Skip')),
                ],
                selected: {pp.sex},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  _profileChanged();
                  pp.setSex(s.first);
                },
              ),
            ),

            _sectionLabel('Units'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<UnitSystem>(
                segments: const [
                  ButtonSegment(
                      value: UnitSystem.metric, label: Text('Kilograms & cm')),
                  ButtonSegment(
                      value: UnitSystem.imperial, label: Text('Pounds & feet')),
                ],
                selected: {pp.unitSystem},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  pp.setUnitSystem(s.first);
                  _updateControllersFromProvider(pp);
                },
              ),
            ),

            _sectionLabel('About you'),
            if (pp.unitSystem == UnitSystem.metric)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ageCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _decoration('Age', 'yrs'),
                      onChanged: (v) {
                        _profileChanged();
                        pp.setAge(int.tryParse(v.trim()));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _heightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: _decoration('Height', 'cm'),
                      onChanged: (v) {
                        _profileChanged();
                        pp.setHeightCm(double.tryParse(v.trim()));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: _decoration('Weight', 'kg'),
                      onChanged: (v) {
                        _profileChanged();
                        pp.setWeightKg(double.tryParse(v.trim()));
                      },
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ageCtrl,
                          keyboardType: TextInputType.number,
                          decoration: _decoration('Age', 'yrs'),
                          onChanged: (v) {
                            _profileChanged();
                            pp.setAge(int.tryParse(v.trim()));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _ftCtrl,
                          keyboardType: TextInputType.number,
                          decoration: _decoration('Height', 'ft'),
                          onChanged: (_) => _updateHeightImperial(pp),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _inCtrl,
                          keyboardType: TextInputType.number,
                          decoration: _decoration('', 'in'),
                          onChanged: (_) => _updateHeightImperial(pp),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lbsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: _decoration('Weight', 'lbs'),
                    onChanged: (_) => _updateWeightImperial(pp),
                  ),
                ],
              ),

            _sectionLabel('Activity level'),
            for (var i = 0; i < ProfileProvider.activityLabels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ChoiceChip(
                  label: SizedBox(
                    width: double.infinity,
                    child: Text(
                      '${ProfileProvider.activityLabels[i]} · '
                      '×${ProfileProvider.activityFactors[i]}',
                    ),
                  ),
                  selected: pp.activityIdx == i,
                  showCheckmark: false,
                  onSelected: (_) {
                    _profileChanged();
                    pp.setActivityIdx(i);
                  },
                ),
              ),

            _sectionLabel('How should training count?'),
            Text(
              'Weekly: your activity level above covers training. '
              'Per workout: baseline is sedentary and every logged '
              'workout adds a low-end burn estimate. Never both — no '
              'double counting.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'weekly', label: Text('Weekly estimate')),
                  ButtonSegment(
                      value: 'workout', label: Text('Per workout')),
                ],
                selected: {pp.burnMode},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  _profileChanged();
                  pp.setBurnMode(s.first);
                },
              ),
            ),

            _sectionLabel('Body type (optional)'),
            Text(
              'Refines the estimate — muscle burns more at rest, body fat '
              'less.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (type, label, note) in const [
                  (BodyType.lean, 'Lean', '+0%'),
                  (BodyType.average, 'Average', 'baseline'),
                  (BodyType.muscular, 'Muscular', '+6.5%'),
                  (BodyType.higherFat, 'Higher body fat', '−6.5%'),
                ])
                  ChoiceChip(
                    label: Text('$label · $note'),
                    selected: pp.bodyType == type,
                    showCheckmark: false,
                    onSelected: (_) {
                      _profileChanged();
                      pp.setBodyType(type);
                    },
                  ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Live estimate + manual override ───────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pp.tdeeOverride != null
                        ? 'DAILY BURN (MANUAL)'
                        : 'ESTIMATED DAILY BURN',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pp.effectiveTdee == null
                        ? '—'
                        : '${pp.effectiveTdee!.round()} kcal',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pp.tdeeOverride != null
                        ? 'Manual value. The estimate would be '
                            '${tdee == null ? '—' : '${tdee.round()} kcal'}.'
                        : tdee == null
                            ? 'Fill in age, height and weight to see the '
                                'estimate.'
                            : 'BMR (Mifflin-St Jeor) ${pp.bmr!.round()} kcal × '
                                'activity ×${ProfileProvider.activityFactors[pp.activityIdx]}'
                                '${pp.bodyType == BodyType.muscular ? ' +6.5% muscle' : pp.bodyType == BodyType.higherFat ? ' −6.5% body fat' : ''}. '
                                'An estimate, not a measurement.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _overrideCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Override daily burn (optional)',
                      suffixText: 'kcal',
                      helperText: 'Leave empty to use the estimate. Changing '
                          'the profile above clears the override.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        pp.setTdeeOverride(double.tryParse(v.trim())),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
