import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fitness_goal.dart';
import '../providers/profile_provider.dart';
import '../theme/app_theme.dart';
import 'profile_wizard_screen.dart';
import 'root_screen.dart';

/// First-launch welcome flow.
///
/// Two pages before any form appears:
///   0. Hero — the free timer is the hook, the rest of the app is the
///      reveal. Capabilities are shown as outcomes, not a feature list.
///   1. Goal — one question that personalises everything after it.
///
/// It then hands off to [ProfileWizardScreen] in intro mode, which weaves
/// goal-matched capability cards into the questions and closes on a
/// personalised plan summary.
///
/// Also reachable from Settings → "Run the setup guide again", in which
/// case [isRerun] is true and we pop back instead of replacing the app root.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.isRerun = false});

  final bool isRerun;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  final _pages = PageController();
  int _page = 0;

  late final AnimationController _ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _pages.dispose();
    _ring.dispose();
    _enter.dispose();
    super.dispose();
  }

  void _goToGoal() {
    _pages.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _pickGoal(FitnessGoal goal) async {
    final pp = context.read<ProfileProvider>();
    await pp.setGoal(goal);
    if (!mounted) return;

    final finished = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileWizardScreen(introMode: true),
      ),
    );
    if (!mounted) return;

    if (finished == true) {
      await pp.markOnboardingComplete();
      if (!mounted) return;
      _leave();
    }
  }

  /// Skipping still counts as onboarded — nobody should be asked twice.
  Future<void> _skip() async {
    await context.read<ProfileProvider>().markOnboardingComplete();
    if (!mounted) return;
    _leave();
  }

  void _leave() {
    if (widget.isRerun) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const RootScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Soft zone-tinted wash behind everything.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: dark
                      ? [
                          const Color(0xFF0C1C1A),
                          Color.lerp(const Color(0xFF0C1C1A),
                              AppTheme.zoneColors[5], 0.16)!,
                          const Color(0xFF0C1C1A),
                        ]
                      : [
                          const Color(0xFFF4F9F8),
                          Color.lerp(const Color(0xFFF4F9F8),
                              AppTheme.zoneColors[4], 0.22)!,
                          const Color(0xFFF4F9F8),
                        ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  page: _page,
                  onSkip: widget.isRerun ? () => Navigator.pop(context) : _skip,
                  skipLabel: widget.isRerun ? 'Close' : 'Skip',
                ),
                Expanded(
                  child: PageView(
                    controller: _pages,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _page = i),
                    children: [
                      _HeroPage(
                        ring: _ring,
                        enter: _enter,
                        onNext: _goToGoal,
                      ),
                      _GoalPage(onPick: _pickGoal),
                    ],
                  ),
                ),
                _Dots(count: 2, index: _page, color: scheme.primary),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.page,
    required this.onSkip,
    required this.skipLabel,
  });

  final int page;
  final VoidCallback onSkip;
  final String skipLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Row(
        children: [
          Icon(Icons.hourglass_full_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            'HealthyFast',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
          ),
          const Spacer(),
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
            ),
            child: Text(skipLabel),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Page 0 — hero
// ─────────────────────────────────────────────────────────────────────

class _HeroPage extends StatelessWidget {
  const _HeroPage({
    required this.ring,
    required this.enter,
    required this.onNext,
  });

  final AnimationController ring;
  final AnimationController enter;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, box) {
        // On short phones the ring shrinks rather than pushing the copy off.
        final ringSize = math.min(box.maxHeight * 0.30, 210.0);

        // The copy scrolls if it has to; the CTA never moves. Note the
        // scroll area must not contain Spacer/Expanded — its height is
        // unbounded.
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight - 150),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: _Fade(
                          enter: enter,
                          delay: 0.0,
                          child: SizedBox(
                            width: ringSize,
                            height: ringSize,
                            child: AnimatedBuilder(
                              animation: ring,
                              builder: (_, __) => CustomPaint(
                                painter: _ZoneRingPainter(
                                  t: ring.value,
                                  trackColor:
                                      scheme.onSurface.withValues(alpha: 0.06),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.hourglass_full_rounded,
                                    size: ringSize * 0.24,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 34),
                      _Fade(
                        enter: enter,
                        delay: 0.12,
                        child: Text(
                          'The timer is free.\nThe rest makes it stick.',
                          textAlign: TextAlign.center,
                          style: text.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _Fade(
                        enter: enter,
                        delay: 0.2,
                        child: Text(
                          'Every fasting protocol and all seven body zones '
                          'stay free. Underneath sits everything '
                          'that turns a good week into real progress.',
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      _Fade(
                        enter: enter,
                        delay: 0.3,
                        child: const Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Chip(
                                icon: Icons.auto_awesome_rounded,
                                label: 'Snap a meal, get macros'),
                            _Chip(
                                icon: Icons.fitness_center_rounded,
                                label: 'Programmes that progress'),
                            _Chip(
                                icon: Icons.watch_rounded,
                                label: 'Live on your wrist'),
                            _Chip(
                                icon: Icons.lock_rounded,
                                label: 'On-device & private'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: _Fade(
                enter: enter,
                delay: 0.4,
                child: Column(
                  children: [
                    FilledButton(
                      onPressed: onNext,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('Show me'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Under a minute. No account needed.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Seven arcs in the zone palette, slowly rotating — the same visual
/// language as the home ring, so the welcome screen already looks like the
/// app rather than a generic splash.
class _ZoneRingPainter extends CustomPainter {
  _ZoneRingPainter({required this.t, required this.trackColor});

  final double t;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final stroke = size.width * 0.075;
    final radius = (size.width - stroke) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    const zones = AppTheme.zoneColors;
    final sweep = (math.pi * 2) / zones.length;
    final spin = t * math.pi * 2;

    for (var i = 0; i < zones.length; i++) {
      // Each arc breathes on its own phase, so the ring never looks static.
      final phase = (t * zones.length + i) % zones.length / zones.length;
      final glow = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2 + spin + i * sweep,
        sweep * 0.82,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke
          ..color = zones[i].withValues(alpha: glow),
      );
    }

    // Inner halo, tied to the fat-burning zone colour.
    canvas.drawCircle(
      center,
      radius - stroke * 1.4,
      Paint()
        ..color = zones[4].withValues(alpha: 0.07)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ZoneRingPainter old) =>
      old.t != t || old.trackColor != trackColor;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Page 1 — goal
// ─────────────────────────────────────────────────────────────────────

class _GoalPage extends StatefulWidget {
  const _GoalPage({required this.onPick});

  final Future<void> Function(FitnessGoal) onPick;

  @override
  State<_GoalPage> createState() => _GoalPageState();
}

class _GoalPageState extends State<_GoalPage> {
  FitnessGoal? _selected;
  bool _busy = false;

  Future<void> _choose(FitnessGoal g) async {
    if (_busy) return;
    setState(() {
      _selected = g;
      _busy = true;
    });
    // Let the selection register visually before the push.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    await widget.onPick(g);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What should it help you\nwith first?',
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Everything stays available either way — this just decides what '
            'the app puts in front of you.',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          for (final g in FitnessGoal.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GoalCard(
                goal: g,
                selected: _selected == g,
                onTap: () => _choose(g),
              ),
            ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.selected,
    required this.onTap,
  });

  final FitnessGoal goal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer
            : scheme.surface.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.7),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(goal.icon, color: scheme.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        goal.subtitle,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.arrow_forward_ios_rounded,
                  size: selected ? 22 : 14,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Shared bits
// ─────────────────────────────────────────────────────────────────────

/// Staggered fade + rise, so the hero assembles itself instead of
/// appearing all at once.
///
/// Stateful purely so the CurvedAnimation is created once and disposed —
/// building one per frame leaks in current Flutter.
class _Fade extends StatefulWidget {
  const _Fade({
    required this.enter,
    required this.delay,
    required this.child,
  });

  final AnimationController enter;
  final double delay;
  final Widget child;

  @override
  State<_Fade> createState() => _FadeState();
}

class _FadeState extends State<_Fade> {
  late final CurvedAnimation anim = CurvedAnimation(
    parent: widget.enter,
    curve: Interval(widget.delay, math.min(1.0, widget.delay + 0.55),
        curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - anim.value)),
          child: c,
        ),
      ),
      child: widget.child,
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
    required this.color,
  });

  final int count;
  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: color.withValues(alpha: i == index ? 1 : 0.28),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
