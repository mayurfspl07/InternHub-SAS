import 'package:intl/intl.dart';
import '../../../shared/models/announcement_model.dart';
import '../../../shared/models/user_model.dart';

class AuditLogEntry {
  final int id;
  final int? actorId;
  final String actorName;
  final String action;
  final String verb;
  final String target;
  final int? targetId;
  final int? projectId;
  final int? affectedUserId;
  final String createdAt;

  const AuditLogEntry({
    required this.id,
    this.actorId,
    required this.actorName,
    required this.action,
    required this.verb,
    required this.target,
    this.targetId,
    this.projectId,
    this.affectedUserId,
    required this.createdAt,
  });

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return AuditLogEntry(
      id: parseInt(json['id']) ?? 0,
      actorId: parseInt(json['actor_id'] ?? json['user_id']),
      actorName: json['actor_name']?.toString() ?? json['user_name']?.toString() ?? 'System',
      action: json['action']?.toString() ?? 'general',
      verb: json['verb']?.toString() ?? 'performed action on',
      target: json['target']?.toString() ?? '',
      targetId: parseInt(json['target_id']),
      projectId: parseInt(json['project_id']),
      affectedUserId: parseInt(json['affected_user_id']),
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'actor_id': actorId,
      'actor_name': actorName,
      'action': action,
      'verb': verb,
      'target': target,
      'target_id': targetId,
      'project_id': projectId,
      'affected_user_id': affectedUserId,
      'created_at': createdAt,
    };
  }
}

class AuditLogList {
  final List<AuditLogEntry> logs;
  final int page;
  final int pageSize;
  final int totalPages;
  final int total;

  const AuditLogList({
    required this.logs,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.total,
  });

  factory AuditLogList.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    List rawLogs = [];
    if (json['logs'] is List) {
      rawLogs = json['logs'];
    } else if (json['items'] is List) {
      rawLogs = json['items'];
    } else if (json['data'] is List) {
      rawLogs = json['data'];
    }

    final parsedLogs = rawLogs
        .whereType<Map<String, dynamic>>()
        .map((m) => AuditLogEntry.fromJson(m))
        .toList();

    return AuditLogList(
      logs: parsedLogs,
      page: toInt(json['page'], 1),
      pageSize: toInt(json['page_size'] ?? json['pageSize'], 30),
      totalPages: toInt(json['total_pages'] ?? json['totalPages'], 1),
      total: toInt(json['total'] ?? json['total_records'], parsedLogs.length),
    );
  }
}

class AnnouncementsPageResult {
  final List<Announcement> items;
  final int page;
  final int pageSize;
  final int totalPages;
  final int total;

  const AnnouncementsPageResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.total,
  });

  factory AnnouncementsPageResult.fromJson(dynamic raw) {
    int toInt(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    List rawItems = [];
    int page = 1;
    int pageSize = 20;
    int totalPages = 1;
    int total = 0;

    if (raw is List) {
      rawItems = raw;
      total = raw.length;
    } else if (raw is Map<String, dynamic>) {
      if (raw['announcements'] is List) {
        rawItems = raw['announcements'];
      } else if (raw['items'] is List) {
        rawItems = raw['items'];
      } else if (raw['data'] is List) {
        rawItems = raw['data'];
      }
      page = toInt(raw['page'], 1);
      pageSize = toInt(raw['page_size'] ?? raw['pageSize'], 20);
      totalPages = toInt(raw['total_pages'] ?? raw['totalPages'], 1);
      total = toInt(raw['total'], rawItems.length);
    }

    final items = rawItems
        .whereType<Map<String, dynamic>>()
        .map((m) => Announcement.fromJson(m))
        .toList();

    return AnnouncementsPageResult(
      items: items,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
      total: total,
    );
  }
}

// Category mappings from web
const List<Map<String, String>> actionCategories = [
  {'value': 'all', 'label': 'All actions'},
  {'value': 'attendance', 'label': 'Attendance'},
  {'value': 'leave', 'label': 'Leave'},
  {'value': 'project', 'label': 'Projects'},
  {'value': 'task', 'label': 'Tasks'},
  {'value': 'user', 'label': 'Users'},
  {'value': 'standup', 'label': 'Standups'},
  {'value': 'review', 'label': 'Reviews'},
  {'value': 'announcement', 'label': 'Announcements'},
];

// Helper: check permission to view activity
bool canViewActivity(UserRole role) {
  return role == UserRole.admin || role == UserRole.superadmin || role == UserRole.mentor;
}

// Helper: isAnnouncementAuditAction
bool isAnnouncementAuditAction(String action) {
  final a = action.toLowerCase().trim();
  return a == 'announcement' || a.contains('announcement');
}

// Helper: announcementToAuditLogEntry
AuditLogEntry announcementToAuditLogEntry(Announcement announcement) {
  return AuditLogEntry(
    id: -announcement.id, // negative synthetic id
    actorId: announcement.authorId,
    actorName: announcement.authorName ?? 'Unknown',
    action: 'announcement',
    verb: 'posted announcement',
    target: announcement.title,
    targetId: announcement.id,
    projectId: announcement.projectId,
    createdAt: announcement.createdAt,
  );
}

// Helper: mergeAuditLogsWithAnnouncements
List<AuditLogEntry> mergeAuditLogsWithAnnouncements({
  required List<AuditLogEntry> auditLogs,
  required List<Announcement> announcements,
  required String category,
  String? dateFilter,
}) {
  // Filter announcements by date if dateFilter is set (YYYY-MM-DD)
  List<Announcement> filteredAnnouncements = announcements;
  if (dateFilter != null && dateFilter.isNotEmpty) {
    filteredAnnouncements = announcements.where((a) {
      if (a.createdAt.length >= 10) {
        return a.createdAt.substring(0, 10) == dateFilter;
      }
      return false;
    }).toList();
  }

  // If category === "announcement" -> return announcement entries only, sort by created_at DESC
  if (category == 'announcement') {
    final entries = filteredAnnouncements.map(announcementToAuditLogEntry).toList();
    entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  // If category !== "all" -> return audit logs only (no merge)
  if (category != 'all') {
    return List<AuditLogEntry>.from(auditLogs);
  }

  // If category === "all":
  // dedupe: skip synthetic announcement if audit already has same target_id for announcement action
  final existingAnnouncementIds = <int>{};
  for (final log in auditLogs) {
    if (isAnnouncementAuditAction(log.action) && log.targetId != null) {
      existingAnnouncementIds.add(log.targetId!);
    }
  }

  final merged = List<AuditLogEntry>.from(auditLogs);
  for (final ann in filteredAnnouncements) {
    if (!existingAnnouncementIds.contains(ann.id)) {
      merged.add(announcementToAuditLogEntry(ann));
    }
  }

  // Sort created_at DESC
  merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return merged;
}

// Relative time formatting
// Exact API datetime formatting
String formatApiDateTime(String? dateTimeStr) {
  if (dateTimeStr == null || dateTimeStr.isEmpty) return '—';
  final dt = DateTime.tryParse(dateTimeStr);
  if (dt == null) return dateTimeStr;
  return DateFormat('MMM d, yyyy, h:mm a').format(dt.toLocal());
}
