import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:watch_connectivity/watch_connectivity.dart';
import 'package:wearable_rotary/wearable_rotary.dart';
import '../providers/fasting_provider.dart';
import '../providers/profile_provider.dart';
import '../services/meal_sync_queue.dart';
import '../services/notification_service.dart';
import '../services/ongoing_activity_service.dart';
import '../widgets/wear_scroll_view.dart';
import 'watch_workout_flow.dart';

/// Compact UI for Wear OS: progress ring, elapsed time, current zone,
/// start/stop control, and the zone's science tip. Syncs with the phone.
class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key});

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> {
  static const _nav = MethodChannel('healthyfast/nav');

  final _rootPageCtrl = PageController();
  StreamSubscription<RotaryEvent>? _rootRotarySub;
  int _rootPage = 0;
  DateTime? _rootLastTurn;

  @override
  void initState() {
    super.initState();
    // Crown/bezel pages between Fast / Workout / Meal — same debounced
    // sensitivity as the workout set pages. Ignored while another route
    // (voice, workout flow, pickers) is on top.
    _rootRotarySub = rotaryEvents.listen((event) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final now = DateTime.now();
      if (_rootLastTurn != null &&
          now.difference(_rootLastTurn!) <
              const Duration(milliseconds: 450)) {
        return;
      }
      final forward = event.direction == RotaryDirection.clockwise;
      final target = (_rootPage + (forward ? 1 : -1)).clamp(0, 2);
      if (target != _rootPage) {
        _rootLastTurn = now;
        HapticFeedback.selectionClick();
        _rootPageCtrl.animateToPage(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
    // The Ongoing Activity (watch face / Recents / Tile indicator) is an
    // ongoing notification, which needs POST_NOTIFICATIONS on Wear OS 4+.
    // Ask on first launch, then (re)post the indicator if a fast is already
    // running so it is never missing while fasting.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.requestNotificationsPermission();
      if (!mounted) return;
      final fp = context.read<FastingProvider>();
      final start = fp.startTime;
      if (fp.isFasting && start != null) {
        await OngoingActivityService.start(
          startMs: start.millisecondsSinceEpoch,
          goalHours: fp.protocol.hours,
        );
      }
    });

    // Tiles launch us with an "open" extra: meal voice or workout logging.
    _nav.setMethodCallHandler((call) async {
      if (call.method != 'open' || !mounted) return;
      if (call.arguments == 'log_meal_voice') {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const _MealVoiceScreen()),
        );
      } else if (call.arguments == 'log_workout') {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WatchWorkoutFlow()),
        );
      }
    });
  }

  @override
  void dispose() {
    _rootRotarySub?.cancel();
    _rootPageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    // Three vertical pages: 1 fasting, 2 log workout, 3 log meal.
    return Scaffold(
      backgroundColor: Colors.black,
      body: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          setState(() {});
          return false;
        },
        child: Stack(
          children: [
            PageView(
              controller: _rootPageCtrl,
              scrollDirection: Axis.vertical,
              onPageChanged: (p) {
                if (p != _rootPage) HapticFeedback.selectionClick();
                setState(() => _rootPage = p);
              },
              children: [
                fp.isFasting ? _FastingView(fp: fp) : _IdleView(fp: fp),
                const _WorkoutPage(),
                const _MealPage(),
              ],
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CurvedScrollIndicatorPainter.of(_rootPageCtrl),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Root page 2: entry to on-watch workout logging.
class _WorkoutPage extends StatelessWidget {
  const _WorkoutPage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Workout',
            style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _BigPlus(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WatchWorkoutFlow()),
            ),
          ),
          const SizedBox(height: 8),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white24, size: 16),
        ],
      ),
    );
  }
}

/// Root page 3: entry to voice meal logging.
class _MealPage extends StatelessWidget {
  const _MealPage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Meal',
            style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _BigPlus(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _MealVoiceScreen()),
            ),
          ),
          const SizedBox(height: 8),
          const Icon(Icons.keyboard_arrow_up_rounded,
              color: Colors.white24, size: 16),
        ],
      ),
    );
  }
}

