import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import 'reference_components.dart';

/// Standard sub-page header from the reference: white round back button,
/// centered title (+ optional subtitle) and up to two round actions.
/// The back button shows only when the route can pop (or [onBack] is set),
/// so screens that also live inside the bottom-nav tabs stay clean.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final bool? showBack;
  final EdgeInsetsGeometry padding;

  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.onBack,
    this.showBack,
    this.padding = const EdgeInsets.fromLTRB(AppSpacing.p20, AppSpacing.p12, AppSpacing.p20, AppSpacing.p12),
  });

  @override
  Widget build(BuildContext context) {
    final canPop = showBack ?? (onBack != null || (ModalRoute.of(context)?.canPop ?? false));
    const slot = 44.0;
    final actionWidth = actions.isEmpty ? slot : actions.length * slot + (actions.length - 1) * 8;
    final sideWidth = actionWidth > slot ? actionWidth : slot;

    return Padding(
      padding: padding,
      child: Row(
        children: [
          SizedBox(
            width: sideWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: canPop
                  ? CircularIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      iconSize: 18,
                      tooltip: 'Back',
                      onTap: onBack ?? () => Navigator.maybePop(context),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle.copyWith(fontSize: 17),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: sideWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Round white action for [PageHeader] / [pageAppBar] (refresh, export, "more").
/// [tooltip] is required: it names the icon for long-press and screen readers.
class HeaderAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final Color? color;

  const HeaderAction({super.key, required this.icon, required this.tooltip, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return CircularIconButton(icon: icon, onTap: onTap, iconSize: 19, iconColor: color ?? AppColors.ink, tooltip: tooltip);
  }
}

/// [AppBar] version of [PageHeader] for screens that need an AppBar
/// (e.g. with a TabBar in `bottom`).
PreferredSizeWidget pageAppBar(
  BuildContext context, {
  required String title,
  List<Widget> actions = const [],
  PreferredSizeWidget? bottom,
  VoidCallback? onBack,
}) {
  final canPop = onBack != null || (ModalRoute.of(context)?.canPop ?? false);
  return AppBar(
    backgroundColor: AppColors.canvas,
    surfaceTintColor: Colors.transparent,
    centerTitle: true,
    toolbarHeight: 66,
    automaticallyImplyLeading: false,
    leadingWidth: 62,
    leading: canPop
        ? Padding(
            padding: const EdgeInsets.only(left: AppSpacing.p20),
            child: Center(
              child: CircularIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                tooltip: 'Back',
                onTap: onBack ?? () => Navigator.maybePop(context),
              ),
            ),
          )
        : null,
    title: Text(title, style: AppTypography.cardTitle.copyWith(fontSize: 17)),
    actions: [
      for (final a in actions) Padding(padding: const EdgeInsets.only(right: 8), child: Center(child: a)),
      const SizedBox(width: AppSpacing.p12),
    ],
    bottom: bottom,
  );
}
