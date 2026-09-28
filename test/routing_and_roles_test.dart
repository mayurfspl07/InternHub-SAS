import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:first_app/main.dart';
import 'package:first_app/splash_screen.dart';
import 'package:first_app/core/state/app_state_provider.dart';
import 'package:first_app/shared/models/user_model.dart';
import 'package:first_app/features/auth/login_screen.dart';
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

  testWidgets('Intern hitting /reviews route is blocked with a No access page', (tester) async {
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
    expect(find.text('No access'), findsOneWidget);
    expect(find.text('Go to Home'), findsOneWidget);
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

  testWidgets('Normal launch opens the splash screen', (tester) async {
    await _launchLikeThePhone(tester, '/');
    expect(tester.takeException(), isNull);
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the splash animations
  });

  testWidgets('Invite link launch opens the join screen with its token', (tester) async {
    await _launchLikeThePhone(tester, '/join/invite-token-xyz');
    expect(tester.takeException(), isNull);
    final join = tester.widget<JoinInviteScreen>(find.byType(JoinInviteScreen));
    expect(join.initialToken, 'invite-token-xyz');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Cold start from the full invite URL opens the join screen', (tester) async {
    // Android hands a cold start the whole link, not just the path.
    await _launchLikeThePhone(tester, 'https://internhub-sas-production-b44c.up.railway.app/join/tok-cold-1');
    expect(tester.takeException(), isNull);
    expect(tester.widget<JoinInviteScreen>(find.byType(JoinInviteScreen)).initialToken, 'tok-cold-1');
    await tester.pumpWidget(const SizedBox());
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

/// Starts the app the way the phone does (no fixed initialRoute), optionally from a deep link.
Future<void> _launchLikeThePhone(WidgetTester tester, String platformRoute) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = platformRoute;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final guest = MockAppStateNotifier(AppState(
    currentUser: const UserModel(id: '0', name: 'Guest', email: '', role: UserRole.intern),
    isSessionLoading: false,
  ));
  await tester.pumpWidget(ProviderScope(
    overrides: [appStateProvider.overrideWith((ref) => guest)],
    child: const InternHubApp(),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

class MockAppStateNotifier extends AppStateNotifier {
  MockAppStateNotifier(AppState initialState) {
    state = initialState;
  }
}
