import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';

/// "‹  Page 2 of 5 · 48 interns  ›" that fits a 360px phone: the label shrinks
/// between two 44px chevron buttons instead of pushing them off-screen.
/// Hidden when there is only one page.
class PaginationBar extends StatelessWidget {
  final int page;
  final int totalPages;
  final int? totalItems;

  /// Plural noun for [totalItems] ("interns"); the singular drops a trailing "s".
  final String itemLabel;
  final ValueChanged<int> onPageChanged;
  final bool isLoading;
  final EdgeInsetsGeometry padding;

  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPageChanged,
    this.totalItems,
    this.itemLabel = 'items',
    this.isLoading = false,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    final count = totalItems;
    final noun = count == 1 && itemLabel.endsWith('s') ? itemLabel.substring(0, itemLabel.length - 1) : itemLabel;
    final label = count == null ? 'Page $page of $totalPages' : 'Page $page of $totalPages · $count $noun';

    return Padding(
      padding: padding,
      child: Row(
        children: [
          _arrow(Icons.chevron_left_rounded, 'Previous page', page > 1 && !isLoading ? () => onPageChanged(page - 1) : null),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption,
            ),
          ),
          _arrow(
            Icons.chevron_right_rounded,
            'Next page',
            page < totalPages && !isLoading ? () => onPageChanged(page + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, String tooltip, VoidCallback? onTap) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon),
      color: AppColors.ink,
      disabledColor: AppColors.border,
      style: IconButton.styleFrom(
        backgroundColor: onTap == null ? AppColors.surfaceMuted : AppColors.surface,
        minimumSize: const Size(44, 44),
      ),
    );
  }
}
