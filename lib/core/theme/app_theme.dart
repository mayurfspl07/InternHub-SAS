import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';

class AppTheme {
  /// Light system bars that let the warm canvas show through (no black nav-bar strip).
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.butter,
      onPrimaryContainer: AppColors.ink,
      secondary: AppColors.cocoa,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.peach,
      onSecondaryContainer: AppColors.ink,
      tertiary: AppColors.olive,
      onTertiary: Colors.white,
      tertiaryContainer: AppColors.sage,
      onTertiaryContainer: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surfaceMuted,
      surfaceContainer: AppColors.surfaceMuted,
      surfaceContainerHigh: AppColors.canvas,
      surfaceContainerHighest: AppColors.canvas,
      surfaceTint: Colors.transparent,
      outline: AppColors.border,
      outlineVariant: AppColors.divider,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: AppColors.dangerSoft,
      onErrorContainer: AppColors.dangerInk,
      inverseSurface: AppColors.ink,
      onInverseSurface: Colors.white,
      inversePrimary: AppColors.primary,
    );

    final textTheme = GoogleFonts.figtreeTextTheme().apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    final pillShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.rPill),
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rInput),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.canvas,
      canvasColor: AppColors.canvas,
      dividerColor: AppColors.divider,
      splashFactory: InkSparkle.splashFactory,
      fontFamily: GoogleFonts.figtree().fontFamily,
      textTheme: textTheme.copyWith(
        displayLarge: AppTypography.metric,
        displayMedium: AppTypography.headline,
        displaySmall: AppTypography.title,
        headlineLarge: AppTypography.headline,
        headlineMedium: AppTypography.title,
        headlineSmall: AppTypography.section,
        titleLarge: AppTypography.section,
        titleMedium: AppTypography.cardTitle.copyWith(fontSize: 16),
        titleSmall: AppTypography.cardTitle.copyWith(fontSize: 14),
        bodyLarge: AppTypography.body.copyWith(fontSize: 15, color: AppColors.ink),
        bodyMedium: AppTypography.body.copyWith(color: AppColors.ink),
        bodySmall: AppTypography.caption,
        labelLarge: AppTypography.bodyStrong,
        labelMedium: AppTypography.caption,
        labelSmall: AppTypography.label,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.ink,
        selectionColor: AppColors.primarySoft,
        selectionHandleColor: AppColors.primary,
      ),
      iconTheme: const IconThemeData(color: AppColors.ink),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: systemOverlay,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.cardTitle.copyWith(fontSize: 17),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: AppTypography.section,
        contentTextStyle: AppTypography.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.rHero),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: AppColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.rHero)),
        ),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shadowColor: Colors.black26,
        textStyle: AppTypography.bodyStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.r16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textTertiary,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: pillShape,
          textStyle: AppTypography.button,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textTertiary,
          minimumSize: const Size(64, 50),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: pillShape,
          textStyle: AppTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.border, width: 1.2),
          minimumSize: const Size(64, 46),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: pillShape,
          textStyle: AppTypography.button.copyWith(color: AppColors.ink),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryInk,
          shape: pillShape,
          textStyle: AppTypography.bodyStrong,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.ink),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: CircleBorder(),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: AppTypography.body.copyWith(color: AppColors.textTertiary),
        labelStyle: AppTypography.body,
        floatingLabelStyle: AppTypography.caption.copyWith(color: AppColors.ink),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        disabledBorder: inputBorder(AppColors.divider),
        focusedBorder: inputBorder(AppColors.primary, 1.6),
        errorBorder: inputBorder(AppColors.danger),
        focusedErrorBorder: inputBorder(AppColors.danger, 1.6),
        errorStyle: AppTypography.caption.copyWith(color: AppColors.dangerInk),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary,
        disabledColor: AppColors.surfaceMuted,
        checkmarkColor: AppColors.onPrimary,
        labelStyle: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: AppTypography.caption.copyWith(color: AppColors.onPrimary),
        side: const BorderSide(color: AppColors.border),
        shape: pillShape,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : AppColors.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceMuted,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.transparent : AppColors.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.onPrimary),
        side: const BorderSide(color: AppColors.textTertiary, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primaryInk : AppColors.textTertiary,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceMuted,
        circularTrackColor: Colors.transparent,
        refreshBackgroundColor: AppColors.surface,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceMuted,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primary.withValues(alpha: 0.16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.onPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: AppTypography.bodyStrong.copyWith(fontSize: 13),
        unselectedLabelStyle: AppTypography.bodyStrong.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.primary : AppColors.surface,
          ),
          foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
          shape: WidgetStatePropertyAll(pillShape),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.ink,
        textColor: AppColors.ink,
        titleTextStyle: AppTypography.bodyStrong,
        subtitleTextStyle: AppTypography.caption,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r16)),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: AppTypography.bodyStrong.copyWith(color: Colors.white),
        actionTextColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r16)),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.danger,
        textColor: Colors.white,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppSpacing.r8),
        ),
        textStyle: AppTypography.caption.copyWith(color: Colors.white),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: AppColors.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rHero)),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.ink,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
        ),
        todayForegroundColor: const WidgetStatePropertyAll(AppColors.primaryInk),
        todayBorder: const BorderSide(color: AppColors.primary, width: 1.5),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.ink,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : Colors.transparent,
        ),
        rangeSelectionBackgroundColor: AppColors.primarySoft,
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.primaryInk),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.surface,
        dialBackgroundColor: AppColors.surfaceMuted,
        dialHandColor: AppColors.primary,
        dialTextColor: AppColors.ink,
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primarySoft : AppColors.surfaceMuted,
        ),
        hourMinuteTextColor: AppColors.ink,
        dayPeriodColor: AppColors.primarySoft,
        dayPeriodTextColor: AppColors.ink,
        entryModeIconColor: AppColors.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rHero)),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.primaryInk),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      ),
    );
  }
}
