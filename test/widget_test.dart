import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:first_app/main.dart';
import 'package:first_app/core/state/app_state_provider.dart';
import 'package:first_app/shared/models/user_model.dart';
import 'package:first_app/features/dashboard/mentor_dashboard_view.dart';
import 'package:first_app/features/dashboard/intern_dashboard_view.dart';
import 'package:first_app/features/dashboard/admin_dashboard_view.dart';

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

class MockAppStateNotifier extends AppStateNotifier {
  MockAppStateNotifier(AppState initialState) {
    state = initialState;
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  testWidgets('Strict Role-Based UI: Login as Mentor shows ONLY Mentor UI',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception is NetworkImageLoadException ||
          details.exception.toString().contains('HTTP request failed')) {
        return;
      }
      originalOnError?.call(details);
    };

    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => MockAppStateNotifier(
          AppState(
            currentUser: const UserModel(
              id: '2',
              name: 'Dr. John Mentor',
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
        child: const InternHubApp(initialRoute: '/dashboard'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify ONLY Mentor Command Center / View is visible
    expect(find.byType(MentorDashboardView), findsOneWidget);
    expect(find.byType(InternDashboardView), findsNothing);
    expect(find.byType(AdminDashboardView), findsNothing);
    // 4th tab is the leave approval queue; everything else is on the More tab (no drawer)
    expect(find.byIcon(Icons.how_to_reg_outlined), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Invite links'), findsOneWidget);
    expect(find.text('My interns'), findsOneWidget);
    expect(find.text('Organization settings'), findsNothing); // admin only

    FlutterError.onError = originalOnError;
  });

  testWidgets('Strict Role-Based UI: Login as Intern shows ONLY Intern UI',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception is NetworkImageLoadException ||
          details.exception.toString().contains('HTTP request failed')) {
        return;
      }
      originalOnError?.call(details);
    };

    final container = ProviderContainer(
      overrides: [
        appStateProvider.overrideWith((ref) => MockAppStateNotifier(
          AppState(
            currentUser: const UserModel(
              id: '1',
              name: 'Sarah',
              email: 'sarah@test.com',
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
        child: const InternHubApp(initialRoute: '/dashboard'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Verify Intern UI is visible
    expect(find.byType(InternDashboardView), findsOneWidget);
    expect(find.byType(MentorDashboardView), findsNothing);
    expect(find.byType(AdminDashboardView), findsNothing);
    // 4th tab is the intern's own leave; everything else is on the More tab (no drawer)
    expect(find.byIcon(Icons.beach_access_outlined), findsOneWidget);
    expect(find.byType(Drawer), findsNothing);

    await tester.tap(find.text('More'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Assignments'), findsOneWidget);
    expect(find.text('Invite links'), findsNothing); // staff only

    FlutterError.onError = originalOnError;
  });
}


