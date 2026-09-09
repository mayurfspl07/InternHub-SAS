// ignore_for_file: non_constant_identifier_names

enum LeaveType {
  casual,
  sick,
  earned,
  comp;

  static LeaveType fromString(String? val) {
    if (val == null) return LeaveType.casual;
    switch (val.toLowerCase().trim()) {
      case 'sick':
        return LeaveType.sick;
      case 'earned':
        return LeaveType.earned;
      case 'comp':
      case 'compoff':
      case 'comp_off':
        return LeaveType.comp;
      case 'casual':
      default:
        return LeaveType.casual;
    }
  }

  String toApiValue() {
    switch (this) {
      case LeaveType.casual:
        return 'casual';
      case LeaveType.sick:
        return 'sick';
      case LeaveType.earned:
        return 'earned';
      case LeaveType.comp:
        return 'comp';
    }
  }

  String get label {
    switch (this) {
      case LeaveType.casual:
        return 'Casual';
      case LeaveType.sick:
        return 'Sick';
      case LeaveType.earned:
        return 'Earned';
      case LeaveType.comp:
        return 'Comp Off';
    }
  }
}

enum LeaveStatus {
  pending,
  approved,
  rejected;

  static LeaveStatus fromString(String? val) {
    if (val == null) return LeaveStatus.pending;
    switch (val.toLowerCase().trim()) {
      case 'approved':
        return LeaveStatus.approved;
      case 'rejected':
        return LeaveStatus.rejected;
      case 'pending':
      default:
        return LeaveStatus.pending;
    }
  }

  String toApiValue() => name;
}

class LeaveRequest {
  final int id;
  final int user_id;
  final String? user_name;
  final String start_date; // YYYY-MM-DD
  final String end_date;
  final int days;
  final String reason;
  final String leave_type; // casual | sick | earned | comp
  final String status; // pending | approved | rejected
  final String? comment;
  final String? reviewer_comment;
  final int? reviewed_by;
  final String? reviewer_name;
  final String? reviewed_at;
  final String? attachment_url;
  final String? attachment_name;
  final bool? has_attachment;
  final dynamic attachment;
  final String created_at;

  const LeaveRequest({
    required this.id,
    required this.user_id,
    this.user_name,
    required this.start_date,
    required this.end_date,
    required this.days,
    required this.reason,
    required this.leave_type,
    required this.status,
    this.comment,
    this.reviewer_comment,
    this.reviewed_by,
    this.reviewer_name,
    this.reviewed_at,
    this.attachment_url,
    this.attachment_name,
    this.has_attachment,
    this.attachment,
    required this.created_at,
  });

