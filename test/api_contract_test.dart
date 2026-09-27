// Feeds real backend responses through the app's models and checks the fields the UI shows.
//
// test/fixtures/api_examples.json is a subset of the backend's routes/api/openapi_examples.json,
// captured from a live run. Refresh it from there when the API changes; a renamed key then fails here
// instead of silently showing blanks in the app.
import 'dart:convert';
import 'dart:io';

import 'package:first_app/features/activity_audit/models/activity_models.dart';
import 'package:first_app/features/dashboard/models/dashboard_models.dart';
import 'package:first_app/features/standup/models/standup_models.dart';
import 'package:first_app/shared/models/cohort_model.dart';
import 'package:first_app/shared/models/invite_model.dart';
import 'package:first_app/shared/models/leave_model.dart';
import 'package:first_app/shared/models/project_model.dart';
import 'package:first_app/shared/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> api;

  setUpAll(() {
    api = jsonDecode(File('test/fixtures/api_examples.json').readAsStringSync()) as Map<String, dynamic>;
  });

  Map<String, dynamic> obj(String key) => api[key] as Map<String, dynamic>;
  List<Map<String, dynamic>> list(dynamic v) => (v as List).cast<Map<String, dynamic>>();

  test('signed-in user (GET /api/auth/me)', () {
    final raw = obj('GET /api/auth/me');
    final user = UserModel.fromJson(raw);
    expect(user.id, raw['id'].toString());
    expect(user.name, raw['name']);
    expect(user.email, raw['email']);
    expect(user.role.toApiValue(), raw['role']);
    expect(user.isPlatformAdmin, raw['is_platform_admin']);
    expect(user.avatarUrl, raw['avatar_url']);
  });

  test('user admin list (GET /api/admin/users)', () {
    final items = list(obj('GET /api/admin/users')['items']);
    expect(items, isNotEmpty);
    for (final raw in items) {
      final u = UserModel.fromJson(raw);
      expect(u.id, raw['id'].toString());
      expect(u.name, raw['name']);
      expect(u.isActive, raw['is_active']);
      expect(u.jobTitle, raw['job_title']);
      expect(u.internshipDurationMonths, raw['internship_duration_months']);
    }
  });

  test('project detail with tasks (GET /api/projects/{id})', () {
    final raw = obj('GET /api/projects/{project_id}');
    final p = ProjectModel.fromJson(raw);
    expect(p.id, raw['id'].toString());
    expect(p.name, raw['name']);
    expect(p.progress, closeTo((raw['progress'] as num) / 100, 1e-9));
    expect(p.mentorName, raw['mentor_name']);
    expect(p.tasks.length, (raw['tasks'] as List).length);
    for (final (i, t) in p.tasks.indexed) {
      final rt = (raw['tasks'] as List)[i] as Map<String, dynamic>;
      expect(t.title, rt['title']);
      expect(t.rawStatus, rt['status']);
      expect(t.priority.name, rt['priority']);
      expect(t.assigneeName, rt['assignee_name']);
      expect(t.dueDate, rt['due_date'] == null ? isNull : isNotNull);
    }
  });

  test('task statuses are real slugs (GET /api/projects/{id}/task-statuses)', () {
    final statuses = list(obj('GET /api/projects/{project_id}/task-statuses')['statuses']);
    expect(statuses, isNotEmpty);
    for (final raw in statuses) {
      final col = TaskStatusColumn.fromJson(raw);
      expect(col.key, raw['slug']);
      expect(col.title, raw['name']);
    }
  });

  test('task comments and their files', () {
    final comments = list(api['GET /api/projects/tasks/{task_id}/comments']);
    final files = list(obj('GET /api/projects/tasks/{task_id}/attachments')['attachments']);
    expect(comments, isNotEmpty);
    expect(files, isNotEmpty);
    final c = TaskComment.fromJson(comments.first);
    expect(c.message, comments.first['body'] ?? comments.first['message']);
    expect(c.authorName, isNotEmpty);
    final a = TaskAttachment.fromJson(files.first);
    expect(a.fileName, files.first['file_name']);
    expect(a.uploadedByName, files.first['user_name']);
    expect(a.commentId, files.first['comment_id']?.toString());
  });

  test('notifications (GET /api/notifications)', () {
    final raw = obj('GET /api/notifications');
    for (final n in list(raw['notifications'])) {
      final item = NotificationItem.fromJson(n);
      expect(item.message, n['message']);
      expect(item.link, n['link']);
      expect(item.isRead, n['is_read']);
    }
  });

  test('recycle bin (GET /api/admin/bin)', () {
    final items = list(obj('GET /api/admin/bin')['items']);
    expect(items, isNotEmpty);
    for (final raw in items) {
      final item = RecycleBinItem.fromJson(raw);
      expect(item.title, raw['title']);
      expect(item.title, isNot('None'));
      expect(item.deletedByName, raw['deleted_by_name']);
      expect(item.expiresAt, isNotNull);
    }
  });

  test('invite link uses the server URL (POST /api/admin/invite-link)', () {
    final raw = obj('POST /api/admin/invite-link')['link'] as Map<String, dynamic>;
    final link = InviteLinkModel.fromJson(raw);
    expect(link.url, raw['url']);
    expect(link.label, raw['label']);
    expect(link.mentorName, raw['mentor_name']);
    expect(link.createdByName, raw['created_by_name']);
  });

  test('leave balance and review comment', () {
    final mine = LeaveMineResponse.fromJson(obj('GET /api/leave/mine'));
    final bal = obj('GET /api/leave/mine')['balance'] as Map<String, dynamic>;
    expect(mine.balance.quota, bal['quota']);
    expect(mine.balance.remaining, bal['remaining']);
    final reviewed = obj('POST /api/leave/review/{leave_id}');
    final req = LeaveRequest.fromJson(reviewed);
    expect(req.status, reviewed['status']);
    expect(req.reviewComment, reviewed['review_comment']);
    expect(req.reviewComment, isNotEmpty);
  });

  test('standup feed (GET /api/standup)', () {
    final raw = obj('GET /api/standup');
    final res = StandupListResponse.fromJson(raw);
    expect(res.logs.length, (raw['logs'] as List).length);
    final first = (raw['logs'] as List).first as Map<String, dynamic>;
    expect(res.logs.first.did, first['did']);
    expect(res.logs.first.mood, first['mood'] ?? '');
  });

  test('audit trail (GET /api/audit)', () {
    final raw = obj('GET /api/audit');
    final res = AuditLogList.fromJson(raw);
    expect(res.logs.length, (raw['logs'] as List).length);
    expect(res.logs.first.actorName, ((raw['logs'] as List).first as Map)['actor_name']);
  });

  test('intern dashboard', () {
    final raw = obj('GET /api/dashboard/intern');
    final d = InternDashboardData.fromJson(raw);
    expect(d.streak, raw['streak']);
    expect(d.assignedTasks.length, (raw['assigned_tasks'] as List).length);
    expect(d.assignedProjects.length, (raw['assigned_projects'] as List).length);
  });

  test('mentor dashboard', () {
    final raw = obj('GET /api/dashboard/mentor');
    final d = MentorDashboardData.fromJson(raw);
    expect(d.assignedInterns.length, (raw['assigned_interns'] as List).length);
    final rawTask = (raw['open_tasks'] as List).first as Map<String, dynamic>;
    expect(d.openTasks.first.assignedUserName, rawTask['assignee_name']);
  });

  test('admin dashboard', () {
    final raw = obj('GET /api/dashboard/admin');
    final d = AdminDashboardData.fromJson(raw);
    final stats = raw['stats'] as Map<String, dynamic>;
    expect(d.organization.name, (raw['organization'] as Map)['name']);
    expect(d.stats.onLeaveToday, stats['on_leave_today']);
    expect(d.stats.presentToday, stats['present_today']);
    final rawTask = (raw['open_tasks'] as List).first as Map<String, dynamic>;
    expect(d.openTasks.first.assignedUserName, rawTask['assignee_name']);
  });
}
