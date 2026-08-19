import 'dart:math';
import 'package:flutter/material.dart';
import '../models/fasting_zone.dart';

/// Draws the multi-coloured zone ring background + progress arc.
class ZoneRingPainter extends CustomPainter {
  final double progress; // 0.0–1.0
  final int goalHours;
  final Color currentZoneColor;

  const ZoneRingPainter({
    required this.progress,
    required this.goalHours,
    required this.currentZoneColor,
  });

  static const _strokeWidth = 24.0;
  static const _startAngle = -pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - _strokeWidth;

    // ── Background zone arcs (faded) ─────────────────────────────
    for (final zone in kFastingZones) {
      final zStart = zone.fromHour / goalHours;
      final zEnd = (zone.toHour >= 999
              ? goalHours.toDouble()
              : zone.toHour.toDouble()) /
          goalHours;
      if (zStart >= 1.0) break;
      final clampedEnd = zEnd.clamp(0.0, 1.0);
      if (clampedEnd <= zStart) continue;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle + 2 * pi * zStart,
        2 * pi * (clampedEnd - zStart),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.butt
          ..color = zone.color.withValues(alpha: 0.18),
      );
    }

    // ── Progress arc — whole ring in the CURRENT zone colour ─────
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _startAngle,
        2 * pi * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = currentZoneColor,
      );
    }

    // ── Zone dividers ("|") ─────────────────────────────────────
    // Small radial ticks mark each zone boundary.
    final dividerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black.withValues(alpha: 0.35);

    for (final zone in kFastingZones) {
      final zStart = zone.fromHour / goalHours;
      final zEnd = (zone.toHour >= 999
              ? goalHours.toDouble()
              : zone.toHour.toDouble()) /
          goalHours;
      final segStart = zStart.clamp(0.0, 1.0);
      final segEnd = zEnd.clamp(0.0, 1.0);
      final sweep = segEnd - segStart;
      if (sweep <= 0) continue;

      // Divider at the START of each zone (skip the 12 o'clock origin —
      // the goal tick already lives there).
      if (segStart > 0 && segStart < 1.0) {
        final a = _startAngle + 2 * pi * segStart;
        final dir = Offset(cos(a), sin(a));
        canvas.drawLine(
          center + dir * (radius - _strokeWidth / 2),
          center + dir * (radius + _strokeWidth / 2),
          dividerPaint,
        );
      }
    }

    // ── Goal tick at 12 o'clock ───────────────────────────────────
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.4);
    final tickOuter =
        center + Offset(0, -(radius + _strokeWidth / 2 + 4));
    final tickInner =
        center + Offset(0, -(radius - _strokeWidth / 2 - 4));
    canvas.drawLine(tickInner, tickOuter, tickPaint);
  }

  @override
  bool shouldRepaint(ZoneRingPainter old) =>
      old.progress != progress ||
      old.goalHours != goalHours ||
      old.currentZoneColor != currentZoneColor;
}
