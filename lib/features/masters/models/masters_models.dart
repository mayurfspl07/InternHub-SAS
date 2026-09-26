import 'dart:ui';
import '../../../shared/models/user_model.dart';
import '../../../core/constants/app_colors.dart';

class TaskStatus {
  final int id;
  final String name;
  final String slug;
  final String color;
  final String statusCategory; // "todo" | "in_progress" | "done"
  final bool isDefault;
  final int orderIndex;
  final String? createdAt;
  final String? updatedAt;

  const TaskStatus({
    required this.id,
    required this.name,
    required this.slug,
    this.color = '#8B5CF6',
    this.statusCategory = 'in_progress',
    this.isDefault = false,
    this.orderIndex = 1,
    this.createdAt,
    this.updatedAt,
  });

  String get categoryBadge {
    final cat = statusCategory.toLowerCase().trim();
    if (cat == 'done' || cat == 'completed') {
      return 'Done';
    } else if (cat == 'in_progress' || cat == 'inprogress' || cat == 'doing' || cat == 'testing') {
      return 'In Progress';
    }
    return 'To Do';
  }

  Color get parsedColor {
    return parseHexColor(color, fallback: AppColors.taupe);
  }

  factory TaskStatus.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    return TaskStatus(
      id: toInt(json['id']),
      name: json['name']?.toString() ?? 'Status',
      slug: json['slug']?.toString() ?? '',
      color: json['color']?.toString() ?? '#8B5CF6',
      statusCategory: json['status_category']?.toString() ?? 'in_progress',
      isDefault: json['is_default'] == true,
      orderIndex: toInt(json['order_index'] ?? json['order'], 1),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'color': color,
      'status_category': statusCategory,
      'is_default': isDefault,
      'order_index': orderIndex,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }
}

class ProjectStatus {
  final int id;
  final int? organizationId;
  final String name;
  final String slug;
  final String color;
  final int orderIndex;
  final bool isDefault;
  final bool isSystem;
  final int projectCount;
  final String? createdAt;
  final String? updatedAt;

