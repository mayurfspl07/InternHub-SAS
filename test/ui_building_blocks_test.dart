import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:first_app/core/state/app_state_provider.dart';
import 'package:first_app/core/utils/formatters.dart';
import 'package:first_app/features/blogs/widgets/safe_html_view.dart';
import 'package:first_app/features/directory_cohorts/widgets/intern_terms_section.dart';
import 'package:first_app/features/masters/task_statuses_screen.dart';
import 'package:first_app/features/masters/widgets/master_list_scaffold.dart';
import 'package:first_app/shared/models/cohort_model.dart';
import 'package:first_app/shared/models/user_model.dart';
import 'package:first_app/shared/widgets/pagination_bar.dart';
import 'package:first_app/shared/widgets/status_chip.dart';

/// Pumps [child] in a phone-sized (360 px wide) app.
Future<void> pumpAt360(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

class _TestNotifier extends AppStateNotifier {
  _TestNotifier(AppState initial) {
    state = initial;
  }

  AppState get current => state;
}

void main() {
  group('formatters', () {
    test('dates, times and ranges read naturally', () {
      expect(formatDate('2026-09-27'), '27 Sep 2026');
      expect(formatDate('2026-09-27', withYear: false), '27 Sep');
      expect(formatDate(null, fallback: '—'), '—');
      expect(formatTime('09:05'), '9:05 AM');
      expect(formatTime('17:30:00'), '5:30 PM');
      expect(formatDateRange('2026-09-27', '2026-09-30'), '27–30 Sep 2026');
      expect(formatDateRange('2026-09-27', '2026-09-27'), '27 Sep 2026');
    });

    test('plural and humanize', () {
      expect(plural(1, 'day'), '1 day');
      expect(plural(3, 'day'), '3 days');
      expect(plural(2, 'person', 'people'), '2 people');
      expect(humanize('in_progress'), 'In progress');
      expect(humanize('HALF_DAY'), 'Half day');
      expect(humanize(null), '');
    });

    test('hours drop a trailing .0', () {
      expect(formatHours(8), '8h');
      expect(formatHours(7.5), '7.5h');
    });
  });

  group('StatusChip.fromString', () {
    test('uses one sentence-case label per status', () {
      expect(StatusChip.fromString('in_progress').label, 'In progress');
      expect(StatusChip.fromString('IN_PROGRESS').label, 'In progress');
      expect(StatusChip.fromString('half-day').label, 'Half day');
      expect(StatusChip.fromString('something_new').label, 'Something new');
      expect(StatusChip.fromString('').label, 'Unknown');
    });

    test('colors follow meaning, not position', () {
      expect(StatusChip.fromString('approved').statusType, StatusType.success);
      expect(StatusChip.fromString('submitted').statusType, StatusType.info);
      expect(StatusChip.fromString('pending').statusType, StatusType.warning);
      expect(StatusChip.fromString('rejected').statusType, StatusType.danger);
      expect(StatusChip.fromString('whatever').statusType, StatusType.neutral);
    });
  });

  group('PaginationBar', () {
    testWidgets('fits a 360 px phone and pages forward and back', (tester) async {
      final pages = <int>[];
      await pumpAt360(
        tester,
        PaginationBar(page: 2, totalPages: 12, totalItems: 240, itemLabel: 'announcements', onPageChanged: pages.add),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Page 2 of 12 · 240 announcements'), findsOneWidget);

      await tester.tap(find.byTooltip('Next page'));
      await tester.tap(find.byTooltip('Previous page'));
      expect(pages, [3, 1]);
    });

    testWidgets('is hidden when everything fits on one page', (tester) async {
      await pumpAt360(tester, PaginationBar(page: 1, totalPages: 1, onPageChanged: (_) {}));
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('uses the singular for one item', (tester) async {
      await pumpAt360(tester, PaginationBar(page: 1, totalPages: 2, totalItems: 1, itemLabel: 'users', onPageChanged: (_) {}));
      expect(find.text('Page 1 of 2 · 1 user'), findsOneWidget);
    });
  });

  group('SafeHtmlView', () {
    testWidgets('renders bullets, numbers, small headings and entities', (tester) async {
      await pumpAt360(
        tester,
        const SingleChildScrollView(
          child: SafeHtmlView(
            html: '<h5>Checklist</h5>'
                '<ul><li>First</li><li>Second</li></ul>'
                '<ol><li>One</li><li>Two</li></ol>'
                '<p>Tom &amp; Jerry&#39;s &#x201C;show&#x201D; &mdash; done</p>',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Checklist'), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.textContaining('Tom & Jerry\'s “show” — done', findRichText: true), findsOneWidget);
    });
  });

  group('master data helpers', () {
    test('hex colours are validated and normalised', () {
      expect(normalizeHexColor('#c8a24b'), '#C8A24B');
      expect(normalizeHexColor('c8a24b'), '#C8A24B');
      expect(normalizeHexColor('#abc'), isNull);
      expect(normalizeHexColor('purple'), isNull);
    });

    test('legacy task categories map onto the three board groups', () {
      expect(normalizeTaskCategory('completed'), 'done');
      expect(normalizeTaskCategory('Done'), 'done');
      expect(normalizeTaskCategory('pending'), 'todo');
      expect(normalizeTaskCategory('testing'), 'in_progress');
      expect(normalizeTaskCategory('anything else'), 'in_progress');
    });
  });

  group('notification swipe', () {
    final a = NotificationItem(id: '1', message: 'A', createdAt: DateTime(2026, 9, 1));
    final b = NotificationItem(id: '2', message: 'B', isRead: true, createdAt: DateTime(2026, 9, 2));
    final c = NotificationItem(id: '3', message: 'C', createdAt: DateTime(2026, 9, 3));

    _TestNotifier notifier() => _TestNotifier(AppState(
          currentUser: const UserModel(id: '9', name: 'Test', email: 't@x.test', role: UserRole.intern),
          notifications: [a, b, c],
          unreadCount: 2,
        ));

    test('hiding removes the item at once and lowers the unread count', () {
      final n = notifier();
      n.hideNotification('1');
      expect(n.current.notifications.map((x) => x.id), ['2', '3']);
      expect(n.current.unreadCount, 1);
    });

    test('undo puts it back in the same place', () {
      final n = notifier();
      n.hideNotification('3');
      n.restoreNotification(c, 2);
      expect(n.current.notifications.map((x) => x.id), ['1', '2', '3']);
      expect(n.current.unreadCount, 2);
    });

    test('restoring twice does not duplicate', () {
      final n = notifier();
      n.restoreNotification(a, 0);
      expect(n.current.notifications.length, 3);
    });
  });

  group('intern duration', () {
    test('tiers from the dropdown API show months and leave days', () {
      final tier = DurationTier.fromJson({'title': '3 Months', 'duration_months': 3, 'duration_days': 90, 'leaves': 5, 'is_default': true});
      expect(tier.months, 3);
      expect(tier.leaves, 5);
      expect(tier.isDefault, isTrue);
      expect(tier.summary, '3 months · 5 leave days');
    });

    test('every intern needs a duration', () {
      expect(InternTerms().problem, 'Choose an internship duration.');
      expect(InternTerms(durationMonths: 3).problem, isNull);
      expect(InternTerms(durationMonths: 3, isPaid: true).problem, isNotNull);
      expect(InternTerms(durationMonths: 3).toPayload()['internship_duration_months'], 3);
    });
  });
}
