import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/status_chip.dart';
import 'apply_leave_bottom_sheet.dart';
import 'leave_approval_queue_screen.dart';

class LeaveDashboardScreen extends ConsumerWidget {
  const LeaveDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final balance = state.leaveBalance;
    final leaves = state.leaveRequests;
    final isMentorOrAdmin = state.currentUser.role == UserRole.admin ||
        state.currentUser.role == UserRole.mentor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Management 🏖️', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(appStateProvider.notifier).fetchLeaves(),
          ),
          if (isMentorOrAdmin)
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: 'Review Approvals',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LeaveApprovalQueueScreen()),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchLeaves(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.p20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Leave Quota Grid
                Text(
                  'Leave Balance Quotas',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    _buildQuotaCard('Remaining', '${balance.remaining} Days', AppColors.cardGreen, isDark),
                    const SizedBox(width: 10),
                    _buildQuotaCard('Used', '${balance.used} Days', AppColors.cardYellow, isDark),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildQuotaCard('Pending', '${balance.pending} Days', AppColors.cardPink, isDark),
                    const SizedBox(width: 10),
                    _buildQuotaCard('Total Quota', '${balance.quota} Days', AppColors.cardBlue, isDark),
                  ],
                ),
                const SizedBox(height: 24),

                // Apply Leave Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        builder: (_) => const ApplyLeaveBottomSheet(),
                      );
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Apply for Leave'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Leave Applications History
                Text(
                  'Leave History & Approvals',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 14),

                if (leaves.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? AppColors.borderDark : AppColors.borderLight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.beach_access_outlined, size: 48, color: isDark ? Colors.white38 : AppColors.textSecondaryLight),
                        const SizedBox(height: 12),
                        Text(
                          'No leave requests found',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your submitted leave requests will appear here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: leaves.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final leave = leaves[index];
                      final startStr = DateFormat('MMM d').format(leave.startDate);
                      final endStr = DateFormat('MMM d, yyyy').format(leave.endDate);

                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark ? AppColors.borderDark : AppColors.borderLight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${leave.type.name.toUpperCase()} LEAVE (${leave.totalDays} Day${leave.totalDays > 1 ? 's' : ''})',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                                StatusChip.fromLeave(leave.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$startStr - $endStr',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : AppColors.textPrimaryLight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              leave.reason,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                              ),
                            ),
                            if (leave.approvedBy != null && leave.approvedBy!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Reviewed by: ${leave.approvedBy}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success),
                              ),
                            ],
                            if (leave.rejectionReason != null && leave.rejectionReason!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Reason: ${leave.rejectionReason}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.redAccent),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuotaCard(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: isDark ? Border.all(color: AppColors.borderDark) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
