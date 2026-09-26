import 'package:intl/intl.dart';
import 'user_model.dart';

class CohortMember {
  final int userId;
  final String? name;
  final String? userName;
  final String? email;
  final String? userEmail;
  final String? department;
  final String? role;
  final String? joinedAt;

  const CohortMember({
    required this.userId,
    this.name,
    this.userName,
    this.email,
    this.userEmail,
    this.department,
    this.role,
    this.joinedAt,
  });

  // Client display mapping:
  // name = member.name || member.user_name || "Intern #${user_id}"
  // email = member.email || member.user_email
  String get displayName {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    if (userName != null && userName!.trim().isNotEmpty) return userName!.trim();
    return 'Intern #$userId';
  }

  String get displayEmail {
    if (email != null && email!.trim().isNotEmpty) return email!.trim();
    if (userEmail != null && userEmail!.trim().isNotEmpty) return userEmail!.trim();
    return '';
  }

  String get initials {
    final n = displayName;
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
  }

  // Backward compatibility getters
  String get id => userId.toString();
  String? get avatarUrl => null;

  factory CohortMember.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic val, int fallback) {
      if (val == null) return fallback;
      if (val is int) return val;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    return CohortMember(
      userId: parseInt(json['user_id'] ?? json['id'], 0),
      name: json['name']?.toString(),
      userName: json['user_name']?.toString(),
      email: json['email']?.toString(),
      userEmail: json['user_email']?.toString(),
      department: json['department']?.toString(),
      role: json['role']?.toString(),
      joinedAt: json['joined_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      if (name != null) 'name': name,
      if (userName != null) 'user_name': userName,
      if (email != null) 'email': email,
      if (userEmail != null) 'user_email': userEmail,
      if (department != null) 'department': department,
      if (role != null) 'role': role,
      if (joinedAt != null) 'joined_at': joinedAt,
    };
  }
}

class Cohort {
  final int id;
  final String name;
  final String? description;
  final String? startDate; // YYYY-MM-DD
  final String? endDate; // YYYY-MM-DD
  final int? createdById;
  final String? createdAt;
  final int? memberCount;
  final List<CohortMember>? members;

  const Cohort({
    required this.id,
    required this.name,
    this.description,
    this.startDate,
    this.endDate,
    this.createdById,
    this.createdAt,
    this.memberCount,
    this.members,
  });

  int get totalMembers => memberCount ?? members?.length ?? 0;

  /// Status badge (CLIENT-SIDE from start_date/end_date vs today YYYY-MM-DD):
  /// - no start & no end → "Active"
  /// - start > today → "Upcoming"
  /// - end < today → "Completed"
  /// - else → "Active Batch"
  String get statusLabel {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    final start = startDate?.trim();
    final end = endDate?.trim();

    final hasStart = start != null && start.isNotEmpty;
    final hasEnd = end != null && end.isNotEmpty;

    if (!hasStart && !hasEnd) {
      return 'Active';
    }

    if (hasStart && start.compareTo(todayStr) > 0) {
      return 'Upcoming';
    }

    if (hasEnd && end.compareTo(todayStr) < 0) {
      return 'Completed';
    }

    return 'Active Batch';
  }

  /// Dates: "Start → End" or "Ongoing batch" if no dates
  String get dateRangeFormatted {
    final start = startDate?.trim();
    final end = endDate?.trim();

    final hasStart = start != null && start.isNotEmpty;
    final hasEnd = end != null && end.isNotEmpty;

    String formatPart(String d) {
      final dt = DateTime.tryParse(d);
      if (dt == null) return d;
      return DateFormat('MMM d, yyyy').format(dt);
    }

    if (hasStart && hasEnd) {
      return '${formatPart(start)} → ${formatPart(end)}';
    } else if (hasStart) {
      return 'From ${formatPart(start)}';
    } else if (hasEnd) {
      return 'Until ${formatPart(end)}';
    }
    return 'Ongoing batch';
  }

  String get formattedCreatedAt {
    if (createdAt == null || createdAt!.isEmpty) return '';
    final dt = DateTime.tryParse(createdAt!);
    if (dt == null) return createdAt!;
    return DateFormat('MMM d, yyyy').format(dt.toLocal());
  }

