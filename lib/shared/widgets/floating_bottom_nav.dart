import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';

class NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Light, labelled bottom bar. When [onCenterTap] is set, an amber "+" button
/// sits in the middle and [items] are split evenly around it.
class FloatingBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<NavItem> items;
  final VoidCallback? onCenterTap;

  const FloatingBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.onCenterTap,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final half = (items.length / 2).ceil();

    final tabs = [
      for (int i = 0; i < items.length; i++) _buildTab(i),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottomPadding > 0 ? bottomPadding : 10),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: onCenterTap == null
            ? tabs
            : [
                ...tabs.take(half),
                _buildCenterButton(),
                ...tabs.skip(half),
              ],
      ),
    );
  }

  Widget _buildTab(int index) {
    final item = items[index];
    final isSelected = index == currentIndex;
    final color = isSelected ? AppColors.ink : AppColors.textTertiary;

    return Expanded(
      child: Semantics(
        selected: isSelected,
        button: true,
        label: item.label,
        child: GestureDetector(
          onTap: () => onTap(index),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isSelected ? item.selectedIcon : item.icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: color,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Semantics(
        button: true,
        label: 'Quick actions',
        child: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: AppShadows.raised,
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              key: const ValueKey('nav_center_action'),
              customBorder: const CircleBorder(),
              onTap: onCenterTap,
              child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
