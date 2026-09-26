import '../../core/api/api_client.dart';
import '../../shared/models/cohort_model.dart';

class CohortInternOption {
  final int userId;
  final String name;
  final String? email;
  final String? department;

  const CohortInternOption({
    required this.userId,
    required this.name,
    this.email,
    this.department,
  });

  String get displayName => name.isNotEmpty ? name : 'Intern #$userId';
  String get displaySubtitle {
    final parts = <String>[];
    if (email != null && email!.isNotEmpty) parts.add(email!);
    if (department != null && department!.isNotEmpty) parts.add(department!);
    return parts.join(' • ');
  }
}

class CohortsRepository {
  static final CohortsRepository _instance = CohortsRepository._internal();
  factory CohortsRepository() => _instance;
  CohortsRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/cohorts?page=&page_size=20&search=
  Future<CohortListResponse> getCohorts({
    int page = 1,
    int pageSize = 20,
    String? search,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };

    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }

    final res = await _client.get('/api/cohorts', queryParameters: query);
    return normalizeCohortListResponse(
      res,
      requestedPage: page,
      requestedPageSize: pageSize,
    );
  }

  /// GET /api/cohorts/{id} (full cohort + members)
  Future<Cohort> getCohort(int id) async {
    final res = await _client.get('/api/cohorts/$id');
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic>
          ? res['data'] as Map<String, dynamic>
          : res;
      return Cohort.fromJson(data);
    }
    throw Exception('Failed to load cohort #$id details');
  }

  /// POST /api/cohorts (JSON)
  /// Optional fields omitted if empty (description, start_date, end_date)
  Future<Cohort> createCohort({
    required String name,
    String? description,
    String? startDate,
    String? endDate,
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
    };

    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }
    if (startDate != null && startDate.trim().isNotEmpty) {
      payload['start_date'] = startDate.trim();
    }
    if (endDate != null && endDate.trim().isNotEmpty) {
      payload['end_date'] = endDate.trim();
    }

    final res = await _client.post('/api/cohorts', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic>
          ? res['data'] as Map<String, dynamic>
          : res;
      return Cohort.fromJson(data);
    }
    throw Exception('Failed to create cohort');
  }

  /// PUT /api/cohorts/{id} (JSON)
  /// Partial update with trimmed name; empty description/dates omitted
  Future<Cohort> updateCohort(
    int id, {
    required String name,
    String? description,
    String? startDate,
    String? endDate,
  }) async {
    final payload = <String, dynamic>{
      'name': name.trim(),
    };

    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }
    if (startDate != null && startDate.trim().isNotEmpty) {
      payload['start_date'] = startDate.trim();
    }
    if (endDate != null && endDate.trim().isNotEmpty) {
      payload['end_date'] = endDate.trim();
    }

    final res = await _client.put('/api/cohorts/$id', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic>
          ? res['data'] as Map<String, dynamic>
          : res;
      return Cohort.fromJson(data);
    }
    throw Exception('Failed to update cohort #$id');
  }

  /// DELETE /api/cohorts/{id} → { ok?: boolean }
  Future<bool> deleteCohort(int id) async {
    final res = await _client.delete('/api/cohorts/$id');
    if (res is Map<String, dynamic>) {
      return res['ok'] == true || res['success'] == true;
    }
    return true;
  }

  /// POST /api/cohorts/{cohortId}/members (JSON: { "user_id": 41 })
  Future<void> addMember(int cohortId, int userId) async {
    await _client.post(
      '/api/cohorts/$cohortId/members',
      body: {'user_id': userId},
    );
  }

  /// DELETE /api/cohorts/{cohortId}/members/{userId} (No body)
  Future<void> removeMember(int cohortId, int userId) async {
    await _client.delete('/api/cohorts/$cohortId/members/$userId');
  }

  /// Intern picker (add member):
  /// GET /api/admin/users?page=1&page_size=20&role=intern&search=
  /// Optional fallback: GET /api/users/dropdown?role=intern
  Future<List<CohortInternOption>> getInternOptions({String? search}) async {
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
            final id = int.tryParse(u['id']?.toString() ?? u['user_id']?.toString() ?? '') ?? 0;
            final name = u['name']?.toString() ??
                u['full_name']?.toString() ??
                u['user_name']?.toString() ??
                'Intern #$id';
            final email = u['email']?.toString() ?? u['user_email']?.toString();
            final dept = u['department']?.toString();
            return CohortInternOption(
              userId: id,
              name: name,
              email: email,
              department: dept,
            );
          })
          .where((o) => o.userId > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
