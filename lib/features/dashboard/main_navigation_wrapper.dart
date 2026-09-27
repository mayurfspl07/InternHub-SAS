import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/floating_bottom_nav.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/logout_confirm_dialog.dart';
import 'intern_dashboard_view.dart';
import 'mentor_dashboard_view.dart';
import 'admin_dashboard_view.dart';
import 'widgets/quick_action_sheet.dart';
import '../attendance/attendance_home_screen.dart';
import '../projects_tasks/projects_list_screen.dart';
import '../leaves/leave_dashboard_screen.dart';
import '../leaves/leave_approval_queue_screen.dart';

class MainNavigationWrapper extends ConsumerStatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  ConsumerState<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends ConsumerState<MainNavigationWrapper> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep the notification badge current when the app comes back to the foreground.
    if (state == AppLifecycleState.resumed) {
      ref.read(appStateProvider.notifier).fetchUnreadCount();
    }
  }

  // Standup (intern) and Notices (mentor/admin) live in the center "+" sheet and the drawer.
  List<NavItem> _getNavItemsForRole(UserRole role) {
    switch (role) {
      case UserRole.intern:
        return const [
          NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
          NavItem(icon: Icons.fingerprint_rounded, selectedIcon: Icons.fingerprint_rounded, label: 'Attendance'),
          NavItem(icon: Icons.folder_outlined, selectedIcon: Icons.folder_rounded, label: 'Projects'),
          NavItem(icon: Icons.beach_access_outlined, selectedIcon: Icons.beach_access_rounded, label: 'Leave'),
        ];
      case UserRole.mentor:
      case UserRole.admin:
      case UserRole.superadmin:
        return const [
          NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
          NavItem(icon: Icons.fingerprint_rounded, selectedIcon: Icons.fingerprint_rounded, label: 'Attendance'),
          NavItem(icon: Icons.folder_outlined, selectedIcon: Icons.folder_rounded, label: 'Projects'),
          NavItem(icon: Icons.how_to_reg_outlined, selectedIcon: Icons.how_to_reg_rounded, label: 'Approvals'),
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
        ];
      case UserRole.mentor:
        return const [
          MentorDashboardView(),
          AttendanceHomeScreen(),
          ProjectsListScreen(),
          LeaveApprovalQueueScreen(),
        ];
      case UserRole.admin:
      case UserRole.superadmin:
        return const [
          AdminDashboardView(),
          AttendanceHomeScreen(),
          ProjectsListScreen(),
          LeaveApprovalQueueScreen(),
        ];
    }
  }

  void _go(String route) {
    Navigator.pop(context);
    Navigator.pushNamed(context, route);
  }

  Widget _buildRoleAwareDrawer(BuildContext context, UserModel user) {
    final role = user.role;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo.horizontal(height: 26),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.rTile),
                    ),
                    child: Row(
                      children: [
                        AppAvatar(url: user.avatarUrl, size: 44, fallbackText: user.name),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.cardTitle),
                              const SizedBox(height: 2),
                              Text(user.roleTitle, style: AppTypography.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  if (role == UserRole.intern) ...[
                    _drawerTile(Icons.chat_bubble_outline_rounded, 'Standup', () => _go('/standup')),
                    _drawerTile(Icons.assignment_outlined, 'Assignments', () => _go('/intern-assignments')),
                    _drawerTile(Icons.campaign_outlined, 'Announcements', () => _go('/announcements')),
                    _drawerTile(Icons.article_outlined, 'Blogs', () => _go('/blogs')),
                    _drawerTile(Icons.notifications_outlined, 'Notification Center', () => _go('/notifications')),
                    _drawerTile(Icons.person_outline_rounded, 'My Profile', () => _go('/profile')),
                  ] else if (role == UserRole.mentor) ...[
                    _drawerTile(Icons.people_alt_outlined, 'My Interns', () => _go('/admin')),
                    _drawerTile(Icons.campaign_outlined, 'Announcements', () => _go('/announcements')),
                    _drawerTile(Icons.assignment_outlined, 'Intern Assignments', () => _go('/intern-assignments')),
                    _drawerTile(Icons.link_rounded, 'Invite Links', () => _go('/invite-links')),
                    _drawerTile(Icons.chat_bubble_outline_rounded, 'Standup', () => _go('/standup')),
                    _drawerTile(Icons.stars_outlined, 'Reviews', () => _go('/reviews')),
                    _drawerTile(Icons.hub_outlined, 'Cohorts', () => _go('/cohorts')),
                    _drawerTile(Icons.article_outlined, 'Blogs', () => _go('/blogs')),
                    _drawerTile(Icons.insights_rounded, 'Activity', () => _go('/activity')),
                    _drawerTile(Icons.notifications_outlined, 'Notifications', () => _go('/notifications')),
                    _drawerTile(Icons.person_outline_rounded, 'Profile', () => _go('/profile')),
                  ] else ...[
                    _drawerTile(Icons.people_outline_rounded, 'User Directory', () => _go('/admin')),
                    _drawerTile(Icons.group_outlined, 'Team Directory', () => _go('/team')),
                    _drawerTile(Icons.campaign_outlined, 'Announcements', () => _go('/announcements')),
                    _drawerTile(Icons.link_rounded, 'Invite Links & Signups', () => _go('/invite-links')),
                    _drawerTile(Icons.assignment_outlined, 'Intern Assignments', () => _go('/intern-assignments')),
                    _drawerTile(Icons.chat_bubble_outline_rounded, 'Standup', () => _go('/standup')),
                    _drawerTile(Icons.stars_outlined, 'Performance Reviews', () => _go('/reviews')),
                    _drawerTile(Icons.hub_outlined, 'Cohorts', () => _go('/cohorts')),
                    _drawerTile(Icons.article_outlined, 'Blogs', () => _go('/blogs')),
                    _drawerTile(Icons.insights_rounded, 'Activity', () => _go('/activity')),
                    _drawerTile(Icons.delete_outline_rounded, 'Recycle Bin', () => _go('/bin')),
                    if (user.isPlatformAdmin)
                      _drawerTile(Icons.dangerous_outlined, 'Danger Zone (Data)', () => _go('/data'), isDestructive: true),
                    if (role == UserRole.admin) ...[
                      _drawerSectionHeader('MASTERS'),
                      _drawerTile(Icons.checklist_rounded, 'Task Status', () => _go('/task-statuses')),
                      _drawerTile(Icons.layers_outlined, 'Project Status', () => _go('/project-statuses')),
                      _drawerTile(Icons.access_time_rounded, 'Duration', () => _go('/internship-durations')),
                      _drawerSectionHeader('SETTINGS'),
                      _drawerTile(Icons.business_rounded, 'Organization', () => _go('/org-settings')),
                      _drawerTile(Icons.mark_email_read_outlined, 'Mail Configuration', () => _go('/admin/settings/mail')),
                    ],
                    _drawerSectionHeader('ACCOUNT'),
                    _drawerTile(Icons.notifications_outlined, 'Notifications', () => _go('/notifications')),
                    _drawerTile(Icons.person_outline_rounded, 'Profile', () => _go('/profile')),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
              child: _drawerTile(Icons.logout_rounded, 'Log out', () {
                Navigator.pop(context);
                showLogoutConfirmDialog(context, ref);
              }, isDestructive: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 20, 6),
      child: Text(title, style: AppTypography.label.copyWith(color: AppColors.textTertiary, letterSpacing: 1.2)),
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    final color = isDestructive ? AppColors.danger : AppColors.ink;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDestructive ? AppColors.dangerSoft : AppColors.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        title: Text(title, style: AppTypography.bodyStrong.copyWith(color: color)),
        onTap: onTap,
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
        child: Column(
          children: [
            CustomAppBar(
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onNotificationTap: () {
                Navigator.of(context).pushNamed('/notifications');
              },
            ),
            Expanded(
              child: IndexedStack(
                index: activeIndex,
                children: screens,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FloatingBottomNav(
        currentIndex: activeIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        items: navItems,
        onCenterTap: () => QuickActionSheet.show(
          context,
          ref: ref,
          role: user.role,
          onSelectTab: (index) => setState(() => _currentTabIndex = index),
        ),
      ),
    );
  }
}
