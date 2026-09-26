import 'package:intl/intl.dart';
import 'user_model.dart';

class PerformanceReview {
  final int id;
  final int internId;
  final String? internName;
  final int reviewerId;
  final String? reviewerName;
  final int? projectId;
  final String? projectName;
  final String? period;
  final int rating; // overall 1–5
  final int? technicalRating; // 1–5
  final int? communicationRating; // 1–5
  final int? initiativeRating; // 1–5
  final String? feedback;
  final String? strengths;
  final String? improvements;
  final String createdAt;

  const PerformanceReview({
    required this.id,
    required this.internId,
    this.internName,
    required this.reviewerId,
    this.reviewerName,
    this.projectId,
    this.projectName,
    this.period,
    required this.rating,
    this.technicalRating,
    this.communicationRating,
    this.initiativeRating,
    this.feedback,
    this.strengths,
    this.improvements,
    required this.createdAt,
  });

  String get internDisplayName {
    if (internName != null && internName!.trim().isNotEmpty) {
      return internName!.trim();
    }
    return 'Intern #$internId';
  }

  String get reviewerDisplayName {
    if (reviewerName != null && reviewerName!.trim().isNotEmpty) {
      return reviewerName!.trim();
    }
    return reviewerId > 0 ? 'Mentor #$reviewerId' : 'Mentor';
  }

  String get internInitials {
    final name = internDisplayName;
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  String get formattedCreatedAt {
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return createdAt;
    return DateFormat('MMM d, yyyy').format(dt.toLocal());
  }

  bool get hasCategoryRatings =>
      technicalRating != null || communicationRating != null || initiativeRating != null;

  factory PerformanceReview.fromJson(Map<String, dynamic> json) {
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

    return PerformanceReview(
      id: parseInt(json['id'], 0),
      internId: parseInt(json['intern_id'] ?? json['user_id'], 0),
      internName: json['intern_name']?.toString() ?? json['user_name']?.toString(),
      reviewerId: parseInt(json['reviewer_id'] ?? json['mentor_id'], 0),
      reviewerName: json['reviewer_name']?.toString() ?? json['mentor_name']?.toString(),
      projectId: parseNullableInt(json['project_id']),
      projectName: json['project_name']?.toString(),
      period: json['period']?.toString() ?? json['evaluation_period']?.toString(),
      rating: parseInt(json['rating'] ?? json['overall_rating'], 5).clamp(1, 5),
      technicalRating: parseNullableInt(json['technical_rating'])?.clamp(1, 5),
      communicationRating: parseNullableInt(json['communication_rating'])?.clamp(1, 5),
      initiativeRating: parseNullableInt(json['initiative_rating'])?.clamp(1, 5),
      feedback: json['feedback']?.toString() ?? json['general_feedback']?.toString(),
      strengths: json['strengths']?.toString(),
      improvements: json['improvements']?.toString() ?? json['areas_for_improvement']?.toString(),
      createdAt: json['created_at']?.toString() ?? json['review_date']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'intern_id': internId,
      if (internName != null) 'intern_name': internName,
      'reviewer_id': reviewerId,
      if (reviewerName != null) 'reviewer_name': reviewerName,
      if (projectId != null) 'project_id': projectId,
      if (projectName != null) 'project_name': projectName,
      if (period != null) 'period': period,
      'rating': rating,
      if (technicalRating != null) 'technical_rating': technicalRating,
      if (communicationRating != null) 'communication_rating': communicationRating,
      if (initiativeRating != null) 'initiative_rating': initiativeRating,
      if (feedback != null) 'feedback': feedback,
      if (strengths != null) 'strengths': strengths,
      if (improvements != null) 'improvements': improvements,
      'created_at': createdAt,
    };
  }
}

class ReviewListResponse {
  final List<PerformanceReview> items;
  final int page;
  final int pageSize;
  final int totalPages;
  final int total;

  const ReviewListResponse({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.total,
  });
}

/// Normalizes backend review responses whether returned as:
/// - Bare JSON array
/// - Wrapped map with items/reviews/results/data
/// - Pagination aliases: pageSize, per_page, perPage, limit, totalPages, last_page, lastPage, count
ReviewListResponse normalizeReviewListResponse(
  dynamic raw, {
  int requestedPage = 1,
  int requestedPageSize = 20,
}) {
  if (raw == null) {
    return ReviewListResponse(
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
        .map((e) => PerformanceReview.fromJson(e))
        .toList();
    final total = allItems.length;
    final totalPages = (total / requestedPageSize).ceil().clamp(1, 999999);
    final startIndex = (requestedPage - 1) * requestedPageSize;
    final pagedItems = startIndex >= total
        ? <PerformanceReview>[]
        : allItems.skip(startIndex).take(requestedPageSize).toList();

    return ReviewListResponse(
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

    dynamic rawItems = data['reviews'] ?? data['items'] ?? data['results'] ?? (data['data'] is List ? data['data'] : null);
    List<PerformanceReview> items = [];
    if (rawItems is List) {
      items = rawItems
          .whereType<Map<String, dynamic>>()
          .map((e) => PerformanceReview.fromJson(e))
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

    return ReviewListResponse(
      items: items,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
      total: total,
    );
  }

  return ReviewListResponse(
    items: [],
    page: requestedPage,
    pageSize: requestedPageSize,
    totalPages: 1,
    total: 0,
  );
}

/// Permissions helper matching web /reviews exact rules
bool canCreateReview(UserModel currentUser) {
  return currentUser.role == UserRole.admin ||
      currentUser.role == UserRole.mentor ||
      currentUser.role == UserRole.superadmin;
}

/// canManageReview(review) for Edit/Delete on a card:
/// - role == "admin" OR "superadmin"
/// - OR currentUser.id == review.reviewer_id
/// - OR (role == "mentor" AND (review.reviewer_id is null/0 OR currentUser.id == review.reviewer_id))
bool canManageReview(PerformanceReview review, UserModel currentUser) {
  final role = currentUser.role;
  if (role == UserRole.admin || role == UserRole.superadmin) {
    return true;
  }
  final currentUserIdInt = int.tryParse(currentUser.id);
  if (currentUserIdInt != null && currentUserIdInt == review.reviewerId) {
    return true;
  }
  if (currentUser.id == review.reviewerId.toString()) {
    return true;
  }
  if (role == UserRole.mentor) {
    if (review.reviewerId == 0) {
      return true;
    }
    if (currentUserIdInt != null && currentUserIdInt == review.reviewerId) {
      return true;
    }
    if (currentUser.id == review.reviewerId.toString()) {
      return true;
    }
  }
  return false;
}
