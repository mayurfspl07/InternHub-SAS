import 'package:intl/intl.dart';

class AssignmentSubmission {
  final int id;
  final int? assignmentId;
  final int userId;
  final String? userName;
  final String? userEmail;
  final String? submissionText;
  final String? githubUrl;
  final bool hasFile;
  final String? fileName;
  final int? fileSize;
  final String? fileUrl;
  final String status; // "submitted"|"approved"|"rejected"|"resubmitted"|"under_review"
  final double? score;
  final String? feedback;
  final String submittedAt;

  const AssignmentSubmission({
    required this.id,
    this.assignmentId,
    required this.userId,
    this.userName,
    this.userEmail,
    this.submissionText,
    this.githubUrl,
    this.hasFile = false,
    this.fileName,
    this.fileSize,
    this.fileUrl,
    this.status = 'submitted',
    this.score,
    this.feedback,
    required this.submittedAt,
  });

  String get displayName => userName?.isNotEmpty == true ? userName! : 'Intern #$userId';

  String get statusLabel {
    switch (status.toLowerCase().trim()) {
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'under_review':
        return 'Under Review';
      case 'resubmitted':
      case 'needs_revision':
        return 'Needs Revision';
      case 'submitted':
      default:
        return 'Submitted';
    }
  }

  String get formattedSubmittedAt {
    final dt = DateTime.tryParse(submittedAt);
    if (dt == null) return submittedAt;
    return DateFormat('MMM d, yyyy • h:mm a').format(dt.toLocal());
  }

  // Backward compatibility getters
  String get assignmentIdStr => (assignmentId ?? 0).toString();
  String get userIdStr => userId.toString();

  factory AssignmentSubmission.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return AssignmentSubmission(
      id: toInt(json['id']),
      assignmentId: json['assignment_id'] != null ? toInt(json['assignment_id']) : null,
      userId: toInt(json['user_id'] ?? json['user']?['id']),
      userName: json['user_name']?.toString() ?? json['user']?['name']?.toString(),
      userEmail: json['user_email']?.toString() ?? json['user']?['email']?.toString(),
      submissionText: json['submission_text']?.toString() ?? json['text']?.toString(),
      githubUrl: json['github_url']?.toString(),
      hasFile: json['has_file'] is bool
          ? json['has_file'] as bool
          : (json['file_url'] != null && json['file_url'].toString().isNotEmpty),
      fileName: json['file_name']?.toString(),
      fileSize: json['file_size'] != null ? toInt(json['file_size']) : null,
      fileUrl: json['file_url']?.toString() ?? json['attachment_url']?.toString(),
      status: json['status']?.toString() ?? 'submitted',
      score: toDouble(json['score'] ?? json['grade']),
      feedback: json['feedback']?.toString() ?? json['review_feedback']?.toString(),
      submittedAt: json['submitted_at']?.toString() ?? json['created_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (assignmentId != null) 'assignment_id': assignmentId,
      'user_id': userId,
      if (userName != null) 'user_name': userName,
      if (userEmail != null) 'user_email': userEmail,
      if (submissionText != null) 'submission_text': submissionText,
      if (githubUrl != null) 'github_url': githubUrl,
      'has_file': hasFile,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (fileUrl != null) 'file_url': fileUrl,
      'status': status,
      if (score != null) 'score': score,
      if (feedback != null) 'feedback': feedback,
      'submitted_at': submittedAt,
    };
  }
}

// Backward-compatibility alias
typedef SubmissionModel = AssignmentSubmission;

class AssignmentItem {
  final int id;
  final int? organizationId;
  final String title;
  final String? description;
  final int? createdById;
  final String? creatorName;
  final int? projectId;
  final String? projectName;
  final int? cohortId;
  final String? cohortName;
  final int? assignedToUserId;
  final String? dueDate; // YYYY-MM-DD
  final double? maxScore;
  final bool hasAttachment;
  final String? attachmentName;
  final String? attachmentUrl;
  final String status; // "active"|"draft"|"closed"|"archived"
  final AssignmentSubmission? mySubmission;
  final bool isSubmitted;
  final String? submissionStatus;
  final int submissionCount;
  final int reviewedCount;
  final int pendingReviewCount;
  final String? createdAt;
  final String? updatedAt;

