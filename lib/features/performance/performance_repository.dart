import '../../core/api/api_client.dart';
import '../../shared/models/performance_review_model.dart';

class ReviewSelectOption {
  final int id;
  final String label;
  final String? subtitle;

  const ReviewSelectOption({
    required this.id,
    required this.label,
    this.subtitle,
  });
}

class PerformanceRepository {
  static final PerformanceRepository _instance = PerformanceRepository._internal();
  factory PerformanceRepository() => _instance;
  PerformanceRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/reviews?page=&page_size=20&search=&rating=&project_id=
  Future<ReviewListResponse> getReviews({
    int page = 1,
    int pageSize = 20,
    String? search,
    int? rating,
    int? projectId,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };

    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }

    if (rating != null && rating >= 1 && rating <= 5) {
      query['rating'] = rating;
    }

    if (projectId != null && projectId > 0) {
      query['project_id'] = projectId;
    }

    final res = await _client.get('/api/reviews', queryParameters: query);
    return normalizeReviewListResponse(
      res,
      requestedPage: page,
      requestedPageSize: pageSize,
    );
  }

  /// GET /api/reviews/{id}
  Future<PerformanceReview> getReview(int id) async {
    final res = await _client.get('/api/reviews/$id');
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return PerformanceReview.fromJson(data);
    }
    throw Exception('Failed to load performance review #$id');
  }

  /// POST /api/reviews (JSON) — create
  Future<PerformanceReview> createReview({
    required int internId,
    int? projectId,
    String? period,
    required int rating,
    int? technicalRating,
    int? communicationRating,
    int? initiativeRating,
    String? feedback,
    String? strengths,
    String? improvements,
  }) async {
    final payload = <String, dynamic>{
      'intern_id': internId,
      'rating': rating,
    };

    if (projectId != null && projectId > 0) {
      payload['project_id'] = projectId;
    }

    if (period != null && period.trim().isNotEmpty) {
      payload['period'] = period.trim();
    }

    if (technicalRating != null) {
      payload['technical_rating'] = technicalRating;
    }

    if (communicationRating != null) {
      payload['communication_rating'] = communicationRating;
    }

    if (initiativeRating != null) {
      payload['initiative_rating'] = initiativeRating;
    }

    if (feedback != null && feedback.trim().isNotEmpty) {
      payload['feedback'] = feedback.trim();
    }

    if (strengths != null && strengths.trim().isNotEmpty) {
      payload['strengths'] = strengths.trim();
    }

    if (improvements != null && improvements.trim().isNotEmpty) {
      payload['improvements'] = improvements.trim();
    }

    final res = await _client.post('/api/reviews', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return PerformanceReview.fromJson(data);
    }
    throw Exception('Failed to create performance review');
  }

  /// PUT /api/reviews/{id} (JSON) — edit (does NOT change intern/project/period)
  Future<PerformanceReview> updateReview({
    required int id,
    required int rating,
    int? technicalRating,
    int? communicationRating,
    int? initiativeRating,
    String? feedback,
    String? strengths,
    String? improvements,
  }) async {
    final payload = <String, dynamic>{
      'rating': rating,
    };

    if (technicalRating != null) {
      payload['technical_rating'] = technicalRating;
    }

    if (communicationRating != null) {
      payload['communication_rating'] = communicationRating;
    }

    if (initiativeRating != null) {
      payload['initiative_rating'] = initiativeRating;
    }

    if (feedback != null && feedback.trim().isNotEmpty) {
      payload['feedback'] = feedback.trim();
    }

    if (strengths != null && strengths.trim().isNotEmpty) {
      payload['strengths'] = strengths.trim();
    }

    if (improvements != null && improvements.trim().isNotEmpty) {
      payload['improvements'] = improvements.trim();
    }

    final res = await _client.put('/api/reviews/$id', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return PerformanceReview.fromJson(data);
    }
    throw Exception('Failed to update performance review');
  }

  /// DELETE /api/reviews/{id}
  Future<void> deleteReview(int id) async {
    await _client.delete('/api/reviews/$id');
  }

  /// Helper: Load interns for the create review form picker
  /// Uses GET /api/admin/users?page=1&page_size=50&role=intern&search= with fallback to /api/users/dropdown?role=intern
  Future<List<ReviewSelectOption>> getInternOptions({String? search}) async {
    try {
      final query = <String, dynamic>{
        'page': 1,
        'page_size': 50,
        'role': 'intern',
      };
      if (search != null && search.trim().isNotEmpty) {
        query['search'] = search.trim();
      }

      dynamic res;
      try {
        res = await _client.get('/api/admin/users', queryParameters: query);
      } catch (_) {
        res = await _client.get('/api/users/dropdown', queryParameters: {'role': 'intern'});
      }

      List items = [];
      if (res is List) {
        items = res;
      } else if (res is Map<String, dynamic>) {
        items = res['users'] ?? res['items'] ?? res['results'] ?? res['data'] ?? [];
      }

      return items
          .whereType<Map<String, dynamic>>()
          .map((u) {
            final id = int.tryParse(u['id']?.toString() ?? '') ?? 0;
            final name = u['name']?.toString() ?? u['full_name']?.toString() ?? 'Intern #$id';
            final email = u['email']?.toString();
            return ReviewSelectOption(id: id, label: name, subtitle: email);
          })
          .where((o) => o.id > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Helper: Load projects for filter & create review form picker
  /// Uses GET /api/projects?page=1&page_size=50&search=
  Future<List<ReviewSelectOption>> getProjectOptions({String? search}) async {
    try {
      final query = <String, dynamic>{
        'page': 1,
        'page_size': 50,
      };
      if (search != null && search.trim().isNotEmpty) {
        query['search'] = search.trim();
      }

      final res = await _client.get('/api/projects', queryParameters: query);
      List items = [];
      if (res is List) {
        items = res;
      } else if (res is Map<String, dynamic>) {
        items = res['projects'] ?? res['items'] ?? res['results'] ?? res['data'] ?? [];
      }

      return items
          .whereType<Map<String, dynamic>>()
          .map((p) {
            final id = int.tryParse(p['id']?.toString() ?? '') ?? 0;
            final title = p['title']?.toString() ?? p['name']?.toString() ?? 'Project #$id';
            return ReviewSelectOption(id: id, label: title);
          })
          .where((o) => o.id > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
