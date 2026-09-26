import 'package:flutter/material.dart';

/// Warm "journal" palette:
/// - Greige canvas with white, borderless cards
/// - Amber primary that always carries dark (ink) text
/// - Cocoa / olive / taupe accents and soft pastel cards
///
/// Light only. Never put amber on text or icons that sit on a light surface;
/// use [primaryInk] or [ink] instead.
class AppColors {
  // Canvas & surfaces
  static const Color canvas = Color(0xFFF1EFEC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF6F4F1);
  static const Color sand = Color(0xFFDDD4CA);

  // Lines
  static const Color border = Color(0xFFE6E1DB);
  static const Color divider = Color(0xFFEDE9E4);

  // Text
  static const Color ink = Color(0xFF1F1C18);
  static const Color textPrimary = ink;
  static const Color textSecondary = Color(0xFF6E675F);
  static const Color textTertiary = Color(0xFFA39B91);

  // Primary (amber)
  static const Color primary = Color(0xFFFDBA2D);
  static const Color onPrimary = ink;
  static const Color primarySoft = Color(0xFFFFF0C7);
  static const Color primaryInk = Color(0xFF8A5A00);

  // Accents
  static const Color cocoa = Color(0xFF6B3A2E);
  static const Color olive = Color(0xFF8C9A33);
  static const Color taupe = Color(0xFF7B7266);

  // Pastel card backgrounds and the ink used for text/tags on them
  static const Color peach = Color(0xFFF8D9D0);
  static const Color peachInk = Color(0xFFB5543F);
  static const Color lavender = Color(0xFFE6E0FB);
  static const Color lavenderInk = Color(0xFF5443B0);
  static const Color butter = Color(0xFFFFEFC2);
  static const Color butterInk = Color(0xFF8A5A00);
  static const Color sage = Color(0xFFE3E8CF);
  static const Color sageInk = Color(0xFF56661A);
  static const Color sandInk = taupe;

  // Semantic: base / soft background / ink (text on soft)
  static const Color success = Color(0xFF7A8F2A);
  static const Color successSoft = Color(0xFFEEF1DD);
  static const Color successInk = Color(0xFF56661A);

  static const Color warning = Color(0xFFE79A14);
  static const Color warningSoft = Color(0xFFFFF0C7);
  static const Color warningInk = Color(0xFF8A5A00);

  static const Color danger = Color(0xFFD2553B);
  static const Color dangerSoft = Color(0xFFFADCD3);
  static const Color dangerInk = Color(0xFFA63A24);

  static const Color info = Color(0xFF7C6BD6);
  static const Color infoSoft = Color(0xFFE6E0FB);
  static const Color infoInk = Color(0xFF5443B0);

  static const Color neutral = taupe;
  static const Color neutralSoft = surfaceMuted;
  static const Color neutralInk = textSecondary;

  // Illustration (hero artwork only)
  static const Color sun = Color(0xFFF08A24);
  static const Color hill = Color(0xFF6E8A2B);

  // Charts
  static const Color chartPeach = Color(0xFFEE9A80);
  static const Color chartLavender = Color(0xFF9D8FE6);
  static const List<Color> chartPalette = [
    primary,
    cocoa,
    olive,
    taupe,
    chartPeach,
    chartLavender,
  ];

  // ---------------------------------------------------------------------------
  // Legacy names, kept so the app compiles while screens migrate.
  // Each points at its light equivalent in the new palette.
  // ---------------------------------------------------------------------------
  @Deprecated('Use AppColors.primaryInk')
  static const Color primaryDark = primaryInk;
  @Deprecated('Use AppColors.primarySoft')
  static const Color primaryLight = primarySoft;
  @Deprecated('Use AppColors.cocoa')
  static const Color secondary = cocoa;
  @Deprecated('Use AppColors.info')
  static const Color accent = info;

  @Deprecated('Use AppColors.canvas')
  static const Color backgroundLight = canvas;
  @Deprecated('Use AppColors.surface')
  static const Color surfaceLight = surface;
  @Deprecated('Use AppColors.surface')
  static const Color cardLight = surface;
  @Deprecated('Use AppColors.surfaceMuted')
  static const Color cardLightTint = surfaceMuted;

