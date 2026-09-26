import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:first_app/main.dart';
import 'package:first_app/core/state/app_state_provider.dart';
import 'package:first_app/shared/models/user_model.dart';
import 'package:first_app/features/auth/login_screen.dart';
import 'package:first_app/features/dashboard/main_navigation_wrapper.dart';
import 'package:first_app/features/performance/performance_dashboard_screen.dart';
import 'package:first_app/features/auth/join_invite_screen.dart';
import 'package:first_app/features/attendance/student_attendance_detail_screen.dart';
import 'package:first_app/features/projects_tasks/project_detail_screen.dart';
import 'package:first_app/features/blogs/blog_detail_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Unauthenticated access to protected route redirects to LoginScreen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => MockAppStateNotifier(
          AppState(
            currentUser: const UserModel(
              id: '0',
              name: 'Guest',
              email: '',
              role: UserRole.intern,
            ),
            isAuthenticated: false,
            isSessionLoading: false,
          ),
        )),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const InternHubApp(initialRoute: '/reviews'),
      ),
    );

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PerformanceDashboardScreen), findsNothing);
  });

  testWidgets('Intern hitting /reviews route is blocked and redirected to dashboard', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => MockAppStateNotifier(
          AppState(
            currentUser: const UserModel(
              id: '1',
              name: 'Intern User',
              email: 'intern@test.com',
              role: UserRole.intern,
            ),
            isAuthenticated: true,
            isSessionLoading: false,
          ),
        )),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const InternHubApp(initialRoute: '/reviews'),
      ),
    );

    // GuardedRoute returns MainNavigationWrapper for unauthorized roles
    expect(find.byType(MainNavigationWrapper), findsOneWidget);
    expect(find.byType(PerformanceDashboardScreen), findsNothing);
  });

  testWidgets('Mentor hitting /reviews route resolves PerformanceDashboardScreen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => MockAppStateNotifier(
          AppState(
            currentUser: const UserModel(
              id: '2',
              name: 'Mentor User',
              email: 'mentor@test.com',
              role: UserRole.mentor,
            ),
            isAuthenticated: true,
            isSessionLoading: false,
          ),
        )),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const InternHubApp(initialRoute: '/reviews'),
      ),
    );

    expect(find.byType(PerformanceDashboardScreen), findsOneWidget);
  });

  testWidgets('Dynamic route /join/:token correctly instantiates JoinInviteScreen with token', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: InternHubApp(initialRoute: '/join/invite-token-abc-123'),
      ),
    );

    final joinScreenFinder = find.byType(JoinInviteScreen);
    expect(joinScreenFinder, findsOneWidget);
    final joinWidget = tester.widget<JoinInviteScreen>(joinScreenFinder);
    expect(joinWidget.initialToken, 'invite-token-abc-123');
  });

  testWidgets('Dynamic route /attendance/:userId correctly instantiates StudentAttendanceDetailScreen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => MockAppStateNotifier(
          AppState(
            currentUser: const UserModel(
              id: '3',
              name: 'Admin User',
              email: 'admin@test.com',
              role: UserRole.admin,
            ),
            isAuthenticated: true,
            isSessionLoading: false,
          ),
        )),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const InternHubApp(initialRoute: '/attendance/42'),
      ),
    );

    final detailFinder = find.byType(StudentAttendanceDetailScreen);
    expect(detailFinder, findsOneWidget);
    final detailWidget = tester.widget<StudentAttendanceDetailScreen>(detailFinder);
    expect(detailWidget.userId, 42);
  });

  testWidgets('Dynamic route /projects/:projectId correctly instantiates ProjectDetailScreen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => MockAppStateNotifier(
          AppState(
            currentUser: const UserModel(
              id: '3',
              name: 'Admin User',
              email: 'admin@test.com',
              role: UserRole.admin,
            ),
            isAuthenticated: true,
            isSessionLoading: false,
          ),
        )),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const InternHubApp(initialRoute: '/projects/99'),
      ),
    );

    final detailFinder = find.byType(ProjectDetailScreen);
    expect(detailFinder, findsOneWidget);
    final detailWidget = tester.widget<ProjectDetailScreen>(detailFinder);
    expect(detailWidget.projectId, 99);
  });

  testWidgets('Dynamic route /blogs/:slug correctly instantiates BlogDetailScreen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => MockAppStateNotifier(
          AppState(
            currentUser: const UserModel(
              id: '3',
              name: 'Admin User',
              email: 'admin@test.com',
              role: UserRole.admin,
            ),
            isAuthenticated: true,
            isSessionLoading: false,
          ),
        )),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const InternHubApp(initialRoute: '/blogs/getting-started'),
      ),
    );

    final detailFinder = find.byType(BlogDetailScreen);
    expect(detailFinder, findsOneWidget);
    final detailWidget = tester.widget<BlogDetailScreen>(detailFinder);
    expect(detailWidget.slug, 'getting-started');
  });
}

class MockAppStateNotifier extends AppStateNotifier {
  MockAppStateNotifier(AppState initialState) {
    state = initialState;
  }
}
