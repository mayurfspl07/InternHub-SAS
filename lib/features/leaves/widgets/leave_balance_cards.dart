import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/leave_model.dart';

/// The intern's leave balance exactly as `GET /api/leave/mine` reports it.
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

  String _days(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final pending = balance.pending ?? 0;
    final afterPending = balance.available_after_pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildMetricBox(value: _days(balance.quota), label: 'Total leaves')),
            const SizedBox(width: 10),
            Expanded(child: _buildMetricBox(value: _days(balance.used), label: 'Used')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildMetricBox(value: _days(pending), label: 'Pending')),
            const SizedBox(width: 10),
            Expanded(child: _buildMetricBox(value: _days(balance.remaining), label: 'Remaining')),
          ],
        ),
        if (afterPending != null && pending > 0) ...[
          const SizedBox(height: 12),
          Text(
            '${_days(afterPending)} days left if your pending requests are approved.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  Widget _buildMetricBox({required String value, required String label}) {
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
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