/// The green + used on the watch's logging pages (same identity as the
/// tiles' + buttons).
class _BigPlus extends StatelessWidget {
  const _BigPlus({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF81C995),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: const SizedBox(
          width: 56,
          height: 56,
          child: Icon(Icons.add_rounded,
              size: 32, color: Color(0xFF1B2B20)),
        ),
      ),
    );
  }
}

/// Speak a meal on the watch → send the text to the phone, which estimates
/// and logs it. On-device speech capture; the phone does the AI part.
class _MealVoiceScreen extends StatefulWidget {
  const _MealVoiceScreen();

  @override
  State<_MealVoiceScreen> createState() => _MealVoiceScreenState();
}

class _MealVoiceScreenState extends State<_MealVoiceScreen> {
  static const _localePrefKey = 'voice_locale';

  final stt.SpeechToText _speech = stt.SpeechToText();
  final _wc = WatchConnectivity();
  String _text = '';
  bool _listening = false;
  bool _sent = false;

  /// Recognition language. Defaults to the watch's system locale; the user
  /// can override it (e.g. Norwegian on an English watch) and the choice
  /// is remembered.
  String? _localeId;
  List<stt.LocaleName> _locales = const [];

  /// Set when starting the mic fails, so a tap always gives visible
  /// feedback instead of silently flipping back to idle.
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  /// Short display label like "NO" or "EN" for the current locale.
  String get _localeLabel {
    final id = _localeId;
    if (id == null) return 'AUTO';
    final lang = id.split(RegExp('[-_]')).first.toUpperCase();
    return lang == 'NB' || lang == 'NN' ? 'NO' : lang;
  }

  /// The speech plugin can HANG (not fail) on some Wear devices — every
  /// call gets a timeout so the screen can never go dead again.
  Future<T> _bounded<T>(Future<T> f, T fallback,
      {int seconds = 5}) =>
      f.timeout(Duration(seconds: seconds), onTimeout: () => fallback);

