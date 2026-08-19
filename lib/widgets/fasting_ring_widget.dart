import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/fasting_provider.dart';
import 'zone_ring_painter.dart';

class FastingRingWidget extends StatelessWidget {
  /// Diameter of the ring. The home screen passes the largest size that
  /// fits, so the ring grows with the available space.
  final double size;

  const FastingRingWidget({super.key, this.size = 280});

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    final zone = fp.currentZone;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: ZoneRingPainter(
          progress: fp.progress,
          goalHours: fp.protocol.hours,
          currentZoneColor: zone.color,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Zone name — coloured to match zone
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: Text(
                  zone.name,
                  key: ValueKey('${zone.name}label'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: zone.color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // HH:MM:SS
              Text(
                fp.isFasting ? fp.formatDuration(fp.elapsed) : '00:00:00',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                fp.isFasting ? 'Goal: ${fp.protocol.label}' : 'Not fasting',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
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
