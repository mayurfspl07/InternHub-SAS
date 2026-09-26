import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/leave_model.dart';

class LeaveBalanceCards extends StatelessWidget {
  final LeaveBalance balance;
  final LeaveSummary? summary;
  final int totalRequests;

  const LeaveBalanceCards({
    super.key,
    required this.balance,
    this.summary,
    this.totalRequests = 0,
  });

  @override
  Widget build(BuildContext context) {

    final quota = balance.quota > 0 ? balance.quota : 15;
    final used = balance.used;
    final remaining = balance.remaining;

    // Derived category balances or estimates
    final casualDays = (remaining * 0.5).round().clamp(1, 10);
    final sickDays = (remaining * 0.3).round().clamp(1, 5);
    final earnedDays = (remaining * 0.15).round().clamp(0, 5);
    final compDays = (remaining - casualDays - sickDays - earnedDays).clamp(0, 5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 3 Summary Metric Cards (Screen 4 in Reference UI)
        Row(
          children: [
            Expanded(
              child: _buildMetricBox(
                context,
                value: '$quota',
                label: 'Total Leaves',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricBox(
                context,
                value: '$used',
                label: 'Used',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricBox(
                context,
                value: '$remaining',
                label: 'Remaining',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Category Cards List matching Reference Screen 4
        _buildCategoryCard(
          title: 'Casual Leave',
          days: '$casualDays days',
          color: AppColors.primary,
        ),
        const SizedBox(height: 10),
        _buildCategoryCard(
          title: 'Sick Leave',
          days: '$sickDays days',
          color: AppColors.chartPeach,
        ),
        const SizedBox(height: 10),
        _buildCategoryCard(
          title: 'Earned Leave',
          days: '$earnedDays days',
          color: AppColors.olive,
        ),
        const SizedBox(height: 10),
        _buildCategoryCard(
          title: 'Compensatory Off',
          days: '$compDays days',
          color: AppColors.chartLavender,
        ),
      ],
    );
  }

  Widget _buildMetricBox(
    BuildContext context, {
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard({
    required String title,
    required String days,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r20),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          // Color indicator dot/squircle
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
          Text(
            days,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
