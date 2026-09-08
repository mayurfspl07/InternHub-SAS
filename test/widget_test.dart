import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:first_app/main.dart';

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
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

    await tester.pumpWidget(
      const ProviderScope(
        child: InternHubApp(),
      ),
    );

    // 1. Fast-forward animation & settle transition to Login Screen
    await tester.pumpAndSettle(const Duration(seconds: 6));

    // 2. Select Mentor Role & Sign In
    await tester.tap(find.text('🧑‍🏫 Mentor'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sign In as 🧑‍🏫 Mentor'));
    await tester.tap(find.text('Sign In as 🧑‍🏫 Mentor'));
    await tester.pumpAndSettle();

    // 3. Verify ONLY Mentor Command Center UI is visible
    expect(find.text('Mentor Command Center 🧑‍🏫'), findsOneWidget);
    expect(find.textContaining('Assigned Interns'), findsOneWidget);
    expect(find.text('Daily Standup Submissions'), findsOneWidget);

    // 4. Verify the top role switch banner is NOT present on the screen
    expect(find.text('Active Role:'), findsNothing);

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

    await tester.pumpWidget(
      const ProviderScope(
        child: InternHubApp(),
      ),
    );

    // 1. Settle to Login Screen
    await tester.pumpAndSettle(const Duration(seconds: 6));

    // 2. Sign In as Intern
    await tester.ensureVisible(find.text('Sign In as 🎓 Intern'));
    await tester.tap(find.text('Sign In as 🎓 Intern'));
    await tester.pumpAndSettle();

    // 3. Verify Intern UI is visible
    expect(find.text('Hello, Sarah!'), findsOneWidget);
    expect(find.text('Today\'s Schedule'), findsOneWidget);
    expect(find.textContaining('GPS'), findsWidgets);
    expect(find.textContaining('Standup'), findsWidgets);

    // 4. Verify Mentor/Admin features are NOT present
    expect(find.text('Mentor Command Center 🧑‍🏫'), findsNothing);
    expect(find.text('Enterprise Admin Console 🛡️'), findsNothing);
    expect(find.text('Active Role:'), findsNothing);

    FlutterError.onError = originalOnError;
  });
}
