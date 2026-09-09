import 'package:intl/intl.dart';

class Announcement {
  final int id;
  final String title;
  final String body;
  final bool isPinned;
  final int? projectId;
  final String? projectName;
  final int authorId;
  final String? authorName;
  final String? authorRole;
  final String createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.isPinned = false,
    this.projectId,
    this.projectName,
    required this.authorId,
    this.authorName,
    this.authorRole,
    required this.createdAt,
  });

  // Compatibility helpers
  String get message => body;
  DateTime get postedAt => DateTime.tryParse(createdAt) ?? DateTime.now();

  String get formattedCreatedAt {
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return createdAt;
    return DateFormat('MMM d, yyyy, h:mm a').format(dt.toLocal());
  }

  String get authorRoleFormatted {
    if (authorRole == null || authorRole!.trim().isEmpty) return 'Staff';
    final raw = authorRole!.trim();
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
  }

  String get authorInitials {
    final name = authorName?.trim() ?? '';
    if (name.isEmpty) return 'U';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  factory Announcement.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic val, int fallback) {
      if (val == null) return fallback;
      if (val is int) return val;
      if (val is double) return val.toInt();
      return int.tryParse(val.toString()) ?? fallback;
    }

    bool parseBool(dynamic val) {
      if (val == null) return false;
      if (val is bool) return val;
      if (val is num) return val != 0;
      return val.toString().toLowerCase() == 'true' || val.toString() == '1';
    }

    // Handle nested author object if present
    final authorMap = json['author'] is Map<String, dynamic> ? json['author'] as Map<String, dynamic> : null;

    final authorIdVal = parseInt(
      json['author_id'] ?? authorMap?['id'],
      0,
    );

    final authorNameVal = json['author_name']?.toString() ??
        authorMap?['name']?.toString() ??
        json['author']?.toString();

    final authorRoleVal = json['author_role']?.toString() ??
        authorMap?['role']?.toString();

    // Handle nested project object if present
    final projectMap = json['project'] is Map<String, dynamic> ? json['project'] as Map<String, dynamic> : null;
    final projectIdVal = json['project_id'] != null
        ? parseInt(json['project_id'], 0)
        : (projectMap?['id'] != null ? parseInt(projectMap!['id'], 0) : null);
    final projectNameVal = json['project_name']?.toString() ?? projectMap?['name']?.toString();

    return Announcement(
      id: parseInt(json['id'], 0),
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? json['message']?.toString() ?? '',
      isPinned: parseBool(json['is_pinned'] ?? json['pinned']),
      projectId: projectIdVal,
      projectName: projectNameVal,
      authorId: authorIdVal,
      authorName: authorNameVal,
      authorRole: authorRoleVal,
      createdAt: json['created_at']?.toString() ??
          json['posted_at']?.toString() ??
          DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'is_pinned': isPinned,
      if (projectId != null) 'project_id': projectId,
      if (projectName != null) 'project_name': projectName,
      'author_id': authorId,
      if (authorName != null) 'author_name': authorName,
      if (authorRole != null) 'author_role': authorRole,
      'created_at': createdAt,
    };
  }
}

class AnnouncementListResponse {
  final List<Announcement> items;
  final int page;
  final int pageSize;
  final int totalPages;
  final int total;

  const AnnouncementListResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.total,
  });

  factory AnnouncementListResponse.empty({int page = 1, int pageSize = 20}) {
    return AnnouncementListResponse(
      items: const [],
      page: page,
      pageSize: pageSize,
      totalPages: 1,
      total: 0,
    );
  }
}

/// Normalizes backend announcement responses according to specifications:
/// - If Array -> { items: array, page: 1, page_size: len, total_pages: 1, total: len }
/// - Else unwrap data; items from announcements | items | results | data
/// - page / page_size (aliases: pageSize, per_page, perPage, limit)
/// - total (aliases: count)
/// - total_pages (aliases: totalPages, last_page, lastPage) OR ceil(total / page_size)
/// - Legacy client-side slicing if backend returns bare array and client requested page/size.
AnnouncementListResponse normalizeAnnouncementListResponse(
  dynamic raw, {
  int requestedPage = 1,
  int requestedPageSize = 20,
}) {
  if (raw == null) {
    return AnnouncementListResponse.empty(
      page: requestedPage,
      pageSize: requestedPageSize,
    );
  }

  int parseNum(dynamic v, int fallback) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  // 1) Bare List case
  if (raw is List) {
    final all = <Announcement>[];
    for (final element in raw) {
      if (element is Map<String, dynamic>) {
        all.add(Announcement.fromJson(element));
      }
    }
    final total = all.length;
    final size = requestedPageSize > 0 ? requestedPageSize : 20;
    final totalPages = total > 0 ? ((total / size).ceil()) : 1;
    final page = requestedPage.clamp(1, totalPages > 0 ? totalPages : 1);

    // Client-side slice
    final start = (page - 1) * size;
    final items = start >= total
        ? <Announcement>[]
        : all.sublist(start, (start + size).clamp(0, total));

    return AnnouncementListResponse(
      items: items,
      page: page,
      pageSize: size,
      totalPages: totalPages,
      total: total,
    );
  }

  // 2) Map/Object case
  if (raw is Map<String, dynamic>) {
    // Unwrap data wrapper if present and doesn't directly contain items keys
    dynamic payload = raw;
    if (raw['data'] is Map<String, dynamic> &&
        !raw.containsKey('items') &&
        !raw.containsKey('announcements') &&
        !raw.containsKey('results')) {
      payload = raw['data'];
    }

    dynamic rawItems;
    if (payload is Map<String, dynamic>) {
      if (payload['announcements'] != null) {
        rawItems = payload['announcements'];
      } else if (payload['items'] != null) {
        rawItems = payload['items'];
      } else if (payload['results'] != null) {
        rawItems = payload['results'];
      } else if (payload['data'] != null && payload['data'] is List) {
        rawItems = payload['data'];
      }
    }

    final items = <Announcement>[];
    if (rawItems is List) {
      for (final element in rawItems) {
        if (element is Map<String, dynamic>) {
          items.add(Announcement.fromJson(element));
        }
      }
    }

    final page = parseNum(
      payload['page'] ?? payload['current_page'] ?? payload['currentPage'],
      requestedPage,
    );

    final pageSize = parseNum(
      payload['page_size'] ??
          payload['pageSize'] ??
          payload['per_page'] ??
          payload['perPage'] ??
          payload['limit'],
      requestedPageSize,
    );

    final total = parseNum(
      payload['total'] ?? payload['count'] ?? payload['total_count'],
      items.length,
    );

    int totalPages = parseNum(
      payload['total_pages'] ??
          payload['totalPages'] ??
          payload['last_page'] ??
          payload['lastPage'],
      0,
    );

    if (totalPages <= 0) {
      totalPages = pageSize > 0 ? (total / pageSize).ceil() : 1;
      if (totalPages <= 0) totalPages = 1;
    }

    // If backend returned a single list with length > pageSize without slicing it
    List<Announcement> finalItems = items;
    if (items.length > pageSize && items.length == total) {
      final start = (page - 1) * pageSize;
      finalItems = start >= total
          ? <Announcement>[]
          : items.sublist(start, (start + pageSize).clamp(0, total));
    }

    return AnnouncementListResponse(
      items: finalItems,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
      total: total,
    );
  }

  return AnnouncementListResponse.empty(
    page: requestedPage,
    pageSize: requestedPageSize,
  );
}
