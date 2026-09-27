import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/theme/app_theme.dart';
import 'core/state/app_state_provider.dart';
import 'shared/models/user_model.dart';
import 'shared/models/project_model.dart';
import 'shared/models/attendance_model.dart';
import 'splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/auth/join_invite_screen.dart';
import 'features/dashboard/main_navigation_wrapper.dart';
import 'features/attendance/attendance_home_screen.dart';
import 'features/attendance/student_attendance_detail_screen.dart';
import 'features/projects_tasks/projects_list_screen.dart';
import 'features/projects_tasks/project_detail_screen.dart';
import 'features/blogs/blogs_list_screen.dart';
import 'features/blogs/blog_detail_screen.dart';
import 'features/leaves/leave_dashboard_screen.dart';
import 'features/announcements/announcements_screen.dart';
import 'features/standup/standup_screen.dart';
import 'features/assignments/assignments_screen.dart';
import 'features/performance/performance_dashboard_screen.dart';
import 'features/directory_cohorts/cohort_management_screen.dart';
import 'features/directory_cohorts/user_management_screen.dart';
import 'features/directory_cohorts/team_directory_screen.dart';
import 'features/invites/invite_links_screen.dart';
import 'features/admin_ops/data_management_screen.dart';
import 'features/org_settings/org_settings_screen.dart';
import 'features/activity_audit/activity_timeline_screen.dart';
import 'features/activity_audit/recycle_bin_screen.dart';
import 'features/masters/task_statuses_screen.dart';
import 'features/masters/project_statuses_screen.dart';
import 'features/masters/internship_durations_screen.dart';
import 'features/mail_settings/mail_configuration_screen.dart';
import 'features/profile_settings/profile_screen.dart';
import 'features/notifications/notification_center_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Figtree ships in assets/google_fonts; never download fonts at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(AppTheme.systemOverlay);
  runApp(
    const ProviderScope(
      child: InternHubApp(),
    ),
  );
}

class InternHubApp extends ConsumerWidget {
  final String? initialRoute;
  const InternHubApp({super.key, this.initialRoute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'InternHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: initialRoute,
      home: initialRoute == null ? const SplashScreen() : null,
      routes: {
        // Public / Auth
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/join': (_) => const JoinInviteScreen(),

        // Tenant Core
        '/dashboard': (_) => const GuardedRoute(child: MainNavigationWrapper()),
        '/attendance': (_) => const GuardedRoute(child: AttendanceHomeScreen()),
        '/projects': (_) => const GuardedRoute(child: ProjectsListScreen()),
        '/blogs': (_) => const GuardedRoute(child: BlogsListScreen()),
        '/leave': (_) => const GuardedRoute(child: LeaveDashboardScreen()),
        '/announcements': (_) => const GuardedRoute(child: AnnouncementsScreen(showBackButton: true)),
        '/standup': (_) => const GuardedRoute(child: StandupScreen()),
        '/intern-assignments': (_) => const GuardedRoute(child: AssignmentsScreen(showBackButton: true)),
        '/reviews': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin, UserRole.mentor],
              child: PerformanceDashboardScreen(showBackButton: true),
            ),
        '/cohorts': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin, UserRole.mentor],
              child: CohortManagementScreen(showBackButton: true),
            ),
        '/activity': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin, UserRole.mentor],
              child: ActivityTimelineScreen(showBackButton: true),
            ),

        // Tenant Management
        '/admin': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin, UserRole.mentor],
              child: UserManagementScreen(),
            ),
        '/invite-links': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin, UserRole.mentor],
              child: InviteLinksScreen(),
            ),
        '/org-settings': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: OrgSettingsScreen(),
            ),
        '/team': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: TeamDirectoryScreen(),
            ),
        // Wipes every organization's data: the API allows platform admins only.
        '/data': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              platformAdminOnly: true,
              child: DataManagementScreen(),
            ),
        '/bin': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: RecycleBinScreen(),
            ),

        // Masters (Admin only)
        '/task-statuses': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: TaskStatusesScreen(),
            ),
        '/project-statuses': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: ProjectStatusesScreen(),
            ),
        '/admin/project-statuses': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: ProjectStatusesScreen(),
            ),
        '/internship-durations': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: InternshipDurationsScreen(),
            ),
        '/admin/internship-durations': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: InternshipDurationsScreen(),
            ),

        // Settings (Admin only)
        '/admin/settings/mail': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: MailConfigurationScreen(),
            ),
        '/settings/mail': (_) => const GuardedRoute(
              allowedRoles: [UserRole.admin],
              child: MailConfigurationScreen(),
            ),

        // Account & Notification
        '/profile': (_) => const GuardedRoute(child: ProfileScreen(showBackButton: true)),
        '/notifications': (_) => const GuardedRoute(child: NotificationCenterScreen()),
      },
      onGenerateRoute: (settings) {
        final name = settings.name;
        if (name == null || name.isEmpty) return null;

        // Dynamic 1: /join/:token (Public)
        if (name.startsWith('/join/')) {
          final token = name.substring('/join/'.length);
          return MaterialPageRoute(
            builder: (_) => JoinInviteScreen(initialToken: token),
            settings: settings,
          );
        }

        // Dynamic 2: /attendance/:userId
        final attendanceMatch = RegExp(r'^/attendance/(\d+)$').firstMatch(name);
        if (attendanceMatch != null) {
          final userId = int.tryParse(attendanceMatch.group(1)!) ?? 0;
          final student = settings.arguments as AdminStudent?;
          return MaterialPageRoute(
            builder: (_) => GuardedRoute(
              child: StudentAttendanceDetailScreen(
                userId: userId,
                initialStudent: student,
              ),
            ),
            settings: settings,
          );
        }

        // Dynamic 3: /projects/:projectId
        final projectMatch = RegExp(r'^/projects/(\d+)$').firstMatch(name);
        if (projectMatch != null) {
          final projectId = int.tryParse(projectMatch.group(1)!) ?? 0;
          final project = settings.arguments as ProjectModel?;
          return MaterialPageRoute(
            builder: (_) => GuardedRoute(
              child: ProjectDetailScreen(
                projectId: projectId,
                project: project,
              ),
            ),
            settings: settings,
          );
        }

        // Dynamic 4: /blogs/:slug
        if (name.startsWith('/blogs/')) {
          final slug = name.substring('/blogs/'.length);
          return MaterialPageRoute(
            builder: (_) => GuardedRoute(
              child: BlogDetailScreen(slug: slug),
            ),
            settings: settings,
          );
        }

        // Unknown route fallback -> Dashboard or Login
        return MaterialPageRoute(
          builder: (_) => const GuardedRoute(child: MainNavigationWrapper()),
          settings: settings,
        );
      },
    );
  }
}

/// Authentication & Role-Gate Guard
class GuardedRoute extends ConsumerWidget {
  final Widget child;
  final List<UserRole>? allowedRoles;
  final bool platformAdminOnly;

  const GuardedRoute({
    super.key,
    required this.child,
    this.allowedRoles,
    this.platformAdminOnly = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    if (!state.isAuthenticated) {
      // While the stored session is being checked, don't flash the login screen.
      if (state.isSessionLoading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return const LoginScreen();
    }
    final roles = allowedRoles;
    if (roles != null && !roles.contains(state.currentUser.role)) {
      // Role restricted -> Redirect to dashboard
      return const MainNavigationWrapper();
    }
    if (platformAdminOnly && !state.currentUser.isPlatformAdmin) {
      return const MainNavigationWrapper();
    }
    return child;
  }
}