  const ProjectStatus({
    required this.id,
    this.organizationId,
    required this.name,
    required this.slug,
    this.color = '#3B82F6',
    this.orderIndex = 1,
    this.isDefault = false,
    this.isSystem = false,
    this.projectCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  Color get parsedColor {
    return parseHexColor(color, fallback: AppColors.taupe);
  }

  factory ProjectStatus.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    return ProjectStatus(
      id: toInt(json['id']),
      organizationId: json['organization_id'] != null ? toInt(json['organization_id']) : null,
      name: json['name']?.toString() ?? 'Status',
      slug: json['slug']?.toString() ?? '',
      color: json['color']?.toString() ?? '#3B82F6',
      orderIndex: toInt(json['order_index'] ?? json['order'], 1),
      isDefault: json['is_default'] == true,
      isSystem: json['is_system'] == true,
      projectCount: toInt(json['project_count'] ?? json['projects_count']),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      'name': name,
      'slug': slug,
      'color': color,
      'order_index': orderIndex,
      'is_default': isDefault,
      'is_system': isSystem,
      'project_count': projectCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }
}

class InternshipDuration {
  final int id;
  final int? organizationId;
  final String title;
  final int durationMonths;
  final int durationDays;
  final int leaves;
  final bool isDefault;
  final int orderIndex;
  final bool isActive;
  final int internCount;
  final String? createdAt;
  final String? updatedAt;

  const InternshipDuration({
    required this.id,
    this.organizationId,
    required this.title,
    required this.durationMonths,
    required this.durationDays,
    required this.leaves,
    this.isDefault = false,
    this.orderIndex = 1,
    this.isActive = true,
    this.internCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  String get shortBadgeLabel => '${durationMonths}m';

  String get spanFormatted => '$durationMonths Month${durationMonths == 1 ? "" : "s"} ($durationDays Days)';

  factory InternshipDuration.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    final months = toInt(json['duration_months'] ?? json['internship_duration'] ?? json['months'], 1);
    final days = toInt(json['duration_days'] ?? json['days'], months * 30);
    final leaves = toInt(json['leaves'] ?? json['leaves_allocation'], 0);

    return InternshipDuration(
      id: toInt(json['id']),
      organizationId: json['organization_id'] != null ? toInt(json['organization_id']) : null,
      title: json['title']?.toString() ?? '$months Months',
      durationMonths: months,
      durationDays: days,
      leaves: leaves,
      isDefault: json['is_default'] == true,
      orderIndex: toInt(json['order_index'] ?? json['order'], months),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      internCount: toInt(json['intern_count'] ?? json['interns_count']),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      'title': title,
      'internship_duration': durationMonths,
      'duration_months': durationMonths,
      'duration_days': durationDays,
      'leaves': leaves,
      'is_default': isDefault,
      'order_index': orderIndex,
      'is_active': isActive,
      'intern_count': internCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }
}

// Permissions Checkers
bool canManageTaskStatuses(UserModel user) => user.role == UserRole.admin || user.role == UserRole.superadmin;
bool canManageProjectStatuses(UserModel user) => user.role == UserRole.admin || user.role == UserRole.superadmin;
bool canManageInternshipDurations(UserModel user) => user.role == UserRole.admin || user.role == UserRole.superadmin;

// Helper: Auto-generate slug from name: lowercase, trim, replace non [a-z0-9] with _, trim leading/trailing _
String generateSlug(String name) {
  var s = name.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  s = s.replaceAll(RegExp(r'^_+|_+$'), '');
  return s;
}

// Helper: Parse Hex Color
Color parseHexColor(String? hexString, {Color fallback = AppColors.taupe}) {
  if (hexString == null) return fallback;
  var hex = hexString.replaceAll('#', '').trim();
  if (hex.length == 6) {
    hex = 'FF$hex';
  } else if (hex.length == 8) {
    // Already has alpha
  } else {
    return fallback;
  }
  final val = int.tryParse(hex, radix: 16);
  if (val == null) return fallback;
  return Color(val);
}

// Normalizers
List<TaskStatus> normalizeTaskStatusList(dynamic raw) {
  if (raw == null) return [];
  List items = [];
  if (raw is List) {
    items = raw;
  } else if (raw is Map<String, dynamic>) {
    items = raw['statuses'] ?? raw['items'] ?? raw['data'] ?? raw['results'] ?? [];
  }
  final list = items
      .whereType<Map<String, dynamic>>()
      .map((m) => TaskStatus.fromJson(m))
      .toList();
  list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  return list;
}

List<ProjectStatus> normalizeProjectStatusList(dynamic raw) {
  if (raw == null) return [];
  List items = [];
  if (raw is List) {
    items = raw;
  } else if (raw is Map<String, dynamic>) {
    items = raw['statuses'] ?? raw['items'] ?? raw['data'] ?? raw['results'] ?? [];
  }
  final list = items
      .whereType<Map<String, dynamic>>()
      .map((m) => ProjectStatus.fromJson(m))
      .toList();
  list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  return list;
}

List<InternshipDuration> normalizeInternshipDurationList(dynamic raw) {
  if (raw == null) return [];
  List items = [];
  if (raw is List) {
    items = raw;
  } else if (raw is Map<String, dynamic>) {
    items = raw['durations'] ?? raw['items'] ?? raw['data'] ?? raw['results'] ?? [];
  }
  final list = items
      .whereType<Map<String, dynamic>>()
      .map((m) => InternshipDuration.fromJson(m))
      .toList();
  list.sort((a, b) {
    final c = a.orderIndex.compareTo(b.orderIndex);
    if (c != 0) return c;
    return a.durationMonths.compareTo(b.durationMonths);
  });
  return list;
}
