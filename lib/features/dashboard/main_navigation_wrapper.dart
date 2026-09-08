import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/floating_bottom_nav.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_logo.dart';
import 'intern_dashboard_view.dart';
import 'mentor_dashboard_view.dart';
import 'admin_dashboard_view.dart';
import '../attendance/attendance_home_screen.dart';
import '../projects_tasks/projects_list_screen.dart';
import '../leaves/leave_dashboard_screen.dart';
import '../leaves/leave_approval_queue_screen.dart';
import '../standup/standup_screen.dart';
import '../standup/standup_feed_screen.dart';
import '../announcements/announcements_screen.dart';
import '../notifications/notification_center_screen.dart';
import '../performance/performance_dashboard_screen.dart';
import '../directory_cohorts/cohort_management_screen.dart';
import '../directory_cohorts/team_directory_screen.dart';
import '../directory_cohorts/user_management_screen.dart';
import '../assignments/assignments_screen.dart';
import '../invites/invite_links_screen.dart';
import '../activity_audit/activity_log_screen.dart';
import '../activity_audit/recycle_bin_screen.dart';
import '../admin_ops/data_management_screen.dart';
import '../profile_settings/profile_screen.dart';
import '../auth/login_screen.dart';

class MainNavigationWrapper extends ConsumerStatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  ConsumerState<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends ConsumerState<MainNavigationWrapper> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentTabIndex = 0;

  List<NavItem> _getNavItemsForRole(UserRole role) {
    switch (role) {
      case UserRole.intern:
        return const [
          NavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: 'Dashboard'),
          NavItem(icon: Icons.fingerprint_rounded, selectedIcon: Icons.fingerprint_rounded, label: 'Attendance'),
          NavItem(icon: Icons.folder_outlined, selectedIcon: Icons.folder_rounded, label: 'Projects'),
          NavItem(icon: Icons.beach_access_outlined, selectedIcon: Icons.beach_access_rounded, label: 'Leave'),
          NavItem(icon: Icons.chat_bubble_outline_rounded, selectedIcon: Icons.chat_bubble_rounded, label: 'Standup'),
        ];
      case UserRole.mentor:
      case UserRole.admin:
      case UserRole.superadmin:
        return const [
          NavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: 'Dashboard'),
          NavItem(icon: Icons.fingerprint_rounded, selectedIcon: Icons.fingerprint_rounded, label: 'Attendance'),
          NavItem(icon: Icons.folder_outlined, selectedIcon: Icons.folder_rounded, label: 'Projects'),
          NavItem(icon: Icons.how_to_reg_outlined, selectedIcon: Icons.how_to_reg_rounded, label: 'Leave'),
          NavItem(icon: Icons.campaign_outlined, selectedIcon: Icons.campaign_rounded, label: 'Notices'),
        ];
    }
  }

  List<Widget> _getScreensForRole(UserRole role) {
    switch (role) {
      case UserRole.intern:
        return const [
          InternDashboardView(),
          AttendanceHomeScreen(),
          ProjectsListScreen(),
          LeaveDashboardScreen(),
          StandupScreen(),
        ];
      case UserRole.mentor:
        return const [
          MentorDashboardView(),
          AttendanceHomeScreen(),
          ProjectsListScreen(),
          LeaveApprovalQueueScreen(),
          AnnouncementsScreen(),
        ];
      case UserRole.admin:
      case UserRole.superadmin:
        return const [
          AdminDashboardView(),
          AttendanceHomeScreen(),
          ProjectsListScreen(),
          LeaveApprovalQueueScreen(),
          AnnouncementsScreen(),
        ];
    }
  }

  Widget _buildRoleAwareDrawer(BuildContext context, UserModel user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final role = user.role;

    return Drawer(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo.horizontal(height: 26),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      AppAvatar(url: user.avatarUrl, size: 48, fallbackText: user.name),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.name, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(
                              user.roleTitle,
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : AppColors.textSecondaryLight),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Drawer Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (role == UserRole.intern) ...[
                    _drawerTile(Icons.assignment_outlined, 'Assignments', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AssignmentsScreen()));
                    }),
                    _drawerTile(Icons.campaign_outlined, 'Announcements', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementsScreen()));
                    }),
                    _drawerTile(Icons.stars_outlined, 'Performance Reviews', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PerformanceDashboardScreen()));
                    }),
                    _drawerTile(Icons.notifications_outlined, 'Notification Center', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen()));
                    }),
                    _drawerTile(Icons.person_outline_rounded, 'My Profile', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                    }),
                  ] else if (role == UserRole.mentor) ...[
                    _drawerTile(Icons.people_alt_outlined, 'My Interns', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                    }),
                    _drawerTile(Icons.assignment_outlined, 'Intern Assignments', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AssignmentsScreen()));
                    }),
                    _drawerTile(Icons.link_rounded, 'Invite Links', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const InviteLinksScreen()));
                    }),
                    _drawerTile(Icons.hub_outlined, 'Cohorts', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CohortManagementScreen()));
                    }),
                    _drawerTile(Icons.forum_outlined, 'Standup Feed', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const StandupFeedScreen()));
                    }),
                    _drawerTile(Icons.stars_outlined, 'Reviews', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PerformanceDashboardScreen()));
                    }),
                    _drawerTile(Icons.history_rounded, 'Activity Trail', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityLogScreen()));
                    }),
                    _drawerTile(Icons.notifications_outlined, 'Notifications', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen()));
                    }),
                    _drawerTile(Icons.person_outline_rounded, 'Profile', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                    }),
                  ] else ...[
                    _drawerTile(Icons.people_outline_rounded, 'User Directory', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                    }),
                    _drawerTile(Icons.group_outlined, 'Team Directory', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamDirectoryScreen()));
                    }),
                    _drawerTile(Icons.link_rounded, 'Invite Links & Signups', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const InviteLinksScreen()));
                    }),
                    _drawerTile(Icons.assignment_outlined, 'Intern Assignments', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AssignmentsScreen()));
                    }),
                    _drawerTile(Icons.hub_outlined, 'Cohorts', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const CohortManagementScreen()));
                    }),
                    _drawerTile(Icons.stars_outlined, 'Performance Reviews', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const PerformanceDashboardScreen()));
                    }),
                    _drawerTile(Icons.history_rounded, 'Activity Audit Trail', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivityLogScreen()));
                    }),
                    _drawerTile(Icons.delete_outline_rounded, 'Recycle Bin', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RecycleBinScreen()));
                    }),
                    _drawerTile(Icons.dangerous_outlined, 'Danger Zone (Data)', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const DataManagementScreen()));
                    }, isDestructive: true),
                    _drawerTile(Icons.notifications_outlined, 'Notifications', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen()));
                    }),
                    _drawerTile(Icons.person_outline_rounded, 'Profile', () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                    }),
                  ],
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
                title: const Text('Log Out', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmLogout(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, size: 22, color: isDestructive ? AppColors.danger : null),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDestructive ? AppColors.danger : null,
        ),
      ),
      onTap: onTap,
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of InternHub?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(appStateProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final navItems = _getNavItemsForRole(user.role);
    final screens = _getScreensForRole(user.role);

    final activeIndex = _currentTabIndex.clamp(0, screens.length - 1);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildRoleAwareDrawer(context, user),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                // Top Custom Header
                CustomAppBar(
                  onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                  onNotificationTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
                    );
                  },
                ),

                // Main Role-Specific Body
                Expanded(
                  child: IndexedStack(
                    index: activeIndex,
                    children: screens,
                  ),
                ),
              ],
            ),

            // Role-Specific Floating Bottom Navigation Bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: FloatingBottomNav(
                currentIndex: activeIndex,
                onTap: (index) => setState(() => _currentTabIndex = index),
                items: navItems,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
