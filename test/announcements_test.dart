import 'package:flutter_test/flutter_test.dart';
import 'package:first_app/shared/models/announcement_model.dart';

void main() {
  group('Announcement Model & Normalizer Tests', () {
    test('parses Announcement from full JSON correctly', () {
      final json = {
        'id': 42,
        'title': 'Q3 Project Showcase Schedule',
        'body': 'Showcase is Friday 4pm in Lab 2. Bring demos.',
        'is_pinned': true,
        'project_id': 101,
        'project_name': 'InternHub App',
        'author_id': 7,
        'author_name': 'John Mentor',
        'author_role': 'mentor',
        'created_at': '2026-09-10T10:30:00Z',
      };

      final announcement = Announcement.fromJson(json);

      expect(announcement.id, 42);
      expect(announcement.title, 'Q3 Project Showcase Schedule');
      expect(announcement.body, 'Showcase is Friday 4pm in Lab 2. Bring demos.');
      expect(announcement.isPinned, true);
      expect(announcement.projectId, 101);
      expect(announcement.projectName, 'InternHub App');
      expect(announcement.authorId, 7);
      expect(announcement.authorName, 'John Mentor');
      expect(announcement.authorRole, 'mentor');
      expect(announcement.authorRoleFormatted, 'Mentor');
      expect(announcement.authorInitials, 'JM');
    });

    test('normalizes bare Array with client-side slicing', () {
      final rawList = [
        {
          'id': 1,
          'title': 'Announcement 1',
          'body': 'Body 1',
          'is_pinned': false,
          'author_id': 1,
          'created_at': '2026-09-10T10:00:00Z',
        },
        {
          'id': 2,
          'title': 'Announcement 2',
          'body': 'Body 2',
          'is_pinned': true,
          'author_id': 2,
          'created_at': '2026-09-10T11:00:00Z',
        },
      ];

      final res = normalizeAnnouncementListResponse(
        rawList,
        requestedPage: 1,
        requestedPageSize: 1,
      );

      expect(res.total, 2);
      expect(res.totalPages, 2);
      expect(res.page, 1);
      expect(res.pageSize, 1);
      expect(res.items.length, 1);
      expect(res.items.first.id, 1);

      // Page 2
      final resPage2 = normalizeAnnouncementListResponse(
        rawList,
        requestedPage: 2,
        requestedPageSize: 1,
      );
      expect(resPage2.items.length, 1);
      expect(resPage2.items.first.id, 2);
    });

    test('normalizes standard paginated response object with wrappers', () {
      final rawMap = {
        'items': [
          {
            'id': 10,
            'title': 'System Maintenance',
            'body': 'Scheduled downtime tonight.',
            'is_pinned': false,
            'author_id': 5,
            'created_at': '2026-09-10T08:00:00Z',
          },
        ],
        'page': 1,
        'page_size': 20,
        'total_pages': 1,
        'total': 1,
      };

      final res = normalizeAnnouncementListResponse(rawMap);

      expect(res.total, 1);
      expect(res.totalPages, 1);
      expect(res.items.length, 1);
      expect(res.items.first.title, 'System Maintenance');
    });

    test('handles aliases: announcements key, per_page, count, last_page', () {
      final rawMap = {
        'announcements': [
          {
            'id': 11,
            'title': 'Demo Day',
            'body': 'Prepare slides.',
            'is_pinned': true,
            'author_id': 3,
            'created_at': '2026-09-10T09:00:00Z',
          },
        ],
        'current_page': 2,
        'per_page': 10,
        'count': 15,
        'last_page': 2,
      };

      final res = normalizeAnnouncementListResponse(rawMap);

      expect(res.total, 15);
      expect(res.totalPages, 2);
      expect(res.page, 2);
      expect(res.pageSize, 10);
      expect(res.items.first.title, 'Demo Day');
      expect(res.items.first.isPinned, true);
    });
  });
}
