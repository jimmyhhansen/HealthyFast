import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/cloud_ai_service.dart';
import '../services/meal_estimator_service.dart';
import '../services/training_ai_service.dart';
import '../services/training_programs.dart' show Program;
import '../widgets/cloud_ai_consent_sheet.dart';
import 'program_editor_screen.dart';

/// Describe a workout in free text (or speak it) and let on-device AI
/// (Gemini Nano — same model as meal estimation) draft a custom program
/// using our own exercise library. The draft always opens in the normal
/// program editor for review before it's saved.
class ProgramAiScreen extends StatefulWidget {
  const ProgramAiScreen({super.key});

  @override
  State<ProgramAiScreen> createState() => _ProgramAiScreenState();
}

class _ProgramAiScreenState extends State<ProgramAiScreen> {
  final _descriptionController = TextEditingController();
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String _dictationBase = '';

  NanoStatus _nanoStatus = NanoStatus.unavailable;
  bool _downloading = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _refreshNanoStatus();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _refreshNanoStatus() async {
    final status = await MealEstimatorService.checkStatus();
    if (mounted) setState(() => _nanoStatus = status);
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

  Future<void> _generate() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      _snack('Describe what you want to train first.');
      return;
    }
    FocusScope.of(context).unfocus();

    final path = await resolveAiPath(context, _nanoStatus,
        feature: 'building a program');
    if (!mounted) return;
    if (path == AiPath.manual) {
      _snack('You can still build a program manually with "New custom '
          'program".');
      return;
    }

    setState(() => _generating = true);
    Program? program;
    String? quotaMessage;
    try {
      if (path == AiPath.cloud) {
        final raw = await TrainingAiService.generateProgramCloudRaw(description);
        program = raw == null ? null : TrainingAiService.parseGenerated(raw, description);
      } else {
        program = await TrainingAiService.generateProgram(description);
      }
    } on CloudAiQuotaExceededException catch (e) {
      quotaMessage = e.message;
    }
    if (!mounted) return;
    setState(() => _generating = false);

    if (quotaMessage != null) {
      _snack(quotaMessage);
      return;
    }
    if (program == null) {
      _snack('Could not generate a program from that. Try describing it '
          'differently, or add more detail.');
      return;
    }

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProgramEditorScreen(existing: program, isAiDraft: true),
      ),
    );
    if (saved == true && mounted) Navigator.pop(context, true);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create program with AI')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _nanoStatus == NanoStatus.available
                        ? 'Runs on-device by default — nothing you type or '
                            'say leaves your phone, unless you\'ve turned on '
                            'cloud AI in Settings.'
                        : 'Uses cloud AI if you accept — your device doesn\'t '
                            'support the on-device model. You\'ll be asked '
                            'before anything is sent.',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'What do you want to train?',
                hintText: 'E.g. "3 days a week, focus on upper body and '
                    'core, I only have dumbbells and a pull-up bar, '
                    'roughly 45 minutes per session." The more detail you '
                    'give, the better the program.',
                hintMaxLines: 6,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _listening ? 'Stop' : 'Dictate',
                  icon: Icon(
                    _listening ? Icons.stop_circle_rounded : Icons.mic_rounded,
                    color: _listening ? scheme.error : scheme.primary,
                  ),
                  onPressed: _toggleDictation,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: mention your experience level, equipment you have '
              'access to, days per week, and any muscle groups or '
              'exercises to focus on or avoid.',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            _buildAction(context, scheme),
            const SizedBox(height: 12),
            Text(
              'You\'ll review every exercise, set and rep before it\'s saved '
              '— nothing is added to your programs automatically.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context, ColorScheme scheme) {
    switch (_nanoStatus) {
      case NanoStatus.available:
        return FilledButton.icon(
          onPressed: _generating ? null : _generate,
          icon: _generating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded),
          label: Text(_generating ? 'Designing your program…' : 'Generate program'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        );
      case NanoStatus.downloadable:
        return Column(
          children: [
            Text(
              'On-device AI needs a one-time download to run on this '
              'phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_downloading ? 'Downloading…' : 'Download AI model'),
              onPressed: _downloading ? null : _downloadModel,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
        );
      case NanoStatus.downloading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case NanoStatus.unavailable:
        return FilledButton.icon(
          onPressed: _generating ? null : _generate,
          icon: _generating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome_rounded),
          label: Text(_generating ? 'Designing your program…' : 'Generate program'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        );
    }
  }
}