  factory LeaveRequest.fromJson(Map<String, dynamic> json) {
    num toNum(dynamic v, [num defaultVal = 0]) {
      if (v == null) return defaultVal;
      if (v is num) return v;
      return num.tryParse(v.toString()) ?? defaultVal;
    }

    // Days calculation fallback
    int parsedDays = toNum(json['days'] ?? json['total_days']).toInt();
    final startStr = json['start_date']?.toString() ?? json['from_date']?.toString() ?? '';
    final endStr = json['end_date']?.toString() ?? json['to_date']?.toString() ?? '';
    if (parsedDays <= 0 && startStr.isNotEmpty && endStr.isNotEmpty) {
      final s = DateTime.tryParse(startStr);
      final e = DateTime.tryParse(endStr);
      if (s != null && e != null) {
        parsedDays = e.difference(s).inDays + 1;
        if (parsedDays <= 0) parsedDays = 1;
      }
    }

    // Attachment resolving
    String? attUrl = json['attachment_url']?.toString();
    String? attName = json['attachment_name']?.toString();
    final rawAtt = json['attachment'];
    if (rawAtt is Map) {
      attUrl ??= rawAtt['url']?.toString();
      attName ??= rawAtt['filename']?.toString() ?? rawAtt['name']?.toString();
    } else if (rawAtt is String && rawAtt.isNotEmpty) {
      attUrl ??= rawAtt;
      attName ??= rawAtt.split('/').last;
    }

    return LeaveRequest(
      id: toNum(json['id']).toInt(),
      user_id: toNum(json['user_id'] ?? json['user']?['id']).toInt(),
      user_name: json['user_name']?.toString() ?? json['user']?['name']?.toString(),
      start_date: startStr,
      end_date: endStr,
      days: parsedDays <= 0 ? 1 : parsedDays,
      reason: json['reason']?.toString() ?? '',
      leave_type: json['leave_type']?.toString() ?? json['type']?.toString() ?? 'casual',
      status: json['status']?.toString() ?? 'pending',
      comment: json['comment']?.toString(),
      reviewer_comment: json['reviewer_comment']?.toString(),
      reviewed_by: json['reviewed_by'] != null ? toNum(json['reviewed_by']).toInt() : null,
      reviewer_name: json['reviewer_name']?.toString() ?? json['approved_by']?.toString(),
      reviewed_at: json['reviewed_at']?.toString(),
      attachment_url: attUrl,
      attachment_name: attName,
      has_attachment: json['has_attachment'] as bool? ?? (attUrl != null || attName != null),
      attachment: rawAtt,
      created_at: json['created_at']?.toString() ?? json['requested_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': user_id,
      'user_name': user_name,
      'start_date': start_date,
      'end_date': end_date,
      'days': days,
      'reason': reason,
      'leave_type': leave_type,
      'status': status,
      'comment': comment,
      'reviewer_comment': reviewer_comment,
      'reviewed_by': reviewed_by,
      'reviewer_name': reviewer_name,
      'reviewed_at': reviewed_at,
      'attachment_url': attachment_url,
      'attachment_name': attachment_name,
      'has_attachment': has_attachment,
      'created_at': created_at,
    };
  }

  // Convenient helper getters
  bool get isPending => status.toLowerCase() == 'pending';
  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isRejected => status.toLowerCase() == 'rejected';

  String get displayComment => reviewer_comment ?? comment ?? '';
  String? get displayReviewer => reviewer_name ?? (reviewed_by != null ? 'Reviewer #$reviewed_by' : null);

  bool get hasAttachment =>
      has_attachment == true ||
      (attachment_url != null && attachment_url!.isNotEmpty) ||
      (attachment_name != null && attachment_name!.isNotEmpty) ||
      (attachment != null);

  String get typeLabel {
    final t = LeaveType.fromString(leave_type);
    return t.label;
  }

  // Backward compatibility getters for existing code
  String get userId => user_id.toString();
  String get userName => user_name ?? 'Intern';
  String get userAvatar => '';
  DateTime get startDate => DateTime.tryParse(start_date) ?? DateTime.now();
  DateTime get endDate => DateTime.tryParse(end_date) ?? DateTime.now();
  int get totalDays => days;
  LeaveType get type => LeaveType.fromString(leave_type);
  LeaveStatus get leaveStatus => LeaveStatus.fromString(status);
  DateTime get requestedAt => DateTime.tryParse(created_at) ?? DateTime.now();
  String? get approvedBy => displayReviewer;
  String? get rejectionReason => displayComment;
}

// Backward-compatibility alias
typedef LeaveModel = LeaveRequest;

class LeaveBalance {
  final num used;
  final num? pending;
  final num quota;
  final num remaining;
  final num? available_after_pending;

  const LeaveBalance({
    this.used = 0,
    this.pending,
    this.quota = 15,
    this.remaining = 15,
    this.available_after_pending,
  });

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    num toNum(dynamic v, [num defaultVal = 0]) {
      if (v == null) return defaultVal;
      if (v is num) return v;
      return num.tryParse(v.toString()) ?? defaultVal;
    }

    final q = toNum(json['quota'], 15);
    final u = toNum(json['used'], 0);
    final rem = toNum(json['remaining'], q - u);
    final pend = json['pending'] != null ? toNum(json['pending']) : null;
    final avail = json['available_after_pending'] != null
        ? toNum(json['available_after_pending'])
        : (pend != null ? rem - pend : rem);

    return LeaveBalance(
      used: u,
      pending: pend,
      quota: q,
      remaining: rem,
      available_after_pending: avail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'used': used,
      'pending': pending,
      'quota': quota,
      'remaining': remaining,
      'available_after_pending': available_after_pending,
    };
  }

  // Backward compatibility getters
  int get casualRemaining => (remaining * 0.25).round();
  int get casualTotal => (quota * 0.25).round();
  int get sickRemaining => (remaining * 0.25).round();
  int get sickTotal => (quota * 0.25).round();
  int get earnedRemaining => (remaining * 0.40).round();
  int get earnedTotal => (quota * 0.40).round();
  int get compOffRemaining => (remaining * 0.10).round();
  int get compOffTotal => (quota * 0.10).round();
}

class LeaveSummary {
  final int total;
  final int pending;
  final int approved;
  final int rejected;
  final int days_taken;
  final int days_pending;

  const LeaveSummary({
    required this.total,
    required this.pending,
    required this.approved,
    required this.rejected,
    required this.days_taken,
    required this.days_pending,
  });

