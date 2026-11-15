import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Dark Theme Neutral Foundations
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color surfaceElevated = Color(0xFF2C2C2C);
  static const Color card = Color(0xFF242424);
  static const Color border = Color(0xFF383838);

  // Player Column Hues (Distinct, High-Contrast)
  static const Color player1 = Color(0xFF2979FF); // Electric Blue
  static const Color player2 = Color(0xFFFF5252); // Coral Red
  static const Color player3 = Color(0xFF00E676); // Lime Green

  // Dimmed / Locked-Out States
  static const Color player1Dim = Color(0x332979FF);
  static const Color player2Dim = Color(0x33FF5252);
  static const Color player3Dim = Color(0x3300E676);

  // Status & Feedback Accents
  static const Color correct = Color(0xFF00E676);
  static const Color incorrect = Color(0xFFFF5252);
  static const Color warning = Color(0xFFFFD600);
  static const Color countdownProgress = Color(0xFFFF9100);

  // Typography
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textDisabled = Color(0xFF6E6E6E);

  /// Returns the corresponding player color given a 0-indexed player index (0, 1, 2)
  static Color getPlayerColor(int index) {
    switch (index) {
      case 0:
        return player1;
      case 1:
        return player2;
      case 2:
        return player3;
      default:
        return surfaceElevated;
    }
  }

  /// Returns the dimmed color for locked out state
  static Color getPlayerDimColor(int index) {
    switch (index) {
      case 0:
        return player1Dim;
      case 1:
        return player2Dim;
      case 2:
        return player3Dim;
      default:
        return surface;
    }
  }
}