  factory Cohort.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic val, int fallback) {
      if (val == null) return fallback;
      if (val is int) return val;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    int? parseNullableInt(dynamic val) {
      if (val == null) return null;
      if (val is int) return val;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString());
    }

    List<CohortMember>? parsedMembers;
    if (json['members'] is List) {
      parsedMembers = (json['members'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => CohortMember.fromJson(m))
          .toList();
    }

    return Cohort(
      id: parseInt(json['id'], 0),
      name: json['name']?.toString() ?? 'Cohort',
      description: json['description']?.toString(),
      startDate: json['start_date']?.toString(),
      endDate: json['end_date']?.toString(),
      createdById: parseNullableInt(json['created_by_id'] ?? json['creator_id']),
      createdAt: json['created_at']?.toString(),
      memberCount: parseNullableInt(json['member_count'] ?? json['members_count'] ?? json['total_interns']) ?? parsedMembers?.length,
      members: parsedMembers,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (description != null) 'description': description,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (createdById != null) 'created_by_id': createdById,
      if (createdAt != null) 'created_at': createdAt,
      if (memberCount != null) 'member_count': memberCount,
      if (members != null) 'members': members!.map((m) => m.toJson()).toList(),
    };
  }
}

// Alias for CohortModel
typedef CohortModel = Cohort;

class CohortListResponse {
  final List<Cohort> items;
  final int page;
  final int pageSize;
  final int totalPages;
  final int total;

  const CohortListResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.total,
  });
}

CohortListResponse normalizeCohortListResponse(
  dynamic raw, {
  int requestedPage = 1,
  int requestedPageSize = 20,
}) {
  if (raw == null) {
    return CohortListResponse(
      items: [],
      page: requestedPage,
      pageSize: requestedPageSize,
      totalPages: 1,
      total: 0,
    );
  }

  // 1. Bare array
  if (raw is List) {
    final allItems = raw
        .whereType<Map<String, dynamic>>()
        .map((e) => Cohort.fromJson(e))
        .toList();
    final total = allItems.length;
    final totalPages = (total / requestedPageSize).ceil().clamp(1, 999999);
    final startIndex = (requestedPage - 1) * requestedPageSize;
    final pagedItems = startIndex >= total
        ? <Cohort>[]
        : allItems.skip(startIndex).take(requestedPageSize).toList();

    return CohortListResponse(
      items: pagedItems,
      page: requestedPage,
      pageSize: requestedPageSize,
      totalPages: totalPages,
      total: total,
    );
  }

  // 2. Map response (unwrap data if needed)
  if (raw is Map<String, dynamic>) {
    final data = raw['data'] is Map<String, dynamic> ? raw['data'] as Map<String, dynamic> : raw;

    dynamic rawItems = data['cohorts'] ?? data['items'] ?? data['results'] ?? (data['data'] is List ? data['data'] : null);
    List<Cohort> items = [];
    if (rawItems is List) {
      items = rawItems
          .whereType<Map<String, dynamic>>()
          .map((e) => Cohort.fromJson(e))
          .toList();
    }

    int parseInt(dynamic val, int fallback) {
      if (val == null) return fallback;
      if (val is int) return val;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    final page = parseInt(
      data['page'] ?? raw['page'],
      requestedPage,
    );

    final pageSize = parseInt(
      data['page_size'] ?? data['pageSize'] ?? data['per_page'] ?? data['perPage'] ?? data['limit'] ?? raw['page_size'],
      requestedPageSize,
    );

    final total = parseInt(
      data['total'] ?? data['count'] ?? raw['total'] ?? raw['count'],
      items.length,
    );

    final calcTotalPages = pageSize > 0 ? (total / pageSize).ceil() : 1;
    final totalPages = parseInt(
      data['total_pages'] ?? data['totalPages'] ?? data['last_page'] ?? data['lastPage'] ?? raw['total_pages'],
      calcTotalPages < 1 ? 1 : calcTotalPages,
    );

    return CohortListResponse(
      items: items,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
      total: total,
    );
  }

  return CohortListResponse(
    items: [],
    page: requestedPage,
    pageSize: requestedPageSize,
    totalPages: 1,
    total: 0,
  );
}

/// canManageCohorts: role == "admin" OR "mentor" OR "superadmin"
bool canManageCohorts(UserModel currentUser) {
  return currentUser.role == UserRole.admin ||
      currentUser.role == UserRole.mentor ||
      currentUser.role == UserRole.superadmin;
}

// ==============================================================================
// PRESERVED MODELS FOR SYSTEM COMPATIBILITY (Notifications, Recycle Bin, etc.)
// ==============================================================================

class AnnouncementModel {
  final String id;
  final String title;
  final String message;
  final String authorName;
  final String authorRole;
  final DateTime postedAt;
  final bool isPinned;
  final String category;
  final List<String> attachmentUrls;
  final String? projectId;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.message,
    required this.authorName,
    this.authorRole = 'Staff',
    required this.postedAt,
    this.isPinned = false,
    this.category = 'General',
    this.attachmentUrls = const [],
    this.projectId,
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return AnnouncementModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      message: json['body']?.toString() ?? json['message']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? json['author']?['name']?.toString() ?? 'InternHub Team',
      authorRole: json['author_role']?.toString() ?? json['author']?['role']?.toString() ?? 'Operations',
      postedAt: parseDate(json['created_at'] ?? json['posted_at']),
      isPinned: json['is_pinned'] is bool ? json['is_pinned'] as bool : false,
      category: json['category']?.toString() ?? 'General',
      projectId: json['project_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': message,
      'is_pinned': isPinned,
      'project_id': projectId,
    };
  }
}

