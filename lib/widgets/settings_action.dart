import 'package:flutter/material.dart';
import '../screens/settings_screen.dart';

/// Gear icon for the AppBar — Settings lives here on every main screen
/// instead of occupying a bottom-navigation slot.
Widget settingsAction(BuildContext context) => IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: 'Settings',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      ),
    );
