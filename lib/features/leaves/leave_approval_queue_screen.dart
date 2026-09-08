import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/leave_model.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/status_chip.dart';

class LeaveApprovalQueueScreen extends ConsumerStatefulWidget {
  const LeaveApprovalQueueScreen({super.key});

  @override
  ConsumerState<LeaveApprovalQueueScreen> createState() => _LeaveApprovalQueueScreenState();
}

class _LeaveApprovalQueueScreenState extends ConsumerState<LeaveApprovalQueueScreen> {
  String _selectedStatusFilter = 'all';

  void _confirmReview(LeaveModel leave, String decision) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision == 'approved' ? 'Approve Leave' : 'Reject Leave'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to $decision the leave request for ${leave.userName}?'),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              decoration: const InputDecoration(
                labelText: 'Comment / Reason (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: decision == 'approved' ? AppColors.success : AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(appStateProvider.notifier).reviewLeave(
                    leaveId: leave.id,
                    decision: decision,
                    comment: commentController.text.trim().isNotEmpty ? commentController.text.trim() : null,
                  );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Leave request $decision successfully.'),
                    backgroundColor: decision == 'approved' ? AppColors.success : AppColors.danger,
                  ),
                );
              }
            },
            child: Text(decision == 'approved' ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final leaves = state.leaveRequests.where((l) {
      if (_selectedStatusFilter != 'all') {
        return l.status.name == _selectedStatusFilter;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Manage Leaves ⏳', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: ['all', 'pending', 'approved', 'rejected'].map((filter) {
                final isSelected = _selectedStatusFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter.toUpperCase()),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (_) => setState(() => _selectedStatusFilter = filter),
                  ),
                );
              }).toList(),
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(appStateProvider.notifier).fetchLeave(),
              child: leaves.isEmpty
                  ? Center(
                      child: Text(
                        'No leave requests found',
                        style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.p20),
                      itemCount: leaves.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final leave = leaves[index];
                        final startStr = DateFormat('MMM d').format(leave.startDate);
                        final endStr = DateFormat('MMM d, yyyy').format(leave.endDate);

                        return Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      AppAvatar(url: leave.userAvatar, size: 40, fallbackText: leave.userName),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            leave.userName,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                            ),
                                          ),
                                          Text(
                                            '${leave.type.name.toUpperCase()} • ${leave.totalDays} Days',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  StatusChip.fromLeave(leave.status),
                                ],
                              ),
                              const SizedBox(height: 14),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  leave.reason,
                                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text('Duration: $startStr - $endStr', style: const TextStyle(fontSize: 12, color: Colors.grey)),

                              if (leave.status == LeaveStatus.pending) ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _confirmReview(leave, 'rejected'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.danger,
                                          side: const BorderSide(color: AppColors.danger),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rPill)),
                                        ),
                                        child: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _confirmReview(leave, 'approved'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rPill)),
                                        ),
                                        child: const Text('Approve'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