  @Deprecated('Light only: use AppColors.canvas')
  static const Color backgroundDark = canvas;
  @Deprecated('Light only: use AppColors.surface')
  static const Color surfaceDark = surface;
  @Deprecated('Light only: use AppColors.surface')
  static const Color cardDark = surface;
  @Deprecated('Light only: use AppColors.surface')
  static const Color cardDarkElevated = surface;

  @Deprecated('Use AppColors.surface')
  static const Color dockBackground = surface;
  @Deprecated('Use AppColors.surface')
  static const Color obsidianNav = surface;
  @Deprecated('Use AppColors.primary')
  static const Color dockActive = primary;
  @Deprecated('Use AppColors.textTertiary')
  static const Color dockInactive = textTertiary;

  @Deprecated('Use AppColors.primary')
  static const Color cardYellow = primary;
  @Deprecated('Use AppColors.butter')
  static const Color cardYellowLight = butter;
  @Deprecated('Light only: use AppColors.butter')
  static const Color cardYellowDark = butter;

  @Deprecated('Use AppColors.info')
  static const Color cardPurple = info;
  @Deprecated('Use AppColors.lavender')
  static const Color cardPurpleLight = lavender;
  @Deprecated('Light only: use AppColors.lavender')
  static const Color cardPurpleDark = lavender;

  @Deprecated('Use AppColors.peachInk')
  static const Color cardPink = peachInk;
  @Deprecated('Use AppColors.peach')
  static const Color cardPinkLight = peach;
  @Deprecated('Light only: use AppColors.peach')
  static const Color cardPinkDark = peach;

  @Deprecated('Use AppColors.info')
  static const Color cardBlue = info;
  @Deprecated('Use AppColors.infoSoft')
  static const Color cardBlueLight = infoSoft;
  @Deprecated('Light only: use AppColors.infoSoft')
  static const Color cardBlueDark = infoSoft;

  @Deprecated('Use AppColors.success')
  static const Color cardGreen = success;
  @Deprecated('Use AppColors.sage')
  static const Color cardGreenLight = sage;
  @Deprecated('Light only: use AppColors.sage')
  static const Color cardGreenDark = sage;

  @Deprecated('Use AppColors.warning')
  static const Color cardOrange = warning;
  @Deprecated('Use AppColors.peach')
  static const Color cardOrangeLight = peach;
  @Deprecated('Light only: use AppColors.peach')
  static const Color cardOrangeDark = peach;

  @Deprecated('Use AppColors.sand')
  static const Color cardBeige = sand;
  @Deprecated('Use AppColors.surfaceMuted')
  static const Color cardBeigeLight = surfaceMuted;
  @Deprecated('Light only: use AppColors.sand')
  static const Color cardBeigeDark = sand;

  @Deprecated('Use AppColors.primary')
  static const Color accentYellow = primary;
  @Deprecated('Use AppColors.info')
  static const Color accentLilac = info;
  @Deprecated('Use AppColors.info')
  static const Color accentCyan = info;
  @Deprecated('Use AppColors.peachInk')
  static const Color accentPink = peachInk;
  @Deprecated('Use AppColors.success')
  static const Color accentGreen = success;
  @Deprecated('Use AppColors.warning')
  static const Color accentOrange = warning;
  @Deprecated('Use AppColors.sand')
  static const Color accentBeige = sand;

  @Deprecated('Light only: use AppColors.surface')
  static const Color actionCircleDark = surface;
  @Deprecated('Use AppColors.surface')
  static const Color actionCircleLight = surface;

  @Deprecated('Use AppColors.ink')
  static const Color textPrimaryLight = ink;
  @Deprecated('Use AppColors.textSecondary')
  static const Color textSecondaryLight = textSecondary;
  @Deprecated('Use AppColors.textTertiary')
  static const Color textTertiaryLight = textTertiary;

  @Deprecated('Light only: use AppColors.ink')
  static const Color textPrimaryDark = ink;
  @Deprecated('Light only: use AppColors.textSecondary')
  static const Color textSecondaryDark = textSecondary;
  @Deprecated('Light only: use AppColors.textTertiary')
  static const Color textTertiaryDark = textTertiary;

  @Deprecated('Use AppColors.border')
  static const Color borderLight = border;
  @Deprecated('Light only: use AppColors.border')
  static const Color borderDark = border;
}
