import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/fasting_provider.dart';
import '../models/fasting_zone.dart';
import 'zone_detail_sheet.dart';

/// Coloured zone chips, wrapping over multiple rows so all zones
/// stay visible. The current zone is highlighted; others are faded.
class ZoneStripWidget extends StatelessWidget {
  const ZoneStripWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FastingProvider>();
    final currentZone = fp.currentZone;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: kFastingZones.map((zone) {
          final isActive = fp.isFasting && zone.name == currentZone.name;
          return GestureDetector(
            onTap: () => showZoneDetail(context, zone),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isActive
                    ? zone.color
                    : zone.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? zone.color
                      : zone.color.withValues(alpha: 0.3),
                  width: 1.2,
                ),
              ),
              child: Text(
                '${zone.emoji} ${zone.shortLabel}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? Colors.white : zone.color,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
