import 'package:flutter/material.dart';
import 'app_avatar.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import 'avatar_stack.dart';

/// White, borderless rounded card sitting on the canvas.
class ReferenceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final double borderRadius;
  final Border? border;
  final double? width;
  final double? height;

  const ReferenceCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.onTap,
    this.borderRadius = AppSpacing.rCard,
    this.border,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.surface;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: bg == AppColors.surface ? AppShadows.soft : AppShadows.none,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppSpacing.p16),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 2-column grid card with avatar, title, metric and an arrow action.
/// [isFeaturedYellow] renders the amber variant.
class GridFeatureCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String metricValue;
  final String? metricLabel;
  final String? avatarUrl;
  final String? initials;
  final bool isFeaturedYellow;
  final VoidCallback? onTap;

  const GridFeatureCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.metricValue,
    this.metricLabel,
    this.avatarUrl,
    this.initials,
    this.isFeaturedYellow = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isFeaturedYellow ? AppColors.primary : AppColors.surface;
    final subtitleColor = isFeaturedYellow ? AppColors.ink.withValues(alpha: 0.7) : AppColors.textSecondary;
    final actionBg = isFeaturedYellow ? AppColors.surface : AppColors.surfaceMuted;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        boxShadow: isFeaturedYellow ? AppShadows.none : AppShadows.soft,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.rCard),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppAvatar(url: avatarUrl, size: 40, fallbackText: initials ?? title),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.cardTitle,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.label.copyWith(color: subtitleColor, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metricValue, style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
                          if (metricLabel != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              metricLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.label.copyWith(color: subtitleColor, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: actionBg, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_outward_rounded, size: 17, color: AppColors.ink),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Background tone for [InteractionHistoryCard].
enum HistoryCardTheme {
  amber,
  peach,
  lavender,
  sage,
  sand,
  white,
}

class InteractionHistoryCard extends StatelessWidget {
  final String dateText;
  final String title;
  final String metricValue;
  final List<String> avatarUrls;
  final HistoryCardTheme cardTheme;
  final VoidCallback? onTap;

  const InteractionHistoryCard({
    super.key,
    required this.dateText,
    required this.title,
    required this.metricValue,
    this.avatarUrls = const [],
    this.cardTheme = HistoryCardTheme.amber,
    this.onTap,
  });

  static Color backgroundFor(HistoryCardTheme theme) {
    switch (theme) {
      case HistoryCardTheme.amber:
        return AppColors.primary;
      case HistoryCardTheme.peach:
        return AppColors.peach;
      case HistoryCardTheme.lavender:
        return AppColors.lavender;
      case HistoryCardTheme.sage:
        return AppColors.sage;
      case HistoryCardTheme.sand:
        return AppColors.sand;
      case HistoryCardTheme.white:
        return AppColors.surface;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundFor(cardTheme);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.rHero),
        boxShadow: cardTheme == HistoryCardTheme.white ? AppShadows.soft : AppShadows.none,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.rHero),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.rHero),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        dateText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: AppColors.ink.withValues(alpha: 0.7)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_outward_rounded, size: 18, color: AppColors.ink),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppTypography.section),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        metricValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.title.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (avatarUrls.isNotEmpty) AvatarStack(avatarUrls: avatarUrls, size: 32),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact metric tile: optional tinted icon circle, value and label.
class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color? accentColor;
  final VoidCallback? onTap;
  final double? width;

  const StatCard({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.accentColor,
    this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.primaryInk;

    return ReferenceCard(
      width: width,
      borderRadius: AppSpacing.rTile,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(height: 10),
          ],
          Text(value, style: AppTypography.title.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(label, style: AppTypography.caption),
        ],
      ),
    );
  }
}

/// Horizontal pill filter. Selected pill is amber, the rest are white.
class PillFilter extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const PillFilter({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(options.length, (index) {
          final isSelected = index == selectedIndex;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              button: true,
              selected: isSelected,
              child: InkWell(
                onTap: () => onSelected(index),
                borderRadius: BorderRadius.circular(AppSpacing.rPill),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  ),
                  child: Text(
                    options[index],
                    style: AppTypography.bodyStrong.copyWith(
                      fontSize: 13,
                      color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// White circular icon button (back, close, "more", trailing actions).
/// Pass [tooltip] for icon-only buttons: it is the long-press hint and the screen-reader label.
class CircularIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final double iconSize;
  final String? tooltip;

  const CircularIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.backgroundColor,
    this.iconColor,
    this.size = 44,
    this.iconSize = 20,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = _circle();
    final labelled = Semantics(button: true, label: tooltip, excludeSemantics: tooltip != null, child: button);
    return tooltip == null ? labelled : Tooltip(message: tooltip!, child: labelled);
  }

  Widget _circle() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Center(
            child: Icon(icon, size: iconSize, color: iconColor ?? AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// Full-width amber pill button with dark label.
class PrimaryActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final double? width;
  final Color? backgroundColor;

  const PrimaryActionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.width,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.primary;
    final fg = bg.computeLuminance() > 0.45 ? AppColors.ink : AppColors.surface;

    return SizedBox(
      width: width ?? double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: fg),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(label, overflow: TextOverflow.ellipsis, style: AppTypography.button.copyWith(color: fg)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Section heading ("My Journal") with an optional "See all" action.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onActionTap;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(child: Text(title, style: AppTypography.section)),
        if (actionText != null && onActionTap != null)
          TextButton(
            onPressed: onActionTap,
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryInk, minimumSize: const Size(44, 44)),
            child: Text(actionText!, style: AppTypography.caption.copyWith(color: AppColors.primaryInk, fontSize: 13)),
          ),
      ],
    );
  }
}

/// List row card: leading widget, title/subtitle, trailing text or widget.
class ListItemCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;

  const ListItemCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.rTile),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.caption),
                      ],
                    ],
                  ),
                ),
                if (trailingText != null) ...[
                  const SizedBox(width: 8),
                  Text(trailingText!, style: AppTypography.label.copyWith(fontWeight: FontWeight.w500)),
                ]
                else ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile hero: large avatar, name, subtitle and a row of round actions.
class CustomerHeroHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  final String? avatarUrl;
  final VoidCallback? onNoteTap;
  final VoidCallback? onEmailTap;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onCalendarTap;
  final VoidCallback? onClockTap;

  const CustomerHeroHeader({
    super.key,
    required this.name,
    required this.subtitle,
    this.avatarUrl,
    this.onNoteTap,
    this.onEmailTap,
    this.onPhoneTap,
    this.onCalendarTap,
    this.onClockTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface, width: 3),
            boxShadow: AppShadows.soft,
          ),
          child: AppAvatar(url: avatarUrl, size: 90, fallbackText: name),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.title),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(fontSize: 13),
          ),
        ),
        if ([onNoteTap, onEmailTap, onPhoneTap, onCalendarTap, onClockTap].any((cb) => cb != null)) ...[
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularIconButton(icon: Icons.edit_note_rounded, onTap: onNoteTap, size: 44),
            const SizedBox(width: 12),
            CircularIconButton(icon: Icons.mail_outline_rounded, onTap: onEmailTap, size: 44),
            const SizedBox(width: 12),
            CircularIconButton(icon: Icons.phone_outlined, onTap: onPhoneTap, size: 44),
            const SizedBox(width: 12),
            CircularIconButton(icon: Icons.calendar_today_outlined, onTap: onCalendarTap, size: 44),
            const SizedBox(width: 12),
            CircularIconButton(icon: Icons.event_available_outlined, onTap: onClockTap, size: 44),
          ],
        ),
        ],
      ],
    );
  }

}
