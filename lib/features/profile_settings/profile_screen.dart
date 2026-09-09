import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/user_360_profile_dialog.dart';
import '../attendance/attendance_home_screen.dart';
import '../attendance/admin_attendance_override_modal.dart';
import '../performance/performance_dashboard_screen.dart';
import '../leaves/leave_dashboard_screen.dart';
import '../leaves/leave_approval_queue_screen.dart';
import '../projects_tasks/projects_list_screen.dart';
import '../directory_cohorts/team_directory_screen.dart';
import '../directory_cohorts/cohort_management_screen.dart';
import '../standup/standup_feed_screen.dart';
import '../activity_audit/activity_log_screen.dart';
import '../activity_audit/recycle_bin_screen.dart';
import '../auth/login_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = state.currentUser;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchCurrentUser(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Bar with Settings Cog
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Profile 👤',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.textPrimaryLight,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 22),
                          tooltip: 'Edit Profile',
                          onPressed: () => _showEditProfileBottomSheet(context, ref, user),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined, size: 22),
                          tooltip: 'Settings',
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // User Info Card
                Row(
                  children: [
                    AppAvatar(
                      url: user.avatarUrl,
                      size: 72,
                      borderColor: AppColors.primary,
                      borderWidth: 2.5,
                      fallbackText: user.name,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${user.roleTitle} • ${user.location}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                            ),
                          ),
                          if (user.bio != null && user.bio!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              user.bio!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 3 Colored Stat Boxes (Strictly tailored to user role)
                if (user.role == UserRole.intern)
                  Row(
                    children: [
                      _buildProfileStatBox('Performance', '⭐ ${user.performanceRating.toStringAsFixed(1)}', const Color(0xFFD1FAE5), isDark),
                      const SizedBox(width: 10),
                      _buildProfileStatBox('Streak', '🔥 ${user.attendanceStreak}d', const Color(0xFFE0F2FE), isDark),
                      const SizedBox(width: 10),
                      _buildProfileStatBox('Coins', '🟡 ${user.streakCoins}', const Color(0xFFFFEDD5), isDark),
                    ],
                  )
                else if (user.role == UserRole.mentor)
                  Row(
                    children: [
                      _buildProfileStatBox('Rating', '⭐ ${user.performanceRating.toStringAsFixed(1)}', const Color(0xFFD1FAE5), isDark),
                      const SizedBox(width: 10),
                      _buildProfileStatBox('Interns', '👥 ${state.allUsers.where((u) => u.role == UserRole.intern).length}', const Color(0xFFE0F2FE), isDark),
                      const SizedBox(width: 10),
                      _buildProfileStatBox('Cohort', '🎓 ${user.cohortName ?? 'Active'}', const Color(0xFFFFEDD5), isDark),
                    ],
                  )
                else
                  Row(
                    children: [
                      _buildProfileStatBox('Role', '🛡️ Admin', const Color(0xFFD1FAE5), isDark),
                      const SizedBox(width: 10),
                      _buildProfileStatBox('Cohorts', '🎓 ${state.cohorts.length} Batches', const Color(0xFFE0F2FE), isDark),
                      const SizedBox(width: 10),
                      _buildProfileStatBox('Users', '👥 ${state.allUsers.length}', const Color(0xFFFFEDD5), isDark),
                    ],
                  ),
                const SizedBox(height: 24),

                // Internship Summary (Interns only)
                if (user.role == UserRole.intern) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
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
                        Text(
                          '🎓 Internship Summary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildSummaryRow('Join Date', user.joiningDate ?? 'Active Session', isDark),
                        _buildSummaryRow('Active Days Tracked', '${state.attendanceRecords.length} Days', isDark),
                        _buildSummaryRow('Completed Tasks', '${user.completedTasks} Tasks', isDark),
                        _buildSummaryRow('Assigned Mentor', user.mentorName ?? 'Senior Mentor', isDark),
                        _buildSummaryRow('Cohort', user.cohortName ?? 'General Cohort', isDark),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // 360 Profile Launch Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => User360ProfileDialog.show(context, userId: user.id, fallbackUser: user),
                    icon: const Icon(Icons.badge_outlined, size: 18),
                    label: const Text('View Full 360° Profile Sheet'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Menu List
                Material(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                    side: BorderSide(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Column(
                    children: _buildRoleSpecificMenuItems(context, state, user, isDark),
                  ),
                ),
                const SizedBox(height: 28),

                // Sign Out Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await ref.read(appStateProvider.notifier).logout();
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      }
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimaryLight,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfileBottomSheet(BuildContext context, WidgetRef ref, UserModel user) {
    final bioCtrl = TextEditingController(text: user.bio ?? '');
    final phoneCtrl = TextEditingController(text: user.phone ?? '');
    final skillsCtrl = TextEditingController(text: user.skills.join(', '));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Edit Profile ✏️',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: bioCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Bio / About You'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: skillsCtrl,
              decoration: const InputDecoration(labelText: 'Skills (comma separated)'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await ref.read(appStateProvider.notifier).updateProfile({
                      'bio': bioCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'skills': skillsCtrl.text.trim(),
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Profile updated successfully!')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to update profile: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save Profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRoleSpecificMenuItems(
    BuildContext context,
    AppState state,
    UserModel user,
    bool isDark,
  ) {
    if (user.role == UserRole.intern) {
      return [
        _buildMenuItem(
          icon: Icons.fingerprint_rounded,
          iconColor: AppColors.primary,
          title: 'Attendance & GPS Log',
          subtitle: '${state.attendanceRecords.length} Verified Check-ins',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AttendanceHomeScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.star_rate_rounded,
          iconColor: Colors.amber,
          title: '360 Performance Reviews',
          subtitle: 'Skills breakdown & mentor feedback',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PerformanceDashboardScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.beach_access_rounded,
          iconColor: AppColors.cardPink,
          title: 'Leave Balances & History',
          subtitle: '${state.leaveBalance.remaining} Days Remaining',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LeaveDashboardScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.assignment_outlined,
          iconColor: AppColors.cardBlue,
          title: 'Sprint Projects & Tasks',
          subtitle: '${user.completedTasks} Tasks completed',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProjectsListScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.tune_rounded,
          iconColor: AppColors.cardGreen,
          title: 'Settings & Security',
          subtitle: 'Biometrics, themes, offline mode',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          isDark: isDark,
        ),
      ];
    } else if (user.role == UserRole.mentor) {
      return [
        _buildMenuItem(
          icon: Icons.people_alt_rounded,
          iconColor: AppColors.primary,
          title: 'Supervised Interns Directory',
          subtitle: 'Review performance & assign tasks',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TeamDirectoryScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.forum_rounded,
          iconColor: AppColors.cardGreen,
          title: 'Daily Standups Feed',
          subtitle: 'Review intern blockers & react',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StandupFeedScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.how_to_reg_rounded,
          iconColor: AppColors.cardPink,
          title: 'Leave Approvals Queue',
          subtitle: '${state.leaveRequests.where((l) => l.isPending).length} Pending requests',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LeaveApprovalQueueScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.star_rate_rounded,
          iconColor: Colors.amber,
          title: '360 Review Evaluations',
          subtitle: 'Score technical & team competency',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PerformanceDashboardScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.tune_rounded,
          iconColor: AppColors.cardBlue,
          title: 'Settings & Security',
          subtitle: 'Biometrics, themes, notifications',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          isDark: isDark,
        ),
      ];
    } else {
      return [
        _buildMenuItem(
          icon: Icons.edit_calendar_rounded,
          iconColor: AppColors.primary,
          title: 'Attendance Overrides',
          subtitle: 'Adjust check-ins & update logs',
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const AdminAttendanceOverrideModal(),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.hub_rounded,
          iconColor: AppColors.cardGreen,
          title: 'Cohort Lifecycle Control',
          subtitle: 'Batch schedules & enrollment',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CohortManagementScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.history_rounded,
          iconColor: AppColors.cardOrange,
          title: 'Enterprise Audit Trail',
          subtitle: 'Real-time security logs & activities',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.delete_outline_rounded,
          iconColor: AppColors.danger,
          title: 'Recycle Bin & Retention',
          subtitle: 'Restore deleted items (30-day purge)',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecycleBinScreen()),
            );
          },
          isDark: isDark,
        ),
        _buildDivider(isDark),
        _buildMenuItem(
          icon: Icons.tune_rounded,
          iconColor: AppColors.cardBlue,
          title: 'Enterprise Settings',
          subtitle: 'Security, privacy & system configs',
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          isDark: isDark,
        ),
      ];
    }
  }

  Widget _buildProfileStatBox(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : color,
          borderRadius: BorderRadius.circular(22),
          border: isDark ? Border.all(color: AppColors.borderDark) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : AppColors.textPrimaryLight,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 64,
      endIndent: 20,
      color: isDark ? AppColors.borderDark : AppColors.borderLight,
    );
  }
}
