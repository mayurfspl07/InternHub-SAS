import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
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

/// Light, labelled bottom bar with evenly spaced tabs.
class FloatingBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final List<NavItem> items;

  const FloatingBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(4, 6, 4, bottomPadding > 0 ? bottomPadding : 8),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [for (int i = 0; i < items.length; i++) _buildTab(i)],
      ),
    );
  }

  Widget _buildTab(int index) {
    final item = items[index];
    final isSelected = index == currentIndex;
    final color = isSelected ? AppColors.ink : AppColors.textSecondary;

    return Expanded(
      child: Semantics(
        selected: isSelected,
        button: true,
        label: item.label,
        excludeSemantics: true,
        child: InkWell(
          onTap: () => onTap(index),
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
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
      ),
    );
  }
}
