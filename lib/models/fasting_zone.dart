import 'package:flutter/material.dart';

/// A fasting phase with its colour, tip, and scientific source.
class FastingZone {
  final String name;
  final String emoji;
  final int fromHour; // inclusive
  final int toHour;   // exclusive; 999 = open-ended
  final Color color;
  final String tip;
  final String source;
  final String shortLabel;

  const FastingZone({
    required this.name,
    required this.emoji,
    required this.fromHour,
    required this.toHour,
    required this.color,
    required this.tip,
    required this.source,
    required this.shortLabel,
  });
}

/// All seven fasting zones, sourced from peer-reviewed research
/// and leading fasting researchers.
const List<FastingZone> kFastingZones = [
  FastingZone(
    name: 'Fed State',
    emoji: '🍽️',
    fromHour: 0,
    toHour: 4,
    color: Color(0xFF9E9E9E),
    shortLabel: '0–4h',
    tip: 'Your body is still processing your last meal. Insulin is elevated, directing glucose into cells for energy and storage. The fast has already started — every hour counts.',
    source: 'Cahill GF Jr., "Fuel Metabolism in Starvation," Annual Review of Nutrition (2006)',
  ),
  FastingZone(
    name: 'Early Fast',
    emoji: '🌅',
    fromHour: 4,
    toHour: 8,
    color: Color(0xFFFFC107),
    shortLabel: '4–8h',
    tip: 'Insulin is falling and blood sugar is stabilising. Your liver begins releasing stored glucose (glycogen) to maintain energy. This is why hunger feels manageable — your body has reserves.',
    source: 'Dr. Jason Fung, The Obesity Code (2016); The Fasting Method',
  ),
  FastingZone(
    name: 'Glycogen Burning',
    emoji: '🔥',
    fromHour: 8,
    toHour: 14,
    color: Color(0xFFFF7043),
    shortLabel: '8–14h',
    tip: 'What you\'re feeling now is your body\'s fuel changing. Liver glycogen is depleting and your metabolism is preparing to switch to fat. Hunger waves are driven by ghrelin — a hormone signal, not true starvation. They pass within 20 minutes.',
    source: 'de Cabo R & Mattson MP, New England Journal of Medicine (2019)',
  ),
  FastingZone(
    name: 'Metabolic Switch',
    emoji: '⚡',
    fromHour: 14,
    toHour: 18,
    color: Color(0xFF29B6F6),
    shortLabel: '14–18h',
    tip: 'The metabolic switch is flipping. After 10–14 hours, your liver begins converting fatty acids into ketone bodies — a clean-burning, efficient fuel for your brain. Mental clarity and reduced hunger are common at this stage.',
    source: 'Mattson MP et al., Nature Reviews Neuroscience (2018); NEJM (2019)',
  ),
  FastingZone(
    name: 'Fat Burning',
    emoji: '💪',
    fromHour: 18,
    toHour: 24,
    color: Color(0xFF26A69A),
    shortLabel: '18–24h',
    tip: 'You\'re in active ketosis. Circulating ketone levels are rising, providing your brain with a highly efficient fuel. Research shows elevated ketones support neuroplasticity, reduce inflammation, and sharpen focus.',
    source: 'Veech RL, "The therapeutic implications of ketone bodies," Annals of the New York Academy of Sciences (2004); Dr. Rhonda Patrick, FoundMyFitness',
  ),
  FastingZone(
    name: 'Autophagy',
    emoji: '🔬',
    fromHour: 24,
    toHour: 36,
    color: Color(0xFF9C27B0),
    shortLabel: '24–36h',
    tip: 'Autophagy — your cells\' built-in self-cleaning system — is ramping up. Damaged proteins and dysfunctional organelles are being recycled. This cellular housekeeping won the 2016 Nobel Prize in Physiology or Medicine.',
    source: 'Yoshinori Ohsumi, Nobel Prize in Physiology or Medicine (2016); Alirezaei M et al., Autophagy Journal (2010)',
  ),
  FastingZone(
    name: 'Deep Renewal',
    emoji: '✨',
    fromHour: 36,
    toHour: 999,
    color: Color(0xFF3F51B5),
    shortLabel: '36h+',
    tip: 'Growth hormone can increase 200–1300% during extended fasting, helping preserve lean muscle while your body runs on fat. Autophagy is at peak levels, clearing cellular debris associated with aging and disease.',
    source: 'Ho KY et al., "Fasting enhances growth hormone secretion," Journal of Clinical Investigation (1988); Longo VD & Mattson MP, Cell Metabolism (2014)',
  ),
];

/// Returns the zone for a given elapsed duration.
FastingZone zoneForDuration(Duration elapsed) {
  final hours = elapsed.inMinutes / 60.0;
  return kFastingZones.lastWhere(
    (z) => z.fromHour <= hours,
    orElse: () => kFastingZones.first,
  );
}
