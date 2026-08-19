import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/meal_record.dart';
import '../providers/fasting_provider.dart';
import '../services/cloud_ai_service.dart';
import '../services/debug_log_service.dart';
import '../services/health_sync_service.dart';
import '../services/meal_estimator_service.dart';
import '../widgets/cloud_ai_consent_sheet.dart';

/// Log a meal: describe it in free text, let on-device AI (Gemini Nano)
/// estimate calories and macros, adjust if needed, save to Health Connect.
/// Supports logging in retrospect: [initialDate] presets the day (e.g. the
/// day selected in the Journal), and both date and time can be changed.
class MealsScreen extends StatefulWidget {
  const MealsScreen({super.key, this.initialDate});

  /// Day the meal defaults to; today when null.
  final DateTime? initialDate;

  @override
  State<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends State<MealsScreen> {
  final _descriptionController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _dictationBase = '';
  bool _analyzingPhoto = false;

  NanoStatus _nanoStatus = NanoStatus.unavailable;
  bool _estimating = false;
  bool _downloading = false;
  bool _saving = false;
  bool _estimated = false;
  MealType _mealType = MealType.LUNCH;
  DateTime _time = DateTime.now();

  static const _mealTypes = {
    MealType.BREAKFAST: 'Breakfast',
    MealType.LUNCH: 'Lunch',
    MealType.DINNER: 'Dinner',
    MealType.SNACK: 'Snack',
  };

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate;
    if (d != null) {
      final now = DateTime.now();
      var t = DateTime(d.year, d.month, d.day, now.hour, now.minute);
      // A future day can't hold a meal — fall back to now.
      if (t.isAfter(now)) t = now;
      _time = t;
    }
    _refreshNanoStatus();
  }

  @override
  void dispose() {
    _speech.cancel();
    _descriptionController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  Future<void> _refreshNanoStatus() async {
    final status = await MealEstimatorService.checkStatus();
    if (mounted) setState(() => _nanoStatus = status);
  }

  /// Photo → description → editable text in the field. Prefers on-device
  /// AI whenever it's available — same as text entry — and only reaches
  /// out to the cloud when it isn't. Two distinct devices route to cloud:
  /// phones with no Gemini Nano at all (resolveAiPath sends these to
  /// cloud/manual directly, same decision as _estimate), and phones that
  /// have Nano for text but fail specifically on the multimodal (image)
  /// path — a real, documented gap, see MealEstimatorService.describePhoto.
  /// Either way the user reviews the text before running the normal
  /// Estimate; this screen itself is already premium-gated (see
  /// meals_dashboard_screen.dart), so no separate premium check is needed
  /// here.
  Future<void> _scanPhoto() async {
    final path = await resolveAiPath(context, _nanoStatus, feature: 'meal photos');
    await DebugLogService.log('ScanPhoto',
        'resolveAiPath -> $path (nanoStatus=$_nanoStatus)');
    if (!mounted) return;
    if (path == AiPath.manual) {
      _snack('Describe the meal in text instead.');
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 85,
      );
    } catch (_) {
      _snack('Could not open the ${source == ImageSource.camera ? 'camera' : 'gallery'}.');
      return;
    }
    if (photo == null || !mounted) return;
    await DebugLogService.log(
        'ScanPhoto', 'picked photo from $source: ${photo.path}');

    setState(() => _analyzingPhoto = true);
    String? description;
    String? quotaMessage;
    try {
      if (path == AiPath.cloud) {
        description = await CloudAiService.describeMealPhoto(photo.path);
      } else {
        description = await MealEstimatorService.describePhoto(photo.path);
        if (description == null && mounted) {
          // Nano handles text but not this photo — the documented gap in
          // describePhoto's contract. Offer the same cloud AI the user may
          // have already consented to, rather than dead-ending here.
          await DebugLogService.log('ScanPhoto',
              'on-device describePhoto returned null, offering cloud fallback');
          final useCloud =
              await resolveCloudAiUsage(context, feature: 'meal photos');
          if (useCloud && mounted) {
            description = await CloudAiService.describeMealPhoto(photo.path);
          } else {
            await DebugLogService.log(
                'ScanPhoto', 'user declined cloud fallback');
          }
        }
      }
    } on CloudAiQuotaExceededException catch (e) {
      quotaMessage = e.message;
    } catch (e) {
      await DebugLogService.log('ScanPhoto', 'unexpected error: $e');
      description = null;
    }
    if (!mounted) return;
    setState(() => _analyzingPhoto = false);
    await DebugLogService.log(
        'ScanPhoto',
        'outcome: quotaMessage=$quotaMessage description='
        '${description == null ? "null" : "${description.length} chars"}');

    if (quotaMessage != null) {
      _snack(quotaMessage);
      return;
    }
    if (description == null) {
      _snack('Could not read the photo. Describe the meal in text instead.');
      return;
    }
    final existing = _descriptionController.text.trim();
    _descriptionController.text =
        existing.isEmpty ? description : '$existing $description';
    _snack('Photo analyzed — review the text, then Estimate.');
  }

