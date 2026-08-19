import 'package:flutter/material.dart';

class HealthyFastTitle extends StatelessWidget {
  const HealthyFastTitle({super.key});

  /// Logical størrelse ikonet faktisk tegnes i.
  static const double _size = 28;

  @override
  Widget build(BuildContext context) {
    // 'new icon.png' er 512x512. Uten cacheWidth/cacheHeight dekoder Flutter
    // hele bildet (512*512*4 B ≈ 1 MB ARGB) inn i bildecachen selv om det
    // vises 28x28 dp — og denne tittelen sitter i AppBar på hver skjerm.
    // Play Console flagget dette som "nedskalert punktgrafikk". Vi ber i
    // stedet om nøyaktig antall fysiske piksler skjermen trenger (~112 px på
    // 4x), som kutter dekodet størrelse med ~95 %.
    final int cacheSize =
        (_size * MediaQuery.devicePixelRatioOf(context)).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'new icon.png',
            width: _size,
            height: _size,
            cacheWidth: cacheSize,
            cacheHeight: cacheSize,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'HealthyFast',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}
