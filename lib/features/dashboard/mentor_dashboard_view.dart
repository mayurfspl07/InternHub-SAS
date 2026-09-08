import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/vibrant_card.dart';
import '../../shared/widgets/user_360_profile_dialog.dart';
import '../standup/standup_feed_screen.dart';
import '../leaves/leave_approval_queue_screen.dart';
import '../performance/performance_dashboard_screen.dart';

class MentorDashboardView extends ConsumerWidget {
  const MentorDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dashboard = state.mentorDashboard;
    final interns = state.allUsers.where((u) => u.role == UserRole.intern).toList();
    final pendingLeaves = state.leaveRequests.where((l) => l.status.name == 'pending').toList();

    final assignedCount = dashboard?.assignedInternsCount ?? interns.length;
    final presentToday = dashboard?.presentToday ?? 0;
    final activeProjs = dashboard?.activeProjects ?? state.projects.length;

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
                    'Mentor Command Center 🧑‍🏫',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Supervising $assignedCount Active Interns • $activeProjs Sprint Projects',
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

            // Primary Mentor Quick Action Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
              child: Column(
                children: [
                  // Yellow Card: Pending Standups & Reviews
                  VibrantCard(
                    backgroundColor: AppColors.cardYellow,
                    badgeText: '💬 ${state.standups.length} Standups Logged',
                    badgeColor: Colors.black12,
                    title: 'Daily Standup Submissions',
                    subtitle: 'Review blockers, give feedback, and cheer today\'s updates.',
                    metricValue: '${state.standups.length} Updates',
                    metricLabel: 'Awaiting Feedback',
                    avatarUrls: interns.map((i) => i.avatarUrl).whereType<String>().toList(),
                    onArrowTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StandupFeedScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2-Column Grid: Leaves & Performance
                  Row(
                    children: [
                      // Pending Leaves
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const LeaveApprovalQueueScreen()),
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
                                    const Text('⏳', style: TextStyle(fontSize: 22)),
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
                                  'Leave Queue',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${pendingLeaves.length} Pending Approval',
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

                      // Milestone Evaluations
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PerformanceDashboardScreen()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.cardPurple,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cardPurple.withValues(alpha: 0.3),
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
                                    const Text('⭐', style: TextStyle(fontSize: 22)),
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
                                  '360° Reviews',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Performance Scorecard',
                                  style: TextStyle(
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

            // Section: Assigned Interns Today Overview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Assigned Interns Overview',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                  Text(
                    '$presentToday Present Today',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Interns List
            interns.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No interns currently assigned',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                    itemCount: interns.length,
                    itemBuilder: (context, index) {
                      final intern = interns[index];
                      return GestureDetector(
                        onTap: () => User360ProfileDialog.show(context, userId: intern.id, fallbackUser: intern),
                        child: Container(
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
                              AppAvatar(
                                url: intern.avatarUrl,
                                size: 48,
                                borderColor: AppColors.primary,
                                borderWidth: 1.5,
                                fallbackText: intern.name,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      intern.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${intern.roleTitle} • ${intern.department ?? ''}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Text(
                                          '🔥 ${intern.attendanceStreak} Streak',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '⭐ ${intern.performanceRating}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                            ],
                          ),
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
