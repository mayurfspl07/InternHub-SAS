import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Figtree everywhere, soft weights (nothing heavier than w700).
/// Use `.copyWith` for one-off size or color tweaks.
class AppTypography {
  static TextStyle get _base => GoogleFonts.figtree(color: AppColors.ink);

  /// Big numeric figure ("420").
  static TextStyle get metric => _base.copyWith(
        fontSize: 44,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        height: 1.1,
      );

  /// Screen greeting ("Hi, Jose Maria").
  static TextStyle get headline => _base.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.2,
      );

  /// Detail page title ("Morning Reflection").
  static TextStyle get title => _base.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.25,
      );

  /// Section heading ("My Journal").
  static TextStyle get section => _base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  /// Card and list item titles.
  static TextStyle get cardTitle => _base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
      );

  static TextStyle get body => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.45,
      );

  static TextStyle get bodyStrong => _base.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.4,
      );

  static TextStyle get caption => _base.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.35,
      );

  static TextStyle get label => _base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: AppColors.textSecondary,
      );

  static TextStyle get button => _base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.onPrimary,
      );

  /// Monospace for codes, tokens and logs.
  static TextStyle get mono => GoogleFonts.robotoMono(
        fontSize: 13,
        color: AppColors.ink,
      );

  // Legacy API: the old styles took an isDark flag. Kept while screens migrate.
  @Deprecated('Use AppTypography.headline')
  static TextStyle displayLarge({bool isDark = false}) => headline;
  @Deprecated('Use AppTypography.title')
  static TextStyle displayMedium({bool isDark = false}) => title;
  @Deprecated('Use AppTypography.section')
  static TextStyle titleLarge({bool isDark = false}) => section;
  @Deprecated('Use AppTypography.cardTitle')
  static TextStyle titleMedium({bool isDark = false}) => cardTitle.copyWith(fontSize: 16);
  @Deprecated('Use AppTypography.body')
  static TextStyle bodyLarge({bool isDark = false}) => body.copyWith(fontSize: 15);
  @Deprecated('Use AppTypography.body')
  static TextStyle bodyMedium({bool isDark = false}) => body;
  @Deprecated('Use AppTypography.label')
  static TextStyle labelLarge({bool isDark = false}) =>
      caption.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink);
  @Deprecated('Use AppTypography.label')
  static TextStyle labelSmall({bool isDark = false}) =>
      label.copyWith(fontWeight: FontWeight.w500, color: AppColors.textTertiary);
}
