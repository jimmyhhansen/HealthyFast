import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/fitness_goal.dart';
import '../providers/profile_provider.dart';
import '../services/cloud_ai_consent_service.dart';
import '../services/meal_estimator_service.dart';
import '../services/notification_service.dart';
import '../widgets/cloud_ai_consent_sheet.dart';
import 'onboarding_summary_screen.dart';

/// Seven-question guided setup of the energy profile. Each step saves
/// immediately, so closing midway keeps what was answered. The step counter
/// ("1 of 7") is always visible.
///
/// With [introMode] on it doubles as the middle of the welcome flow:
///  - each question carries a capability card matched to the user's chosen
///    goal, so the app demonstrates itself while they are already answering
///    and it costs them no extra taps;
///  - two steps are appended — the daily reminder and the AI engine choice
///    (9 total) — because both are decisions users otherwise never find;
///  - the last step hands off to [OnboardingSummaryScreen] rather than
///    just closing.
class ProfileWizardScreen extends StatefulWidget {
  const ProfileWizardScreen({super.key, this.introMode = false});

  final bool introMode;

  @override
  State<ProfileWizardScreen> createState() => _ProfileWizardScreenState();
}

class _ProfileWizardScreenState extends State<ProfileWizardScreen> {
  /// The welcome flow adds two steps at the end — the daily reminder and
  /// the AI engine choice — because both are worth far more on day one than
  /// buried in Settings. Re-opening from Settings keeps the original 7.
  int get _totalSteps => widget.introMode ? 9 : 7;
  int _step = 0;

  // Daily-reminder step state, seeded from NotificationService.
  bool _remindersOn = true;
  int _reminderHour = 20;
  int _reminderMin = 0;

  // AI engine step state.
  NanoStatus _nanoStatus = NanoStatus.unavailable;
  bool _nanoChecked = false;
  bool _nanoDownloading = false;
  bool _nanoFailed = false;
  CloudAiConsent _cloudConsent = CloudAiConsent.notAsked;