  const AssignmentItem({
    required this.id,
    this.organizationId,
    required this.title,
    this.description,
    this.createdById,
    this.creatorName,
    this.projectId,
    this.projectName,
    this.cohortId,
    this.cohortName,
    this.assignedToUserId,
    this.dueDate,
    this.maxScore = 100.0,
    this.hasAttachment = false,
    this.attachmentName,
    this.attachmentUrl,
    this.status = 'active',
    this.mySubmission,
    this.isSubmitted = false,
    this.submissionStatus,
    this.submissionCount = 0,
    this.reviewedCount = 0,
    this.pendingReviewCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  String get formattedDueDate {
    if (dueDate == null || dueDate!.isEmpty) return 'No due date';
    final dt = DateTime.tryParse(dueDate!);
    if (dt == null) return dueDate!;
    return 'Due ${DateFormat('MMM d, yyyy').format(dt)}';
  }

  String get effectiveSubmissionStatus {
    if (mySubmission != null) {
      return mySubmission!.status;
    }
    if (submissionStatus != null && submissionStatus!.isNotEmpty) {
      return submissionStatus!;
    }
    if (isSubmitted) {
      return 'submitted';
    }
    return 'not_submitted';
  }

  // Backward compatibility getters
  DateTime? get parsedDueDate => dueDate != null ? DateTime.tryParse(dueDate!) : null;
  DateTime get parsedCreatedAt => (createdAt != null ? DateTime.tryParse(createdAt!) : null) ?? DateTime.now();
  List<AssignmentSubmission> get submissions => mySubmission != null ? [mySubmission!] : const [];

  factory AssignmentItem.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    AssignmentSubmission? parsedSubmission;
    if (json['my_submission'] is Map<String, dynamic>) {
      parsedSubmission = AssignmentSubmission.fromJson(json['my_submission'] as Map<String, dynamic>);
    } else if (json['submission'] is Map<String, dynamic>) {
      parsedSubmission = AssignmentSubmission.fromJson(json['submission'] as Map<String, dynamic>);
    }

    return AssignmentItem(
      id: toInt(json['id']),
      organizationId: json['organization_id'] != null ? toInt(json['organization_id']) : null,
      title: json['title']?.toString() ?? 'Assignment',
      description: json['description']?.toString(),
      createdById: json['created_by_id'] != null ? toInt(json['created_by_id']) : null,
      creatorName: json['creator_name']?.toString() ?? json['creator']?['name']?.toString(),
      projectId: json['project_id'] != null ? toInt(json['project_id']) : null,
      projectName: json['project_name']?.toString() ?? json['project']?['name']?.toString(),
      cohortId: json['cohort_id'] != null ? toInt(json['cohort_id']) : null,
      cohortName: json['cohort_name']?.toString() ?? json['cohort']?['name']?.toString(),
      assignedToUserId: json['assigned_to_user_id'] != null ? toInt(json['assigned_to_user_id']) : null,
      dueDate: json['due_date']?.toString(),
      maxScore: toDouble(json['max_score'] ?? json['max_points']) ?? 100.0,
      hasAttachment: json['has_attachment'] is bool
          ? json['has_attachment'] as bool
          : (json['attachment_url'] != null && json['attachment_url'].toString().isNotEmpty),
      attachmentName: json['attachment_name']?.toString(),
      attachmentUrl: json['attachment_url']?.toString(),
      status: json['status']?.toString() ?? 'active',
      mySubmission: parsedSubmission,
      isSubmitted: json['is_submitted'] is bool
          ? json['is_submitted'] as bool
          : (parsedSubmission != null || json['submission_status'] != null),
      submissionStatus: json['submission_status']?.toString(),
      submissionCount: toInt(json['submission_count'] ?? json['submissions_count']),
      reviewedCount: toInt(json['reviewed_count']),
      pendingReviewCount: toInt(json['pending_review_count']),
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (organizationId != null) 'organization_id': organizationId,
      'title': title,
      if (description != null) 'description': description,
      if (createdById != null) 'created_by_id': createdById,
      if (creatorName != null) 'creator_name': creatorName,
      if (projectId != null) 'project_id': projectId,
      if (projectName != null) 'project_name': projectName,
      if (cohortId != null) 'cohort_id': cohortId,
      if (cohortName != null) 'cohort_name': cohortName,
      if (assignedToUserId != null) 'assigned_to_user_id': assignedToUserId,
      if (dueDate != null) 'due_date': dueDate,
      if (maxScore != null) 'max_score': maxScore,
      'has_attachment': hasAttachment,
      if (attachmentName != null) 'attachment_name': attachmentName,
      if (attachmentUrl != null) 'attachment_url': attachmentUrl,
      'status': status,
      if (mySubmission != null) 'my_submission': mySubmission!.toJson(),
      'is_submitted': isSubmitted,
      if (submissionStatus != null) 'submission_status': submissionStatus,
      'submission_count': submissionCount,
      'reviewed_count': reviewedCount,
      'pending_review_count': pendingReviewCount,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }
}

// Backward-compatibility alias
typedef AssignmentModel = AssignmentItem;

class AssignmentListResponse {
  final List<AssignmentItem> items;
  final int page;
  final int pageSize;
  final int totalPages;
  final int total;

  const AssignmentListResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.total,
  });
}