  factory LeaveSummary.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int defaultVal = 0]) {
      if (v == null) return defaultVal;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? defaultVal;
    }

    return LeaveSummary(
      total: toInt(json['total']),
      pending: toInt(json['pending']),
      approved: toInt(json['approved']),
      rejected: toInt(json['rejected']),
      days_taken: toInt(json['days_taken']),
      days_pending: toInt(json['days_pending']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total': total,
      'pending': pending,
      'approved': approved,
      'rejected': rejected,
      'days_taken': days_taken,
      'days_pending': days_pending,
    };
  }
}

class LeaveMineResponse {
  final List<LeaveRequest> requests;
  final List<LeaveRequest>? pending_requests;
  final List<LeaveRequest>? approved_requests;
  final List<LeaveRequest>? rejected_requests;
  final LeaveSummary? summary;
  final LeaveBalance balance;

  const LeaveMineResponse({
    required this.requests,
    this.pending_requests,
    this.approved_requests,
    this.rejected_requests,
    this.summary,
    required this.balance,
  });

  factory LeaveMineResponse.fromJson(Map<String, dynamic> json) {
    List<LeaveRequest> parseList(dynamic raw) {
      if (raw is List) {
        return raw.map((e) => LeaveRequest.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    }

    final reqs = parseList(json['requests'] ?? json['items'] ?? json['data']);
    final pend = json['pending_requests'] != null ? parseList(json['pending_requests']) : null;
    final app = json['approved_requests'] != null ? parseList(json['approved_requests']) : null;
    final rej = json['rejected_requests'] != null ? parseList(json['rejected_requests']) : null;

    final sum = json['summary'] != null && json['summary'] is Map<String, dynamic>
        ? LeaveSummary.fromJson(json['summary'] as Map<String, dynamic>)
        : null;

    final bal = json['balance'] != null && json['balance'] is Map<String, dynamic>
        ? LeaveBalance.fromJson(json['balance'] as Map<String, dynamic>)
        : const LeaveBalance(used: 0, quota: 15, remaining: 15);

    return LeaveMineResponse(
      requests: reqs,
      pending_requests: pend,
      approved_requests: app,
      rejected_requests: rej,
      summary: sum,
      balance: bal,
    );
  }
}

class PaginatedLeaveResponse {
  final List<LeaveRequest> requests;
  final int page;
  final int page_size;
  final int total_pages;
  final int total;

  const PaginatedLeaveResponse({
    required this.requests,
    required this.page,
    required this.page_size,
    required this.total_pages,
    required this.total,
  });

  factory PaginatedLeaveResponse.fromDynamic(dynamic raw) {
    if (raw == null) {
      return const PaginatedLeaveResponse(
        requests: [],
        page: 1,
        page_size: 10,
        total_pages: 1,
        total: 0,
      );
    }

    // 1. Array wrapper normalization
    if (raw is List) {
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map((e) => LeaveRequest.fromJson(e))
          .toList();
      final len = list.length;
      return PaginatedLeaveResponse(
        requests: list,
        page: 1,
        page_size: len == 0 ? 10 : len,
        total_pages: 1,
        total: len,
      );
    }

    // 2. Object unwrap normalization
    if (raw is Map<String, dynamic>) {
      final dynamic data = raw['data'] is Map<String, dynamic> ? raw['data'] : raw;
      final dynamic rawList = data['requests'] ??
          data['items'] ??
          data['results'] ??
          (data['data'] is List ? data['data'] : null) ??
          (raw['requests'] ?? raw['items'] ?? raw['results']);

      List<LeaveRequest> list = [];
      if (rawList is List) {
        list = rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => LeaveRequest.fromJson(e))
            .toList();
      }

      int toInt(dynamic v, [int defaultVal = 0]) {
        if (v == null) return defaultVal;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString()) ?? defaultVal;
      }

      final page = toInt(data['page'] ?? data['current_page'] ?? raw['page'], 1);
      final pageSize = toInt(data['page_size'] ?? data['per_page'] ?? raw['page_size'], 10);
      final total = toInt(data['total'] ?? data['total_count'] ?? raw['total'], list.length);
      int totalPages = toInt(data['total_pages'] ?? raw['total_pages'], 0);
      if (totalPages <= 0) {
        totalPages = pageSize > 0 ? (total / pageSize).ceil() : 1;
        if (totalPages <= 0) totalPages = 1;
      }

      return PaginatedLeaveResponse(
        requests: list,
        page: page <= 0 ? 1 : page,
        page_size: pageSize <= 0 ? 10 : pageSize,
        total_pages: totalPages,
        total: total,
      );
    }

    return const PaginatedLeaveResponse(
      requests: [],
      page: 1,
      page_size: 10,
      total_pages: 1,
      total: 0,
    );
  }
}
