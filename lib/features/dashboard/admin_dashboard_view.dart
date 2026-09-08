import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/vibrant_card.dart';
import '../directory_cohorts/cohort_management_screen.dart';
import '../directory_cohorts/user_management_screen.dart';
import '../activity_audit/activity_log_screen.dart';
import '../activity_audit/recycle_bin_screen.dart';
import '../attendance/admin_attendance_override_modal.dart';

class AdminDashboardView extends ConsumerWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dashboard = state.adminDashboard;

    final totalUsers = dashboard?.totalUsers ?? state.allUsers.length;
    final totalCohorts = dashboard?.activeCohorts ?? state.cohorts.length;
    final totalProjects = dashboard?.activeProjects ?? state.projects.length;
    final attRate = dashboard?.averageAttendanceRate ?? 96.8;

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
                    'Enterprise Admin Console 🛡️',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Organization Health • $totalUsers Users • $totalCohorts Cohorts • $totalProjects Projects',
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

            // Primary Admin Stats Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
              child: Column(
                children: [
                  // Yellow Card: Attendance Override & Summary
                  VibrantCard(
                    backgroundColor: AppColors.cardYellow,
                    badgeText: '🛡️ Operations Overview',
                    badgeColor: Colors.black12,
                    title: 'Attendance Health & Records',
                    subtitle: 'Audit attendance logs, inspect student timelines, and export XLSX reports.',
                    metricValue: '${attRate.toStringAsFixed(1)}%',
                    metricLabel: 'Org Attendance Rate',
                    avatarUrls: state.allUsers.map((u) => u.avatarUrl).whereType<String>().toList(),
                    onArrowTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        builder: (_) => const AdminAttendanceOverrideModal(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2-Column Stats Blocks
                  Row(
                    children: [
                      // User Directory
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const UserManagementScreen()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.cardGreen,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.cardGreen.withValues(alpha: 0.3),
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
                                    const Text('👥', style: TextStyle(fontSize: 22)),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.white24,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.arrow_outward_rounded, size: 16, color: Colors.white),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '$totalUsers Users',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                const Text('Manage Directory', style: TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Cohort Management
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const CohortManagementScreen()),
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
                                    const Text('🎯', style: TextStyle(fontSize: 22)),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.white24,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.arrow_outward_rounded, size: 16, color: Colors.white),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '$totalCohorts Batches',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                const Text('Active Cohorts', style: TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2-Column: Activity Log & Recycle Bin
                  Row(
                    children: [
                      // Activity Trail
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
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
                                    const Text('📜', style: TextStyle(fontSize: 22)),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.white24,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.arrow_outward_rounded, size: 16, color: Colors.white),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                const Text('Audit Trail', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                                const SizedBox(height: 4),
                                const Text('Realtime Activity', style: TextStyle(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Recycle Bin
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('🗑️', style: TextStyle(fontSize: 22)),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white12 : Colors.black12,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.arrow_outward_rounded, size: 16, color: isDark ? Colors.white : Colors.black),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Recycle Bin',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${state.recycleBin.length} items',
                                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : AppColors.textSecondaryLight),
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
          ],
        ),
      ),
    );
  }
}