  Future<void> _start() async {
    try {
      setState(() => _error = null);

      if (!_speech.isAvailable) {
        final ok = await _bounded(
          _speech.initialize(
            onStatus: (s) {
              if ((s == 'done' || s == 'notListening') && mounted) {
                setState(() => _listening = false);
              }
            },
            onError: (e) {
              if (mounted) {
                setState(() {
                  _listening = false;
                  _error = 'Mic error (${e.errorMsg})';
                });
              }
            },
          ),
          false,
          seconds: 10,
        );
        if (!ok) {
          if (mounted) {
            setState(() {
              _listening = false;
              _error = 'Speech recognition unavailable';
            });
          }
          return;
        }
      }

      // Stored language preference only — NO plugin locale calls here:
      // locales()/systemLocale() are exactly the calls that hang on some
      // watches. null means the recognizer's own default.
      if (_localeId == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          _localeId = prefs.getString(_localePrefKey);
        } catch (_) {}
      }

      // Clear any stuck session before starting a new one.
      try {
        await _bounded(_speech.cancel(), null, seconds: 2);
      } catch (_) {}

      if (!mounted) return;
      setState(() => _listening = true);
      try {
        await _bounded(
          _speech.listen(
            onResult: (r) => setState(() => _text = r.recognizedWords),
            listenOptions: stt.SpeechListenOptions(
              partialResults: true,
              localeId: _localeId,
            ),
          ),
          null,
        );
      } catch (_) {
        // Retry once without a locale (system default) — a rejected
        // localeId is the most common instant-failure cause.
        _localeId = null;
        await _bounded(
          _speech.listen(
            onResult: (r) => setState(() => _text = r.recognizedWords),
            listenOptions: stt.SpeechListenOptions(partialResults: true),
          ),
          null,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _listening = false;
          _error = 'Could not start the mic';
        });
      }
    }
  }

  Future<void> _pickLocale() async {
    try {
      await _bounded(_speech.stop(), null, seconds: 2);
    } catch (_) {}

    // Fetch the list on demand (it hangs on some watches — hence bounded
    // and OFF the startup path).
    if (_locales.isEmpty) {
      try {
        _locales = await _bounded(
            _speech.locales(), const <stt.LocaleName>[],
            seconds: 4);
      } catch (_) {
        _locales = const [];
      }
      if (_locales.isEmpty) {
        if (mounted) {
          setState(() =>
              _error = 'No language list from the watch — using default');
        }
        return;
      }
    }

    if (!mounted) return;
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _LocalePickerScreen(
          locales: _locales,
          currentId: _localeId,
        ),
      ),
    );
    if (selected == null) return;
    _localeId = selected;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localePrefKey, selected);
    if (!mounted) return;
    setState(() => _text = '');
    await _start();
  }

  /// Starts a fresh dictation: clears the previous text first, so Retry
  /// visibly resets instead of appearing dead.
  Future<void> _retry() async {
    setState(() {
      _text = '';
      _error = null;
    });
    await _start();
  }

  /// True when the phone confirmed delivery immediately; false = queued.
  bool _deliveredNow = false;

  Future<void> _send() async {
    final text = _text.trim();
    if (text.isEmpty) return;
    try {
      await _bounded(_speech.stop(), null, seconds: 2);
    } catch (_) {}

    // Queue FIRST (survives everything), then try the fast path. The
    // queued copy rides the persisted application context until the
    // phone acknowledges the id — see MealSyncQueue/WatchSyncService.
    final item = await MealSyncQueue.enqueue(text);
    var delivered = false;
    try {
      if (await _bounded(_wc.isReachable, false, seconds: 3)) {
        await _wc.sendMessage(
            {'type': 'logMeal', 'id': item['id'], 'text': text});
        delivered = true;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _sent = true;
      _deliveredNow = delivered;
    });
    await Future.delayed(const Duration(milliseconds: 2500));
    if (mounted) {
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        // If still on this screen, reset state so it's ready for next time.
        setState(() {
          _sent = false;
          _text = '';
          _error = null;
        });
        // Optional: Pop back to the main meal page instead of staying here.
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        center: true,
        children: [
          if (_sent) ...[
            Icon(
              _deliveredNow ? Icons.check_circle : Icons.schedule_send_rounded,
              color: _deliveredNow ? Colors.green : Colors.amber,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              _deliveredNow
                  ? 'Sent to phone —\nlogging your meal'
                  : 'Saved — syncs when\nyour phone is nearby',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ] else ...[
            // The whole mic area is tappable: "Tap to talk" must actually
            // respond to a tap, not just the small retry button below.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _listening ? null : _start,
              child: Icon(
                _listening ? Icons.mic : Icons.mic_none,
                color: _listening ? Colors.redAccent : Colors.white70,
                size: 26,
              ),
            ),
            const SizedBox(height: 2),
            // Recognition language — tap to change (remembered). The list
            // is fetched on demand with a timeout.
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(40, 24),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: _pickLocale,
              child: Text(
                _localeLabel,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 2),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _listening ? null : _start,
              child: Text(
                _text.isEmpty
                    ? (_listening
                        ? 'Listening…\nSay what you ate'
                        : 'Tap to talk')
                    : _text,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.orangeAccent, fontSize: 11),
                ),
              ),
            const SizedBox(height: 12),
            // Hard width cap + scale-down: the button row can never reach
            // outside the round bezel, at any system font size.
            SizedBox(
              width: MediaQuery.sizeOf(context).shortestSide * 0.55,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Retry as a compact icon button to save width.
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.grey.shade800,
                        shape: const CircleBorder(),
                        minimumSize: const Size(40, 40),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: _listening ? null : _retry,
                      child: const Icon(Icons.refresh_rounded,
                          size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade800,
                        shape: const StadiumBorder(),
                        minimumSize: const Size(88, 40),
                      ),
                      onPressed: _text.trim().isEmpty ? null : _send,
                      child: const Text('Log', style: TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Logs the phone's "next workout" from the wrist: check off sets and
/// adjust kg, then Finish sends everything to the phone through the
/// reliable sync queue (same id+ack mechanism as meals).
class _WatchWorkoutScreen extends StatefulWidget {
  const _WatchWorkoutScreen();

  @override
  State<_WatchWorkoutScreen> createState() => _WatchWorkoutScreenState();
}

class _WatchExercise {
  _WatchExercise(this.name, this.sets, this.reps, this.kg)
      : done = List.filled(sets, false);
  final String name;
  final int sets;
  final int reps;
  double kg;
  final List<bool> done;
}

class _WatchWorkoutScreenState extends State<_WatchWorkoutScreen> {
  final _wc = WatchConnectivity();
  final _pageCtrl = PageController();
  StreamSubscription<RotaryEvent>? _rotarySub;
  late final DateTime _startedAt = DateTime.now();
  String _programName = '';
  String _dayTitle = 'Workout';
  int _dayIdx = -1;
  List<_WatchExercise> _exercises = const [];
  bool _loaded = false;
  bool _sent = false;
  bool _deliveredNow = false;
  int _page = 0;
  DateTime? _lastPageTurn;

  @override
  void initState() {
    super.initState();
    _load();
    // Crown/bezel scrolls between exercise pages, with a haptic tick.
    // Debounced: the crown fires many small events per turn, which made
    // paging far too sensitive — one page change per 450 ms max.
    _rotarySub = rotaryEvents.listen((event) {
      final now = DateTime.now();
      if (_lastPageTurn != null &&
          now.difference(_lastPageTurn!) <
              const Duration(milliseconds: 450)) {
        return;
      }
      final forward = event.direction == RotaryDirection.clockwise;
      final target = (_page + (forward ? 1 : -1))
          .clamp(0, _exercises.length); // last page = finish
      if (target != _page) {
        _lastPageTurn = now;
        HapticFeedback.selectionClick();
        _pageCtrl.animateToPage(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _rotarySub?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('next_workout_json');
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map;
        _programName = m['pName'] as String? ?? '';
        _dayTitle = m['title'] as String? ?? 'Workout';
        _dayIdx = ((m['dayIdx'] as num?) ?? -1).toInt();
        _exercises = [
          for (final e in (m['exercises'] as List? ?? const []))
            if (e is Map)
              _WatchExercise(
                e['n'] as String? ?? 'Exercise',
                ((e['sets'] as num?) ?? 3).toInt(),
                ((e['reps'] as num?) ?? 5).toInt(),
                ((e['kg'] as num?) ?? 20).toDouble(),
              ),
        ];
        // Locally remembered weights for THIS program day (per exercise):
        // fresher than the sync when the phone hasn't processed the last
        // session yet. Cleared implicitly when the day index moves on.
        final memRaw = prefs.getString('watch_last_kg');
        if (memRaw != null && memRaw.isNotEmpty) {
          final mem = jsonDecode(memRaw) as Map;
          if ((mem['dayIdx'] as num?)?.toInt() == _dayIdx) {
            final kgs = (mem['kg'] as Map?) ?? const {};
            for (final e in _exercises) {
              final v = kgs[e.name];
              if (v is num) e.kg = v.toDouble();
            }
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _rememberWeights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'watch_last_kg',
          jsonEncode({
            'dayIdx': _dayIdx,
            'kg': {for (final e in _exercises) e.name: e.kg},
          }));
    } catch (_) {}
  }

  Future<void> _finish() async {
    // Remember per-exercise weights for next time on the watch.
    await _rememberWeights();

    if (!mounted) return;

    final fullTitle = _programName.isNotEmpty
        ? '$_programName, $_dayTitle' 
        : _dayTitle;

    final exercisesJson = jsonEncode([
      for (final e in _exercises)
        if (e.done.any((d) => d))
          {
            'n': e.name,
            'sets': [
              for (final d in e.done)
                if (d) {'kg': e.kg, 'reps': e.reps},
            ],
          },
    ]);

    // Queue first (reliable), then try the fast path.
    final payload = await MealSyncQueue.enqueueRaw({
      'type': 'workout',
      'title': fullTitle,
      'dayTitle': _dayTitle, // Send raw day title for progression matching
      'startMs': _startedAt.millisecondsSinceEpoch,
      'endMs': DateTime.now().millisecondsSinceEpoch,
      'exercises': exercisesJson,
    });

    var delivered = false;
    try {
      if (await _wc.isReachable
          .timeout(const Duration(seconds: 3), onTimeout: () => false)) {
        await _wc.sendMessage(payload);
        delivered = true;
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _sent = true;
      _deliveredNow = delivered;
    });
    await Future.delayed(const Duration(milliseconds: 1600));
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_exercises.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: WearScrollView(
          center: true,
          children: const [
            Text(
              'No program workout available.\nPick a program in the '
              'phone app first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_sent) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: WearScrollView(
          center: true,
          children: [
            Icon(
              _deliveredNow
                  ? Icons.check_circle
                  : Icons.schedule_send_rounded,
              color: _deliveredNow ? Colors.green : Colors.amber,
              size: 40,
            ),
            const SizedBox(height: 10),
            Text(
              _deliveredNow
                  ? 'Sent to phone —\nworkout logged'
                  : 'Saved — syncs when\nyour phone is nearby',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final pp = context.watch<ProfileProvider>();
    final isImperial = pp.unitSystem == UnitSystem.imperial;

    // One exercise per page (crown/bezel or swipe scrolls between them,
    // with a haptic tick); the last page is the Finish page.
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView(
        controller: _pageCtrl,
        scrollDirection: Axis.vertical,
        onPageChanged: (p) {
          if (p != _page) HapticFeedback.selectionClick();
          setState(() => _page = p);
        },
        children: [
          for (var i = 0; i < _exercises.length; i++)
            _exercisePage(_exercises[i], i, isImperial),
          _finishPage(),
        ],
      ),
    );
  }

  Widget _exercisePage(_WatchExercise e, int index, bool isImperial) {
    final side = MediaQuery.sizeOf(context).shortestSide;

    final displayKg = isImperial ? e.kg / 0.45359237 : e.kg;
    final weightLabel = '${displayKg == displayKg.roundToDouble() ? displayKg.round() : displayKg.toStringAsFixed(1)} ${isImperial ? 'lbs' : 'kg'}';

    // The whole page scales down as one unit, so everything ALWAYS fits
    // a single screen — no inner scrolling to fight the page scroll.
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: side * 0.10, vertical: side * 0.08),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: side * 0.80),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
          // Long names get "…" instead of being cut or shrunk unreadably.
          Text(
            e.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          // kg stepper — minus pinned far left, plus far right, value
          // centered between them. Fixed width keeps it symmetric.
          SizedBox(
            width: side * 0.80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  iconSize: 30,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                  icon: const Icon(Icons.remove_circle_outline,
                      color: Colors.white70),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (isImperial) {
                      var lbs = e.kg / 0.45359237;
                      lbs = (lbs - 5).clamp(0, 2000);
                      setState(() => e.kg = lbs * 0.45359237);
                    } else {
                      setState(() => e.kg = (e.kg - 2.5).clamp(0, 999));
                    }
                  },
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$weightLabel × ${e.reps}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  iconSize: 30,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                  icon: const Icon(Icons.add_circle_outline,
                      color: Colors.white70),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    if (isImperial) {
                      var lbs = e.kg / 0.45359237;
                      lbs += 5;
                      setState(() => e.kg = lbs * 0.45359237);
                    } else {
                      setState(() => e.kg += 2.5);
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < e.done.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => e.done[i] = !e.done[i]);
                  },
                  child: Container(
                    width: 38,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: e.done[i]
                          ? Colors.green.shade800
                          : Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      e.done[i] ? '✓' : '${i + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white24, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _finishPage() {
    final anyDone = _exercises.any((e) => e.done.any((d) => d));
    final side = MediaQuery.sizeOf(context).shortestSide;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side * 0.14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _dayTitle,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_exercises.where((e) => e.done.every((d) => d)).length} of '
            '${_exercises.length} exercises complete',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade800,
              minimumSize: const Size(130, 44),
              shape: const StadiumBorder(),
            ),
            onPressed: anyDone ? _finish : null,
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Finish', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen list of speech recognition languages, watch-sized.
class _LocalePickerScreen extends StatelessWidget {
  final List<stt.LocaleName> locales;
  final String? currentId;
  const _LocalePickerScreen({required this.locales, this.currentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Voice language',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
          for (final l in locales)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: l.localeId == currentId
                      ? Colors.green.shade800
                      : Colors.grey.shade900,
                  minimumSize: const Size.fromHeight(42),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.pop(context, l.localeId),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    l.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Idle: ring outline, selected protocol, start button (opens picker).
class _IdleView extends StatelessWidget {
  final FastingProvider fp;
  const _IdleView({required this.fp});

  @override
  Widget build(BuildContext context) {
    final ring = MediaQuery.of(context).size.shortestSide * 0.72;
    // Non-scrolling page (lives inside the root PageView); FittedBox
    // keeps everything on one screen at large font sizes.
    return Center(
        child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: ring,
              height: ring,
              child: const CircularProgressIndicator(
                value: 0,
                strokeWidth: 6,
                backgroundColor: Colors.white12,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    fp.protocol.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Ready to fast',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade800,
            minimumSize: const Size(120, 40),
            shape: const StadiumBorder(),
          ),
          onPressed: () => _pickProtocolAndStart(context, fp),
          child: const Text('Start', style: TextStyle(fontSize: 14)),
        ),
      ],
      ),
    ));
  }

  Future<void> _pickProtocolAndStart(
      BuildContext context, FastingProvider fp) async {
    final selected = await Navigator.push<FastingProtocol>(
      context,
      MaterialPageRoute(
          builder: (_) => _ProtocolPickerScreen(customHours: fp.customHours)),
    );
    if (selected == null) return;
    if (selected.isCustom) {
      fp.setCustomProtocol(selected.hours);
    } else {
      fp.setProtocol(selected);
    }
    await fp.startFast();
  }
}

/// Full-screen protocol list, sized for a small round display.
class _ProtocolPickerScreen extends StatelessWidget {
  final int customHours;
  const _ProtocolPickerScreen({required this.customHours});

  @override
  Widget build(BuildContext context) {
    final custom = FastingProtocol.custom(customHours);
    final options = [...FastingProtocol.presets, custom];

    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 28),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Fast type',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
          for (final p in options)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.grey.shade900,
                    minimumSize: const Size.fromHeight(42),
                    shape: const StadiumBorder(),
                  ),
                  // Custom opens the day/hour editor (like the phone);
                  // presets are returned directly.
                  onPressed: p.isCustom
                      ? () => _editCustom(context, p.hours)
                      : () => Navigator.pop(context, p),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      p.isCustom ? 'Custom · ${p.label}' : p.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _editCustom(BuildContext context, int currentHours) async {
    final total = await Navigator.push<int>(
      context,
      MaterialPageRoute(
          builder: (_) => _CustomFastEditScreen(initialHours: currentHours)),
    );
    if (total == null || !context.mounted) return;
    Navigator.pop(context, FastingProtocol.custom(total));
  }
}

/// Watch equivalent of the phone's custom-fast dialog: day and hour wheels.
/// Everything is scrollable and scale-capped so it works at the largest
/// system font size on round displays.
class _CustomFastEditScreen extends StatefulWidget {
  final int initialHours;
  const _CustomFastEditScreen({required this.initialHours});

  @override
  State<_CustomFastEditScreen> createState() => _CustomFastEditScreenState();
}

class _CustomFastEditScreenState extends State<_CustomFastEditScreen> {
  late int _days = widget.initialHours ~/ 24;
  late int _hours = widget.initialHours % 24;
  late final FixedExtentScrollController _dayCtrl =
      FixedExtentScrollController(initialItem: _days);
  late final FixedExtentScrollController _hourCtrl =
      FixedExtentScrollController(initialItem: _hours);

  int get _total => _days * 24 + _hours;

  @override
  void dispose() {
    _dayCtrl.dispose();
    _hourCtrl.dispose();
    super.dispose();
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required String label,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        SizedBox(
          width: 52,
          height: 96,
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 32,
            physics: const FixedExtentScrollPhysics(),
            overAndUnderCenterOpacity: 0.3,
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildLoopingListDelegate(
              children: [
                for (var i = 0; i < count; i++)
                  Center(
                    // Scale-capped so large system fonts never overflow
                    // the fixed wheel item height.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$i',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide;
    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        center: true,
        children: [
          const Text(
            'Custom fast',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          // Width-capped row of wheels — can never reach the round bezel.
          SizedBox(
            width: side * 0.6,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _wheel(
                    controller: _dayCtrl,
                    count: 15,
                    label: 'Days',
                    onChanged: (v) => setState(() => _days = v),
                  ),
                  const SizedBox(width: 12),
                  _wheel(
                    controller: _hourCtrl,
                    count: 24,
                    label: 'Hours',
                    onChanged: (v) => setState(() => _hours = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _total > 0 ? 'Total: $_total hours' : 'Set a duration',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green.shade800,
              minimumSize: const Size(110, 40),
              shape: const StadiumBorder(),
            ),
            onPressed:
                _total > 0 ? () => Navigator.pop(context, _total) : null,
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Set', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Adjust menu for an ongoing fast, mirroring the phone app's edit options:
/// change the start time or change the goal.
class _AdjustScreen extends StatelessWidget {
  const _AdjustScreen();

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();

    Widget item(String label, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.grey.shade900,
              minimumSize: const Size.fromHeight(42),
              shape: const StadiumBorder(),
            ),
            onPressed: onTap,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        center: true,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Adjust fast',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
          item('Start time', () async {
            final start = fp.startTime;
            if (start == null) return;
            final newStart = await Navigator.push<DateTime>(
              context,
              MaterialPageRoute(
                  builder: (_) => _EditStartScreen(initial: start)),
            );
            if (newStart != null) await fp.editStartTime(newStart);
          }),
          item('Goal · ${fp.protocol.label}', () async {
            final selected = await Navigator.push<FastingProtocol>(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      _ProtocolPickerScreen(customHours: fp.customHours)),
            );
            if (selected != null) await fp.updateGoalDuringFast(selected);
          }),
        ],
      ),
    );
  }
}

/// Start-time editor: pick the day (chevrons, today and back) and the time
/// of day with hour/minute wheels — the watch equivalent of the phone app's
/// date + time pickers. Never allows a start in the future.
class _EditStartScreen extends StatefulWidget {
  final DateTime initial;
  const _EditStartScreen({required this.initial});

  @override
  State<_EditStartScreen> createState() => _EditStartScreenState();
}

class _EditStartScreenState extends State<_EditStartScreen> {
  static const _maxDaysBack = 7;

  late int _daysAgo;
  late int _hour;
  late int _minute;
  late final FixedExtentScrollController _hourCtrl;
  late final FixedExtentScrollController _minCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(
        widget.initial.year, widget.initial.month, widget.initial.day);
    _daysAgo = today.difference(day).inDays.clamp(0, _maxDaysBack);
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour);
    _minCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  String get _dayLabel {
    if (_daysAgo == 0) return 'Today';
    if (_daysAgo == 1) return 'Yesterday';
    return '$_daysAgo days ago';
  }

  DateTime _compose() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: _daysAgo));
    var start = DateTime(day.year, day.month, day.day, _hour, _minute);
    if (start.isAfter(now)) start = now;
    return start;
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int count,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 52,
      height: 96,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 32,
        physics: const FixedExtentScrollPhysics(),
        overAndUnderCenterOpacity: 0.3,
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildLoopingListDelegate(
          children: [
            for (var i = 0; i < count; i++)
              Center(
                child: Text(
                  i.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: WearScrollView(
        center: true,
        children: [
          const Text(
            'Start time',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          // Day: chevrons around the label, clamped to [today - 7d, today].
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _daysAgo >= _maxDaysBack
                    ? null
                    : () => setState(() => _daysAgo++),
                icon: Icon(Icons.chevron_left,
                    size: 22,
                    color: _daysAgo >= _maxDaysBack
                        ? Colors.white24
                        : Colors.white),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  _dayLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed:
                    _daysAgo <= 0 ? null : () => setState(() => _daysAgo--),
                icon: Icon(Icons.chevron_right,
                    size: 22,
                    color: _daysAgo <= 0 ? Colors.white24 : Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Time of day: hour and minute wheels.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _wheel(
                controller: _hourCtrl,
                count: 24,
                onChanged: (v) => setState(() => _hour = v),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  ':',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold),
                ),
              ),
              _wheel(
                controller: _minCtrl,
                count: 60,
                onChanged: (v) => setState(() => _minute = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 40),
              shape: const StadiumBorder(),
            ),
            onPressed: () => Navigator.pop(context, _compose()),
            child: const Text('Save', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

/// Fasting: ring + elapsed + stop, with the zone tip scrollable below.
class _FastingView extends StatelessWidget {
  final FastingProvider fp;
  const _FastingView({required this.fp});

  @override
  Widget build(BuildContext context) {
    final zone = fp.currentZone;
    final ringSize = MediaQuery.of(context).size.shortestSide;

    // Single-screen page inside the root PageView. The zone-tip section
    // is gone — scroll down goes to Workout/Meal pages instead.
    return Center(
      child: SizedBox(
        height: ringSize,
        width: ringSize,
        child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Center(
                  child: SizedBox(
                    // Inset enough that the curved scroll indicator (which
                    // hugs the bezel at the right edge) sits outside the ring
                    // instead of overlapping it.
                    width: ringSize - 24,
                    height: ringSize - 24,
                    child: CircularProgressIndicator(
                      value: fp.progress,
                      strokeWidth: 6,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation<Color>(zone.color),
                    ),
                  ),
                ),
              ),
              Padding(
                // Keep the centered text/controls inside the ring, clear of
                // the curved edges even when the column grows at large fonts.
                padding: EdgeInsets.symmetric(
                    horizontal: ringSize * 0.15, vertical: ringSize * 0.15),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Width-capped and slightly smaller: the longest zone
                    // names (Deep Renewal) grazed the ring on hi-res
                    // watches at the top of the circle.
                    SizedBox(
                      width: ringSize * 0.58,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${zone.emoji} ${zone.name}',
                          style: TextStyle(
                            color: zone.color,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        fp.formatDuration(fp.elapsed),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Goal: ${fp.protocol.label}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Hard width cap, scaled down as a whole (not just the
                    // label) if system font size would otherwise make the
                    // row grow — guarantees it never reaches the ring,
                    // regardless of accessibility text scaling.
                    SizedBox(
                      width: ringSize * 0.5,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton(
                              style: FilledButton.styleFrom(
                                // Watch's own green — same as the Start and
                                // Log buttons, consistent across the watch.
                                backgroundColor: Colors.green.shade800,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(80, 36),
                              ),
                              onPressed: () => _confirmStop(context, fp),
                              child: const Text('Stop',
                                  style: TextStyle(fontSize: 14)),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit,
                                  size: 16, color: Colors.white54),
                              tooltip: 'Edit start time',
                              onPressed: () => _editStart(context, fp),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                ),
              ),
            ],
          ),
        ),
    );
  }

  Future<void> _editStart(BuildContext context, FastingProvider fp) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _AdjustScreen()),
    );
  }

  Future<void> _confirmStop(BuildContext context, FastingProvider fp) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        // Inset to the square inscribed in the round display:
        // (1 - 1/sqrt(2)) / 2 of the diameter on every side. Content kept
        // inside this box can never clip against the circular bezel.
        final inset = size.shortestSide * 0.1464;
        return Dialog.fullscreen(
          backgroundColor: Colors.grey.shade900,
          child: Padding(
            padding: EdgeInsets.all(inset),
            child: Center(
              // Scrolls when large font sizes make content taller than
              // the safe box, instead of overflowing off-screen.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Stop after ${fp.formatDuration(fp.elapsed)}?',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Stop'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Keep'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (confirmed == true) await fp.stopFast();
  }
}