class NotificationItem {
  final String id;
  final String title;
  final String body;
  final DateTime time;
  final String category; // 'task', 'attendance', 'leave', 'system'
  final bool isRead;
  final String? route;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.category,
    this.isRead = false,
    this.route,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return NotificationItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Notification',
      body: json['body']?.toString() ?? json['message']?.toString() ?? '',
      time: parseDate(json['created_at'] ?? json['time']),
      category: json['category']?.toString() ?? json['type']?.toString() ?? 'system',
      isRead: json['is_read'] is bool ? json['is_read'] as bool : (json['read'] == true),
      route: json['route']?.toString() ?? json['link']?.toString(),
    );
  }

  NotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? time,
    String? category,
    bool? isRead,
    String? route,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      time: time ?? this.time,
      category: category ?? this.category,
      isRead: isRead ?? this.isRead,
      route: route ?? this.route,
    );
  }
}

class ActivityLogItem {
  final String id;
  final String userName;
  final String userAvatar;
  final String actionTitle;
  final String details;
  final DateTime timestamp;
  final String category;

  const ActivityLogItem({
    required this.id,
    required this.userName,
    this.userAvatar = '',
    required this.actionTitle,
    required this.details,
    required this.timestamp,
    this.category = 'System',
  });

  factory ActivityLogItem.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    final actor = json['actor_name']?.toString() ?? json['user_name']?.toString() ?? 'System';
    final action = json['action']?.toString() ?? '';
    final target = json['target']?.toString() ?? json['details']?.toString() ?? '';

    return ActivityLogItem(
      id: json['id']?.toString() ?? '',
      userName: actor,
      userAvatar: json['actor_avatar']?.toString() ?? json['user_avatar']?.toString() ?? '',
      actionTitle: action.isNotEmpty ? action : 'Activity update',
      details: target,
      timestamp: parseDate(json['created_at'] ?? json['timestamp']),
      category: json['category']?.toString() ?? 'General',
    );
  }
}

class RecycleBinItem {
  final String id;
  final String entityType; // 'Task', 'Project', 'User', 'Document'
  final String title;
  final String deletedBy;
  final DateTime deletedAt;
  final int daysRemaining;

  const RecycleBinItem({
    required this.id,
    required this.entityType,
    required this.title,
    required this.deletedBy,
    required this.deletedAt,
    this.daysRemaining = 15,
  });

  factory RecycleBinItem.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    final deleted = parseDate(json['deleted_at']);
    final days = (json['days_remaining'] as num?)?.toInt() ?? (15 - DateTime.now().difference(deleted).inDays).clamp(0, 15);

    return RecycleBinItem(
      id: json['id']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? json['type']?.toString() ?? 'Item',
      title: json['title']?.toString() ?? json['name']?.toString() ?? 'Deleted Resource',
      deletedBy: json['deleted_by']?.toString() ?? 'Admin',
      deletedAt: deleted,
      daysRemaining: days,
    );
  }
}
