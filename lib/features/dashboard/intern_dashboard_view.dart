import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/widgets/vibrant_card.dart';
import '../../shared/widgets/segmented_progress_bar.dart';
import '../../shared/widgets/status_chip.dart';
import '../attendance/checkin_checkout_screen.dart';
import '../standup/standup_screen.dart';
import '../projects_tasks/task_detail_screen.dart';
import '../projects_tasks/create_task_bottom_sheet.dart';
import '../leaves/leave_dashboard_screen.dart';

class InternDashboardView extends ConsumerStatefulWidget {
  const InternDashboardView({super.key});

  @override
  ConsumerState<InternDashboardView> createState() => _InternDashboardViewState();
}

class _InternDashboardViewState extends ConsumerState<InternDashboardView> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = state.currentUser;
    final dashboard = state.internDashboard;
    final tasks = state.tasks;
    final todayAttendance = state.todayAttendance;

    final openTasksCount = dashboard?.openTasks ?? tasks.where((t) => t.status != KanbanStatus.completed).length;
    final streak = dashboard?.streakDays ?? user.attendanceStreak;
    final isCheckedIn = dashboard?.isCheckedInToday ?? (todayAttendance != null);

    // Filter tasks
    final filteredTasks = tasks.where((t) {
      if (_selectedFilter == 'Today') return t.status == KanbanStatus.inProgress || t.status == KanbanStatus.todo;
      if (_selectedFilter == 'Upcoming') return t.status == KanbanStatus.todo;
      if (_selectedFilter == 'In Progress') return t.status == KanbanStatus.inProgress;
      if (_selectedFilter == 'Completed') return t.status == KanbanStatus.completed;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(appStateProvider.notifier).fetchDashboard(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Headline
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'You have $openTasksCount tasks for today',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${user.cohortName ?? 'Active Cohort'} • Attendance Streak: 🔥 $streak days',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Segmented Progress Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
              child: SegmentedProgressBar(
                totalSegments: 12,
                completedSegments: dashboard != null && dashboard.assignedTasks > 0
                    ? ((dashboard.completedTasks / dashboard.assignedTasks) * 12).round().clamp(0, 12)
                    : 8,
                percentage: dashboard != null && dashboard.assignedTasks > 0
                    ? (dashboard.completedTasks / dashboard.assignedTasks).clamp(0.0, 1.0)
                    : 0.68,
                activeColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),

            // Primary Signature Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
              child: Column(
                children: [
                  // Yellow Sunshine Card: GPS Check-in Card
                  VibrantCard(
                    backgroundColor: AppColors.cardYellow,
                    badgeText: !isCheckedIn ? '⚡ Attendance Pending' : '✅ Checked In',
                    badgeColor: Colors.black12,
                    title: !isCheckedIn ? 'Verify GPS & Selfie Check-In' : 'Checked In: Geofence Active',
                    subtitle: !isCheckedIn
                        ? 'Camera & Location Required • Tap to Clock In'
                        : 'Hours Worked: ${todayAttendance?.workingHours?.inHours ?? 0}h',
                    metricValue: '🔥 $streak Days',
                    metricLabel: 'Current Streak',
                    avatarUrls: state.projects.isNotEmpty ? state.projects.first.memberAvatars : const [],
                    onArrowTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CheckinCheckoutScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Next Priority Task Highlight
                  if (tasks.isNotEmpty)
                    VibrantCard(
                      backgroundColor: AppColors.cardPurple,
                      badgeText: 'Next Priority Task',
                      title: tasks.first.title,
                      subtitle: '${tasks.first.projectName} • ${tasks.first.timeSlot}',
                      metricValue: tasks.first.priority.toApiValue().toUpperCase(),
                      metricLabel: 'Priority',
                      avatarUrls: tasks.first.assigneeAvatars,
                      onArrowTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TaskDetailScreen(task: tasks.first),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 16),

                  // 2-Column Grid: Standup & Leave balance
                  Row(
                    children: [
                      // Standup Card
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const StandupScreen()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.cardPink,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cardPink.withValues(alpha: 0.3),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('📝', style: TextStyle(fontSize: 22)),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.white24,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.arrow_outward_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Daily Standup',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  state.todayStandup != null ? 'Submitted for Today' : 'Share blockers & mood',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Leave Balance Card
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LeaveDashboardScreen()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.cardBlue,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cardBlue.withValues(alpha: 0.3),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('🏖️', style: TextStyle(fontSize: 22)),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.white24,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.arrow_outward_rounded,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Leave Balance',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${state.leaveBalance.remaining} Days Remaining',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Filter Tabs & Task List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tasks & Deliverables',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        builder: (_) => const CreateTaskBottomSheet(),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                          SizedBox(width: 4),
                          Text(
                            'New Task',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Filter Pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
              child: Row(
                children: ['All', 'Today', 'Upcoming', 'In Progress', 'Completed'].map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedFilter = filter),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.surfaceDark : Colors.white),
                        borderRadius: BorderRadius.circular(AppSpacing.rPill),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? AppColors.borderDark : AppColors.borderLight),
                        ),
                      ),
                      child: Text(
                        filter,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white70 : AppColors.textSecondaryLight),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            // Tasks ListView
            filteredTasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Center(
                      child: Text(
                        'No tasks in this category',
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? AppColors.borderDark : AppColors.borderLight,
                          ),
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                ref.read(appStateProvider.notifier).fetchProjects();
                              },
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: task.status == KanbanStatus.completed
                                      ? AppColors.success
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: task.status == KanbanStatus.completed
                                        ? AppColors.success
                                        : Colors.grey.shade400,
                                    width: 2,
                                  ),
                                ),
                                child: task.status == KanbanStatus.completed
                                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      decoration: task.status == KanbanStatus.completed
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${task.projectName} • Due: ${task.dueDate.toIso8601String().substring(0, 10)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            StatusChip(
                              label: task.status.label,
                              statusType: task.status == KanbanStatus.completed
                                  ? StatusType.success
                                  : StatusType.primary,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
