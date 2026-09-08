class CohortMember {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final String role;

  const CohortMember({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.role,
  });

  factory CohortMember.fromJson(Map<String, dynamic> json) {
    return CohortMember(
      id: json['id']?.toString() ?? json['user_id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['user_name']?.toString() ?? 'Member',
      email: json['email']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      role: json['role']?.toString() ?? 'intern',
    );
  }
}

class CohortModel {
  final String id;
  final String name;
  final String description;
  final String batchSeason;
  final DateTime startDate;
  final DateTime endDate;
  final String leadMentorName;
  final int totalInterns;
  final double averageAttendanceRate;
  final double averagePerformance;
  final List<String> internAvatars;
  final List<CohortMember> members;

  const CohortModel({
    required this.id,
    required this.name,
    this.description = '',
    this.batchSeason = 'Summer 2026',
    required this.startDate,
    required this.endDate,
    this.leadMentorName = 'Unassigned',
    this.totalInterns = 0,
    this.averageAttendanceRate = 95.0,
    this.averagePerformance = 4.8,
    this.internAvatars = const [],
    this.members = const [],
  });

  factory CohortModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    List<CohortMember> parsedMembers = [];
    if (json['members'] is List) {
      parsedMembers = (json['members'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => CohortMember.fromJson(m))
          .toList();
    }

    final total = (json['member_count'] ?? json['total_interns'] as num?)?.toInt() ?? parsedMembers.length;

    return CohortModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Cohort',
      description: json['description']?.toString() ?? '',
      batchSeason: json['batch_season']?.toString() ?? 'Active Cohort',
      startDate: parseDate(json['start_date']),
      endDate: parseDate(json['end_date']),
      leadMentorName: json['lead_mentor_name']?.toString() ?? 'Staff Mentor',
      totalInterns: total,
      averageAttendanceRate: (json['avg_attendance'] as num?)?.toDouble() ?? 95.0,
      averagePerformance: (json['avg_performance'] as num?)?.toDouble() ?? 4.8,
      members: parsedMembers,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'start_date': startDate.toIso8601String().substring(0, 10),
      'end_date': endDate.toIso8601String().substring(0, 10),
    };
  }
}

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