  final _ageCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  final _heightFtCtrl = TextEditingController();
  final _heightInCtrl = TextEditingController();
  final _weightLbsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final pp = context.read<ProfileProvider>();
    _ageCtrl.text = pp.age?.toString() ?? '';
    _updateControllersFromProvider(pp);
    if (widget.introMode) {
      _loadReminderDefaults();
      _loadAiState();
    }
  }

  Future<void> _loadAiState() async {
    final status = await MealEstimatorService.checkStatus();
    final consent = await CloudAiConsentService.get();
    if (!mounted) return;
    setState(() {
      _nanoStatus = status;
      _cloudConsent = consent;
      _nanoChecked = true;
    });
  }

  /// Starts the on-device model download.
  ///
  /// Deliberately fire-and-forget: the native side (AICore) owns the actual
  /// transfer, so it keeps running even after this screen is popped. Nothing
  /// here gates the Next button, and the `mounted` check means finishing
  /// after disposal is harmless. The user never waits on it.
  Future<void> _downloadNano() async {
    if (_nanoDownloading) return;
    setState(() {
      _nanoDownloading = true;
      _nanoFailed = false;
    });
    final ok = await MealEstimatorService.downloadModel();
    final status = await MealEstimatorService.checkStatus();
    if (!mounted) return;
    setState(() {
      _nanoDownloading = false;
      _nanoStatus = status;
      _nanoFailed = !ok && status != NanoStatus.available;
    });
  }

  /// Cloud AI needs informed consent, so this opens the existing disclosure
  /// sheet rather than flipping the flag silently.
  ///
  /// The sheet has two voices: the default explains that this phone *can't*
  /// run AI on-device, which would be plainly false on a Pixel 9. Since
  /// cloud is now offered first regardless of hardware, capable phones get
  /// the `upsell` copy ("more capable than on-device") instead.
  Future<void> _chooseCloud() async {
    final nanoCapable = _nanoStatus != NanoStatus.unavailable;
    final accept = await showCloudAiConsentSheet(
      context,
      feature: 'meal estimates and AI programs',
      upsell: nanoCapable,
    );
    if (accept == null) return;
    await CloudAiConsentService.set(
        accept ? CloudAiConsent.accepted : CloudAiConsent.declined);
    if (!mounted) return;
    setState(() => _cloudConsent =
        accept ? CloudAiConsent.accepted : CloudAiConsent.declined);
  }

  Future<void> _loadReminderDefaults() async {
    final (h, m) = await NotificationService.getReminderTime();
    if (!mounted) return;
    setState(() {
      _reminderHour = h;
      _reminderMin = m;
    });
  }

  /// Persists the reminder choice. Called when leaving the last step, so a
  /// user who backs out never gets notifications they did not confirm.
  Future<void> _saveReminder() async {
    // Ask for the OS permission only once they have said yes — a permission
    // prompt with no context in front of it is the fastest way to get denied.
    // Only the simple popup here — requestPermissions() also opens the
    // Android 14 "Alarms & reminders" system screen, which is too jarring
    // mid-flow. RootScreen handles that once they land in the app.
    if (_remindersOn) {
      await NotificationService.requestNotificationsPermission();
    }
    await NotificationService.setReminderTime(_reminderHour, _reminderMin);
    await NotificationService.setReminderEnabled(_remindersOn);
  }

  void _updateControllersFromProvider(ProfileProvider pp) {
    _heightCtrl.text = pp.heightCm?.round().toString() ?? '';
    _weightCtrl.text = pp.weightKg?.round().toString() ?? '';

    if (pp.heightCm != null) {
      double totalInches = pp.heightCm! / 2.54;
      int feet = (totalInches / 12).floor();
      int inches = (totalInches % 12).round();
      if (inches == 12) {
        feet++;
        inches = 0;
      }
      _heightFtCtrl.text = feet.toString();
      _heightInCtrl.text = inches.toString();
    }
    if (pp.weightKg != null) {
      _weightLbsCtrl.text = (pp.weightKg! / 0.45359237).round().toString();
    }
  }

  @override
  void dispose() {
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _heightFtCtrl.dispose();
    _heightInCtrl.dispose();
    _weightLbsCtrl.dispose();
    super.dispose();
  }

  void _updateHeightImperial(ProfileProvider pp) {
    final ft = double.tryParse(_heightFtCtrl.text.trim()) ?? 0;
    final inch = double.tryParse(_heightInCtrl.text.trim()) ?? 0;
    if (ft > 0 || inch > 0) {
      pp.setHeightCm((ft * 12 + inch) * 2.54);
    } else {
      pp.setHeightCm(null);
    }
  }

  void _updateWeightImperial(ProfileProvider pp) {
    final lbs = double.tryParse(_weightLbsCtrl.text.trim());
    if (lbs != null && lbs > 0) {
      pp.setWeightKg(lbs * 0.45359237);
    } else {
      pp.setWeightKg(null);
    }
  }

  /// Index of the daily-reminder step in intro mode.
  static const _reminderStep = 7;

  void _next() {
    if (_step < _totalSteps - 1) {
      // Save (and ask for the OS permission) as they leave the reminder
      // step, so the system prompt appears while that question is still
      // the thing on screen.
      if (widget.introMode && _step == _reminderStep) _saveReminder();
      setState(() => _step++);
      return;
    }
    if (widget.introMode) {
      _finishIntro();
      return;
    }
    Navigator.pop(context, true);
  }

  /// Last step of the welcome flow: show the personalised plan, then report
  /// success back so the welcome screen can drop into the app.
  void _finishIntro() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingSummaryScreen(
          onDone: () {
            // Pop the summary, then the wizard itself.
            Navigator.of(context).pop();
            Navigator.of(context).pop(true);
          },
        ),
      ),
    );
  }

  /// The capability shown alongside the current question, or null once we
  /// run out of ones matching the user's goal.
  AppCapability? _teaserFor(int step, FitnessGoal goal) {
    if (!widget.introMode) return null;
    final matched = kCapabilities.where((c) => c.matches(goal)).toList();
    return step < matched.length ? matched[step] : null;
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  bool get _stepValid {
    final pp = context.read<ProfileProvider>();
    return switch (_step) {
      1 => pp.age != null,
      3 => pp.heightCm != null,
      4 => pp.weightKg != null,
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<ProfileProvider>();
    final scheme = Theme.of(context).colorScheme;
    final teaser = _teaserFor(_step, pp.goal);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.introMode,
        title: Text(widget.introMode ? 'Setting you up' : 'Energy profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_step + 1} of $_totalSteps',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / _totalSteps,
            minHeight: 4,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStep(pp, scheme),
                      if (teaser != null) ...[
                        const SizedBox(height: 28),
                        _CapabilityTeaser(
                          key: ValueKey(teaser.title),
                          capability: teaser,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  if (_step > 0)
                    TextButton(onPressed: _back, child: const Text('Back')),
                  const Spacer(),
                  FilledButton(
                    onPressed: _stepValid ? _next : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(140, 48),
                    ),
                    child: Text(_step < _totalSteps - 1
                        ? 'Next'
                        : widget.introMode
                            ? 'See my plan'
                            : 'Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _question(String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                )),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStep(ProfileProvider pp, ColorScheme scheme) {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _question(
              'Which formula fits you best?',
              'Biological sex changes the calorie formula slightly. '
                  'Skip uses a neutral middle value.',
            ),
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
                onSelectionChanged: (s) => pp.setSex(s.first),
              ),
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _question('How old are you?',
                'Calorie burn falls slightly with age.'),
            TextField(
              controller: _ageCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Age',
                suffixText: 'years',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => pp.setAge(int.tryParse(v.trim())),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _question(
              'Units',
              'Choose your preferred unit system for height and weight.',
            ),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<UnitSystem>(
                segments: const [
                  ButtonSegment(
                    value: UnitSystem.metric,
                    label: Text('Kilograms & cm'),
                  ),
                  ButtonSegment(
                    value: UnitSystem.imperial,
                    label: Text('Pounds & feet'),
                  ),
                ],
                selected: {pp.unitSystem},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  pp.setUnitSystem(s.first);
                  _updateControllersFromProvider(pp);
                },
              ),
            ),
          ],
        );
      case 3:
        final isMetric = pp.unitSystem == UnitSystem.metric;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _question('How tall are you?', 'Used by the calorie formula.'),
            if (isMetric)
              TextField(
                controller: _heightCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Height',
                  suffixText: 'cm',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => pp.setHeightCm(double.tryParse(v.trim())),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _heightFtCtrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Feet',
                        suffixText: 'ft',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _updateHeightImperial(pp),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _heightInCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Inches',
                        suffixText: 'in',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _updateHeightImperial(pp),
                    ),
                  ),
                ],
              ),
          ],
        );
      case 4:
        final isMetric = pp.unitSystem == UnitSystem.metric;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _question('What do you weigh?',
                'An estimate is fine — you can adjust it any time.'),
            TextField(
              controller: isMetric ? _weightCtrl : _weightLbsCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Weight',
                suffixText: isMetric ? 'kg' : 'lbs',
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                if (isMetric) {
                  pp.setWeightKg(double.tryParse(v.trim()));
                } else {
                  _updateWeightImperial(pp);
                }
              },
            ),
          ],
        );
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _question('How active are you?',
                'Daily movement and training, not just workouts.'),
            for (var i = 0; i < ProfileProvider.activityLabels.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ChoiceChip(
                  label: SizedBox(
                    width: double.infinity,
                    child: Text(ProfileProvider.activityLabels[i]),
                  ),
                  selected: pp.activityIdx == i,
                  showCheckmark: false,
                  onSelected: (_) => pp.setActivityIdx(i),
                ),
              ),
          ],
        );
      case 6:
        final tdee = pp.tdee;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _question('How would you describe your body type?',
                'Optional — muscle burns more at rest, body fat less.'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (type, label) in const [
                  (BodyType.lean, 'Lean'),
                  (BodyType.average, 'Average'),
                  (BodyType.muscular, 'Muscular'),
                  (BodyType.higherFat, 'Higher body fat'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: pp.bodyType == type,
                    showCheckmark: false,
                    onSelected: (_) => pp.setBodyType(type),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            if (tdee != null)
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
                      'YOUR ESTIMATED DAILY BURN',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${tdee.round()} kcal',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Meals you log are compared against this. Adjust '
                      'anytime in Settings → Energy profile.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
          ],
        );

      // Intro flow only — the habit question.
      case 7:
        return _buildReminderStep(scheme);

      // Intro flow only — where the AI runs.
      default:
        return _buildAiStep(scheme);
    }
  }

  /// Lets the user turn on AI up front, framed as a privacy decision rather
  /// than a technical one.
  ///
  /// Cloud leads deliberately: on-device Gemini Nano needs a Pixel 8+ or
  /// Galaxy S25+, so leading with it means most users see the headline
  /// premium feature as unavailable on their very first run. Cloud works on
  /// every phone, so it is the default path, and on-device is offered
  /// underneath as a privacy upgrade for the hardware that supports it.
  Widget _buildAiStep(ColorScheme scheme) {
    final text = Theme.of(context).textTheme;
    final nanoReady = _nanoStatus == NanoStatus.available;
    // The OS may already have a transfer in flight from a previous session,
    // so treat that as busy too rather than offering "Download now" again.
    final downloading =
        _nanoDownloading || _nanoStatus == NanoStatus.downloading;
    final nanoPossible = _nanoStatus == NanoStatus.downloadable ||
        _nanoStatus == NanoStatus.downloading;
    final cloudOn = _cloudConsent == CloudAiConsent.accepted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _question(
          'Turn on AI meal logging?',
          'Photograph a plate or just describe it, and get calories and '
              'macros back in seconds.',
        ),
        if (!_nanoChecked)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          // Primary path — works on every phone.
          _AiOptionCard(
            icon: Icons.cloud_rounded,
            title: 'Yes, turn it on',
            body: cloudOn
                ? 'Ready. Works on any phone, and handles longer, messier '
                    'descriptions best.'
                : 'Works on any phone and handles longer descriptions best. '
                    'The text you write is sent to Google to process — '
                    'nothing else from HealthyFast goes with it.',
            selected: cloudOn,
            busy: false,
            statusLabel: cloudOn ? 'On' : null,
            actionLabel: cloudOn ? null : 'Turn on',
            onTap: cloudOn ? null : _chooseCloud,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Divider(color: scheme.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'OR, IF YOUR PHONE SUPPORTS IT',
                  style: text.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(child: Divider(color: scheme.outlineVariant)),
            ],
          ),
          const SizedBox(height: 14),
          // Secondary path — a privacy upgrade, only on capable hardware.
          if (nanoReady || nanoPossible)
            _AiOptionCard(
              icon: Icons.lock_rounded,
              title: 'Keep it all on this phone',
              body: nanoReady
                  ? 'On-device AI is installed. Nothing you log ever leaves '
                      'this phone, and it works offline.'
                  : downloading
                      ? 'Downloading in the background — carry on, you don\'t '
                          'need to wait here. It works offline once it lands.'
                      : 'Your phone can run the AI itself, so nothing you log '
                          'leaves the device and it works offline. Needs a '
                          'one-time download; Wi-Fi recommended.',
              selected: nanoReady,
              busy: downloading,
              statusLabel: nanoReady
                  ? 'Installed'
                  : downloading
                      ? 'Downloading…'
                      : null,
              actionLabel: nanoReady || downloading ? null : 'Download now',
              onTap: nanoReady || downloading ? null : _downloadNano,
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Running the AI fully offline needs a recent flagship '
                      '(Pixel 8+, Galaxy S25+). This phone isn\'t one, so '
                      'the option above is the way to go.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_nanoFailed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'That download didn\'t finish. You can retry here or later '
                'in Settings → Cloud & AI.',
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          const SizedBox(height: 14),
          Text(
            'You can pick either, both, or neither — and change it any time '
            'in Settings → Cloud & AI.',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  /// Asking for the reminder here, right after showing the user their own
  /// numbers, is the moment they care most. It also front-loads the single
  /// biggest driver of week-two retention.
  Widget _buildReminderStep(ColorScheme scheme) {
    final text = Theme.of(context).textTheme;
    final time = TimeOfDay(hour: _reminderHour, minute: _reminderMin);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _question(
          'Want a nudge to start your fast?',
          'One quiet notification a day. Off in Settings any time.',
        ),
        Row(
          children: [
            Expanded(
              child: _ChoiceTile(
                icon: Icons.notifications_active_rounded,
                label: 'Yes, remind me',
                selected: _remindersOn,
                onTap: () => setState(() => _remindersOn = true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ChoiceTile(
                icon: Icons.notifications_off_rounded,
                label: 'No thanks',
                selected: !_remindersOn,
                onTap: () => setState(() => _remindersOn = false),
              ),
            ),
          ],
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _remindersOn
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHAT TIME?',
                  style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (h, label) in const [
                      (7, 'Morning · 07:00'),
                      (12, 'Midday · 12:00'),
                      (18, 'Evening · 18:00'),
                      (20, 'Night · 20:00'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        showCheckmark: false,
                        selected: _reminderHour == h && _reminderMin == 0,
                        onSelected: (_) => setState(() {
                          _reminderHour = h;
                          _reminderMin = 0;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (picked == null || !mounted) return;
                    setState(() {
                      _reminderHour = picked.hour;
                      _reminderMin = picked.minute;
                    });
                  },
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text('Pick another time · ${time.format(context)}'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                ),
              ],
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// One AI engine option: what it is, what it costs you in privacy, and a
/// single action. Both options can be active at once, so this is a set of
/// independent cards rather than a radio group.
class _AiOptionCard extends StatelessWidget {
  const _AiOptionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.busy,
    required this.statusLabel,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final bool busy;
  final String? statusLabel;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style:
                      text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (statusLabel != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 16, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel!,
                      style: text.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: busy ? null : onTap,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Large tap target used by the yes/no reminder question.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Column(
              children: [
                Icon(icon,
                    size: 24,
                    color:
                        selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single capability, revealed under the question the user is answering.
///
/// It costs no taps and blocks nothing — by the time the profile is done,
/// the user has been shown the whole product without ever sitting through a
/// feature tour. Premium items are labelled honestly rather than hidden.
class _CapabilityTeaser extends StatefulWidget {
  const _CapabilityTeaser({super.key, required this.capability});

  final AppCapability capability;

  @override
  State<_CapabilityTeaser> createState() => _CapabilityTeaserState();
}

class _CapabilityTeaserState extends State<_CapabilityTeaser>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  // Typed as CurvedAnimation, not Animation<double> — dispose() only
  // exists on the concrete type.
  late final CurvedAnimation _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final cap = widget.capability;

    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - _a.value)),
          child: child,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  cap.premium ? 'ALSO IN HEALTHYFAST' : 'FREE, FROM DAY ONE',
                  style: text.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                    color: scheme.primary,
                  ),
                ),
                const Spacer(),
                if (cap.premium)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'PREMIUM',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(cap.icon, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cap.title,
                        style: text.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cap.proof,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
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