class SubmissionsResponse {
  final int assignmentId;
  final String assignmentTitle;
  final List<AssignmentSubmission> submissions;

  const SubmissionsResponse({
    required this.assignmentId,
    required this.assignmentTitle,
    required this.submissions,
  });
}

AssignmentItem normalizeAssignmentItem(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    final data = raw['assignment'] is Map<String, dynamic>
        ? raw['assignment'] as Map<String, dynamic>
        : (raw['data'] is Map<String, dynamic> ? raw['data'] as Map<String, dynamic> : raw);
    return AssignmentItem.fromJson(data);
  }
  throw Exception('Invalid assignment data structure');
}

AssignmentListResponse normalizeAssignmentListResponse(
  dynamic raw, {
  int requestedPage = 1,
  int requestedPageSize = 20,
}) {
  if (raw == null) {
    return AssignmentListResponse(
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
        .map((e) => AssignmentItem.fromJson(e))
        .toList();
    final total = allItems.length;
    final totalPages = (total / requestedPageSize).ceil().clamp(1, 999999);
    final startIndex = (requestedPage - 1) * requestedPageSize;
    final pagedItems = startIndex >= total
        ? <AssignmentItem>[]
        : allItems.skip(startIndex).take(requestedPageSize).toList();

    return AssignmentListResponse(
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

    dynamic rawItems = data['assignments'] ?? data['items'] ?? data['results'] ?? (data['data'] is List ? data['data'] : null);
    List<AssignmentItem> items = [];
    if (rawItems is List) {
      items = rawItems
          .whereType<Map<String, dynamic>>()
          .map((e) => AssignmentItem.fromJson(e))
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

    return AssignmentListResponse(
      items: items,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
      total: total,
    );
  }

  return AssignmentListResponse(
    items: [],
    page: requestedPage,
    pageSize: requestedPageSize,
    totalPages: 1,
    total: 0,
  );
}

SubmissionsResponse normalizeSubmissionsResponse(dynamic raw, int fallbackAssignmentId, String fallbackTitle) {
  if (raw is Map<String, dynamic>) {
    final data = raw['data'] is Map<String, dynamic> ? raw['data'] as Map<String, dynamic> : raw;

    final assignmentMap = data['assignment'] is Map<String, dynamic> ? data['assignment'] as Map<String, dynamic> : null;
    final int aid = assignmentMap != null ? (int.tryParse(assignmentMap['id']?.toString() ?? '') ?? fallbackAssignmentId) : fallbackAssignmentId;
    final String title = assignmentMap?['title']?.toString() ?? fallbackTitle;

    final rawSubs = data['submissions'] ?? (data['items'] is List ? data['items'] : (raw is List ? raw : []));
    List<AssignmentSubmission> subs = [];
    if (rawSubs is List) {
      subs = rawSubs
          .whereType<Map<String, dynamic>>()
          .map((s) => AssignmentSubmission.fromJson(s))
          .toList();
    }

    return SubmissionsResponse(
      assignmentId: aid,
      assignmentTitle: title,
      submissions: subs,
    );
  } else if (raw is List) {
    final subs = raw
        .whereType<Map<String, dynamic>>()
        .map((s) => AssignmentSubmission.fromJson(s))
        .toList();
    return SubmissionsResponse(
      assignmentId: fallbackAssignmentId,
      assignmentTitle: fallbackTitle,
      submissions: subs,
    );
  }

  return SubmissionsResponse(
    assignmentId: fallbackAssignmentId,
    assignmentTitle: fallbackTitle,
    submissions: [],
  );
}
