import 'package:flutter/material.dart';

/// Curated color palette directly derived from the reference UI designs:
/// - Vibrant pastel/candy accent cards (Purple, Yellow, Electric Pink, Sky Blue, Mint)
/// - Dark Obsidian floating bottom dock (#161922)
/// - Crisp neutral canvas (#F7F8FC)
class AppColors {
  // Primary Brand & Backgrounds
  static const Color primary = Color(0xFF7B61FF); // Vibrant Cyber Lilac / Purple
  static const Color primaryDark = Color(0xFF634AD8);
  static const Color primaryLight = Color(0xFFEDE9FE);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color accent = Color(0xFF38BDF8);

  static const Color backgroundLight = Color(0xFFF7F8FC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color cardLight = Color(0xFFFFFFFF);

  static const Color backgroundDark = Color(0xFF0F1117);
  static const Color surfaceDark = Color(0xFF181A22);
  static const Color cardDark = Color(0xFF1E212B);

  // Floating Navigation Dock
  static const Color dockBackground = Color(0xFF161922);
  static const Color dockActive = Color(0xFF7B61FF);
  static const Color dockInactive = Color(0xFF8E95A5);

  // Signature Vibrant Card Colors (from attached design screenshots)
  static const Color cardYellow = Color(0xFFFFE043); // Sunshine Yellow
  static const Color cardYellowDark = Color(0xFFE5C522);
  static const Color cardPurple = Color(0xFF8B5CF6); // Soft Cyber Violet
  static const Color cardPurpleLight = Color(0xFFDDD6FE);
  static const Color cardPink = Color(0xFFF43F5E); // Electric Hot Pink
  static const Color cardPinkLight = Color(0xFFFCE7F3);
  static const Color cardBlue = Color(0xFF38BDF8); // Sky Blue
  static const Color cardBlueLight = Color(0xFFE0F2FE);
  static const Color cardGreen = Color(0xFF34D399); // Mint Emerald
  static const Color cardGreenLight = Color(0xFFD1FAE5);
  static const Color cardOrange = Color(0xFFFB923C); // Warm Tangerine
  static const Color cardOrangeLight = Color(0xFFFFEDD5);

  // Action Elements
  static const Color actionCircleDark = Color(0xFF181A20);
  static const Color actionCircleLight = Color(0xFFFFFFFF);

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Text Colors
  static const Color textPrimaryLight = Color(0xFF111827);
  static const Color textSecondaryLight = Color(0xFF6B7280);
  static const Color textTertiaryLight = Color(0xFF9CA3AF);

  static const Color textPrimaryDark = Color(0xFFF9FAFB);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);
  static const Color textTertiaryDark = Color(0xFF6B7280);

  // Borders & Dividers
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color borderDark = Color(0xFF2E3342);
}
