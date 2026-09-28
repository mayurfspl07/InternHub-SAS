import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/custom_app_bar.dart';
import '../../shared/widgets/floating_bottom_nav.dart';
import 'intern_dashboard_view.dart';
import 'mentor_dashboard_view.dart';
import 'admin_dashboard_view.dart';
import 'more_screen.dart';
import '../attendance/attendance_home_screen.dart';
import '../projects_tasks/projects_list_screen.dart';
import '../leaves/leave_dashboard_screen.dart';
import '../leaves/leave_approval_queue_screen.dart';

/// Bottom-tab indexes, the same for every role.
class MainTab {
  static const home = 0;
  static const attendance = 1;
  static const projects = 2;
  static const leave = 3;
  static const more = 4;
}

/// The selected bottom tab. Screens inside the shell switch tabs with
/// `ref.read(mainTabProvider.notifier).state = MainTab.leave` instead of pushing a second copy.
final mainTabProvider = StateProvider<int>((ref) => MainTab.home);

class MainNavigationWrapper extends ConsumerStatefulWidget {
  const MainNavigationWrapper({super.key});

  @override
  ConsumerState<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends ConsumerState<MainNavigationWrapper> with WidgetsBindingObserver {
  // Tabs are built the first time they are opened, then kept alive.
  final Set<int> _visited = {MainTab.home};
  final List<ScrollController> _scrollControllers = List.generate(5, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A fresh shell (e.g. after signing in again) always opens on Home.
    Future.microtask(() => ref.read(mainTabProvider.notifier).state = MainTab.home);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in _scrollControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep the notification badge current when the app comes back to the foreground.
    if (state == AppLifecycleState.resumed) {
      ref.read(appStateProvider.notifier).fetchUnreadCount();
    }
  }

  // Everything that isn't one of these tabs is listed on the More tab.
  List<NavItem> _getNavItemsForRole(UserRole role) {
    final leave = role == UserRole.intern
        ? const NavItem(icon: Icons.beach_access_outlined, selectedIcon: Icons.beach_access_rounded, label: 'Leave')
        : const NavItem(icon: Icons.how_to_reg_outlined, selectedIcon: Icons.how_to_reg_rounded, label: 'Approvals');
    return [
      const NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
      const NavItem(icon: Icons.fingerprint_rounded, selectedIcon: Icons.fingerprint_rounded, label: 'Attendance'),
      const NavItem(icon: Icons.folder_outlined, selectedIcon: Icons.folder_rounded, label: 'Projects'),
      leave,
      const NavItem(icon: Icons.grid_view_outlined, selectedIcon: Icons.grid_view_rounded, label: 'More'),
    ];
  }

  Widget _screen(UserRole role, int index) {
    switch (index) {
      case MainTab.home:
        return switch (role) {
          UserRole.intern => const InternDashboardView(),
          UserRole.mentor => const MentorDashboardView(),
          _ => const AdminDashboardView(),
        };
      case MainTab.attendance:
        return const AttendanceHomeScreen();
      case MainTab.projects:
        return const ProjectsListScreen();
      case MainTab.leave:
        return role == UserRole.intern ? const LeaveDashboardScreen() : const LeaveApprovalQueueScreen();
      default:
        return const MoreScreen();
    }
  }

  void _selectTab(int index) {
    final current = ref.read(mainTabProvider);
    if (index == current) {
      // Tapping the open tab again scrolls it back to the top.
      for (final position in _scrollControllers[index].positions.toList()) {
        position.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      return;
    }
    ref.read(mainTabProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final navItems = _getNavItemsForRole(user.role);
    final activeIndex = ref.watch(mainTabProvider).clamp(0, navItems.length - 1);
    _visited.add(activeIndex);

    return PopScope(
      // Android back from another tab returns Home before leaving the app.
      canPop: activeIndex == MainTab.home,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(mainTabProvider.notifier).state = MainTab.home;
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Greeting, search, notifications and profile live on Home; the other tabs have their own titles.
              if (activeIndex == MainTab.home)
                CustomAppBar(onNotificationTap: () => Navigator.of(context).pushNamed('/notifications')),
              Expanded(
                child: IndexedStack(
                  index: activeIndex,
                  children: [
                    for (int i = 0; i < navItems.length; i++)
                      _visited.contains(i)
                          ? TickerMode(
                              enabled: i == activeIndex,
                              child: PrimaryScrollController(
                                controller: _scrollControllers[i],
                                child: _screen(user.role, i),
                              ),
                            )
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: FloatingBottomNav(
          currentIndex: activeIndex,
          onTap: _selectTab,
          items: navItems,
        ),
      ),
    );
  }
}