  /// Starts/stops voice dictation straight into the description field.
  Future<void> _toggleDictation() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_speech.isAvailable) {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!ok) {
        if (mounted) {
          _snack('Voice input is not available on this device. '
              'Check the microphone permission.');
        }
        return;
      }
    }
    // Keep whatever is already typed; dictation appends after it.
    final existing = _descriptionController.text.trim();
    _dictationBase = existing.isEmpty ? '' : '$existing ';
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _descriptionController.text = _dictationBase + result.recognizedWords;
        _descriptionController.selection = TextSelection.collapsed(
          offset: _descriptionController.text.length,
        );
      },
      listenOptions: stt.SpeechListenOptions(partialResults: true),
    );
  }

  Future<void> _downloadModel() async {
    setState(() => _downloading = true);
    final ok = await MealEstimatorService.downloadModel();
    if (!mounted) return;
    setState(() => _downloading = false);
    if (ok) {
      await _refreshNanoStatus();
    } else {
      _snack('Could not download the AI model. Try again later.');
    }
  }

  Future<void> _estimate() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      _snack('Describe what you ate first.');
      return;
    }
    FocusScope.of(context).unfocus();

    final path = await resolveAiPath(context, _nanoStatus, feature: 'meal estimates');
    if (!mounted) return;
    if (path == AiPath.manual) {
      _snack('Enter the values manually below.');
      return;
    }

    setState(() => _estimating = true);
    MealEstimate? est;
    String? quotaMessage;
    try {
      if (path == AiPath.cloud) {
        final raw = await CloudAiService.estimateMeal(description);
        est = raw == null ? null : MealEstimatorService.parseEstimate(raw);
      } else {
        est = await MealEstimatorService.estimate(description);
      }
    } on CloudAiQuotaExceededException catch (e) {
      quotaMessage = e.message;
    } catch (_) {
      est = null;
    }
    if (!mounted) return;
    setState(() => _estimating = false);

    if (quotaMessage != null) {
      _snack(quotaMessage);
    } else if (est == null) {
      _snack(path == AiPath.cloud
          ? 'Cloud AI could not estimate this meal. Enter values manually '
              'or try rephrasing.'
          : 'Could not estimate this meal. Adjust the description or '
              'enter values manually.');
    } else {
      _kcalController.text = est.calories.toString();
      _proteinController.text = est.protein?.toString() ?? '';
      _carbsController.text = est.carbs?.toString() ?? '';
      _fatController.text = est.fat?.toString() ?? '';
      setState(() => _estimated = true);
    }
  }

  Future<void> _save() async {
    final description = _descriptionController.text.trim();
    final kcal = double.tryParse(_kcalController.text.trim());
    if (description.isEmpty) {
      _snack('Describe what you ate first.');
      return;
    }
    if (kcal == null || kcal < 0) {
      _snack('Enter calories (use Estimate or type them in).');
      return;
    }

    final protein = double.tryParse(_proteinController.text.trim());
    final carbs = double.tryParse(_carbsController.text.trim());
    final fat = double.tryParse(_fatController.text.trim());

    setState(() => _saving = true);

    // Always store locally so it shows up in the Journal.
    await context.read<FastingProvider>().addMeal(MealRecord(
          time: _time,
          name: description,
          calories: kcal,
          protein: protein,
          carbs: carbs,
          fat: fat,
          mealType: _mealType.name,
        ));

    // Best-effort mirror to Health Connect (so the AI coach can read it).
    final granted = await HealthSyncService.ensureNutritionPermission();
    var syncedToHealth = false;
    if (granted) {
      syncedToHealth = await HealthSyncService.logMeal(
        name: description,
        mealType: _mealType,
        time: _time,
        calories: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);

    _snack(syncedToHealth
        ? 'Meal saved (${kcal.round()} kcal) and synced to Health.'
        : 'Meal saved (${kcal.round()} kcal). Not synced to Health.');

    // Eating during an active fast usually means the fast is over — ask.
    final fp = context.read<FastingProvider>();
    if (fp.isFasting) {
      final endFast = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('End your fast?'),
          content: Text(
            'You are ${fp.formatDuration(fp.elapsed)} into a fast. '
            'Should this meal end it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep fasting'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End fast'),
            ),
          ],
        ),
      );
      if (endFast == true) await fp.stopFast();
      if (!mounted) return;
    }

    _descriptionController.clear();
    _kcalController.clear();
    _proteinController.clear();
    _carbsController.clear();
    _fatController.clear();
    setState(() {
      _estimated = false;
      _time = DateTime.now();
    });
  }

  /// Picks date + time, so meals can be logged in retrospect.
  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      helpText: 'When did you eat this?',
    );
    if (date == null || !mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (picked == null || !mounted) return;
    final t =
        DateTime(date.year, date.month, date.day, picked.hour, picked.minute);
    if (t.isAfter(now)) {
      _snack('Meal time cannot be in the future.');
      return;
    }
    setState(() => _time = t);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );

  InputDecoration _decoration(String label,
      {String? hint, EdgeInsetsGeometry? contentPadding}) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      contentPadding: contentPadding,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      isDense: true,
    );
  }

  Widget _sectionCard(BuildContext context,
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Log Meal',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // ── What & when ────────────────────────────────────────────────
            _sectionCard(
              context,
              title: 'Meal',
              icon: Icons.restaurant_rounded,
              children: [
                // Roomy description field with a floating mic that
                // dictates straight into it.
                Stack(
                  children: [
                    TextField(
                      controller: _descriptionController,
                      maxLines: 6,
                      minLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _decoration(
                        'What did you eat?',
                        hint: 'e.g. 2 eggs, a slice of bread with brown '
                            'cheese, coffee with milk',
                        contentPadding:
                            const EdgeInsets.fromLTRB(14, 14, 56, 14),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Photo scan — on-device when available, cloud
                          // fallback otherwise (see _scanPhoto). Shown on
                          // every device now that both paths are covered.
                          Material(
                            elevation: 2,
                            shape: const CircleBorder(),
                            color: scheme.secondaryContainer,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _analyzingPhoto ? null : _scanPhoto,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: _analyzingPhoto
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: scheme.onSecondaryContainer,
                                        ),
                                      )
                                    : Icon(
                                        Icons.photo_camera_rounded,
                                        size: 22,
                                        color: scheme.onSecondaryContainer,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            elevation: 2,
                            shape: const CircleBorder(),
                            color: _listening ? scheme.error : scheme.primary,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _toggleDictation,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Icon(
                                  _listening
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
                                  size: 22,
                                  color: _listening
                                      ? scheme.onError
                                      : scheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_listening)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded,
                            size: 14, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Listening… tap the button to stop',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                // All four meal types on a single line.
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<MealType>(
                    segments: [
                      for (final entry in _mealTypes.entries)
                        ButtonSegment(
                          value: entry.key,
                          label: Text(
                            entry.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    selected: {_mealType},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 12.5),
                      ),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 6),
                      ),
                    ),
                    onSelectionChanged: (s) =>
                        setState(() => _mealType = s.first),
                  ),
                ),
                const SizedBox(height: 10),
                ActionChip(
                  avatar: Icon(Icons.schedule_rounded,
                      size: 18, color: scheme.primary),
                  label: Text(
                    'Eaten ${DateFormat('d MMM · HH:mm').format(_time)}',
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  onPressed: _pickWhen,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Nutrition ──────────────────────────────────────────────────
            _sectionCard(
              context,
              title: 'Nutrition',
              icon: Icons.local_fire_department_rounded,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SizeTransition(sizeFactor: anim, child: child),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_nanoStatus),
                    child: _aiSection(scheme),
                  ),
                ),
                const SizedBox(height: 14),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 250),
                  opacity: _estimated ? 1 : 0,
                  child: _estimated
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 14, color: scheme.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'AI estimate — adjust if it looks off',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _numberField(_kcalController, 'Calories (kcal)'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _numberField(_proteinController, 'Protein (g)'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _numberField(_carbsController, 'Carbs (g)')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(_fatController, 'Fat (g)')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Save ───────────────────────────────────────────────────────
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _saving ? 'Saving…' : 'Save',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.onPrimary),
              ),
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiSection(ColorScheme scheme) {
    switch (_nanoStatus) {
      case NanoStatus.available:
        return FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _estimating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label:
              Text(_estimating ? 'Estimating…' : 'Estimate with AI'),
          onPressed: _estimating ? null : _estimate,
        );
      case NanoStatus.downloadable:
        return FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: _downloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded),
          label: Text(_downloading
              ? 'Downloading AI model…'
              : 'Download AI model (one-time)'),
          onPressed: _downloading ? null : _downloadModel,
        );
      case NanoStatus.downloading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Text('AI model is downloading…'),
          ),
        );
      case NanoStatus.unavailable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'On-device AI is not available on this phone.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Check again',
                  onPressed: _refreshNanoStatus,
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _estimating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_outlined),
              label: Text(_estimating ? 'Estimating…' : 'Estimate with AI'),
              onPressed: _estimating ? null : _estimate,
            ),
          ],
        );
    }
  }

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: _decoration(label),
      );
}
