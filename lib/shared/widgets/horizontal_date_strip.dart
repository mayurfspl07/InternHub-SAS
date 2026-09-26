import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import 'reference_components.dart';

/// Week strip: weekday labels above white day circles.
/// The selected day is amber; today gets an amber ring.
class HorizontalDateStrip extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final EdgeInsetsGeometry padding;
  final bool showMonthHeader;

  const HorizontalDateStrip({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 12),
    this.showMonthHeader = true,
  });

  @override
  State<HorizontalDateStrip> createState() => _HorizontalDateStripState();
}

class _HorizontalDateStripState extends State<HorizontalDateStrip> {
  late DateTime _currentWeekStart;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = widget.selectedDate.subtract(
      Duration(days: widget.selectedDate.weekday - 1),
    );
  }

  void _shiftWeek(int days) {
    setState(() => _currentWeekStart = _currentWeekStart.add(Duration(days: days)));
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(widget.selectedDate);
    final days = List.generate(7, (index) => _currentWeekStart.add(Duration(days: index)));

    return Padding(
      padding: widget.padding,
      child: Column(
        children: [
          if (widget.showMonthHeader) Row(
            children: [
              Expanded(child: Text(monthLabel, style: AppTypography.cardTitle.copyWith(fontSize: 16))),
              CircularIconButton(icon: Icons.chevron_left_rounded, size: 34, iconSize: 18, onTap: () => _shiftWeek(-7)),
              const SizedBox(width: 8),
              CircularIconButton(icon: Icons.chevron_right_rounded, size: 34, iconSize: 18, onTap: () => _shiftWeek(7)),
            ],
          ),
          if (widget.showMonthHeader) const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: days.map((date) {
              final isSelected = DateUtils.isSameDay(date, widget.selectedDate);
              final isToday = DateUtils.isSameDay(date, DateTime.now());

              return GestureDetector(
                onTap: () => widget.onDateSelected(date),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  children: [
                    Text(
                      DateFormat('E').format(date),
                      style: AppTypography.caption.copyWith(
                        color: isSelected ? AppColors.ink : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surface,
                        shape: BoxShape.circle,
                        border: isToday && !isSelected
                            ? Border.all(color: AppColors.primary, width: 1.5)
                            : null,
                      ),
                      child: Text(
                        DateFormat('d').format(date),
                        style: AppTypography.bodyStrong.copyWith(
                          fontSize: 15,
                          color: isSelected ? Colors.white : AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
