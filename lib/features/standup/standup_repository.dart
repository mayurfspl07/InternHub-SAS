import '../../core/api/api_client.dart';
import 'models/standup_models.dart';

class StandupRepository {
  static final StandupRepository _instance = StandupRepository._internal();
  factory StandupRepository() => _instance;
  StandupRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/standup?page&page_size=12&search&mood (filters run on the server)
  Future<StandupListResponse> getStandupFeed({
    int page = 1,
    int pageSize = 12,
    String? search,
    String? mood,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };

    if (search != null && search.trim().isNotEmpty) {
      params['search'] = search.trim();
    }

    if (mood != null && mood.trim().isNotEmpty && mood != 'all') {
      params['mood'] = mood.trim().toLowerCase();
    }

    final res = await _client.get('/api/standup', queryParameters: params);
    return StandupListResponse.fromJson(res);
  }

  /// GET /api/standup/today: today's log, or null when none was posted yet.
  Future<StandupLog?> getTodayStandup() async {
    final res = await _client.get('/api/standup/today');
    if (res is Map<String, dynamic> && res['id'] != null) {
      return StandupLog.fromJson(res);
    }
    return null;
  }

  /// POST /api/standup
  Future<StandupLog> createStandup({
    required String date,
    required String did,
    required String plan,
    String? blockers,
    String mood = 'good',
  }) async {
    final payload = {
      'date': date.trim(),
      'did': did.trim(),
      'plan': plan.trim(),
      'blockers': blockers?.trim() ?? '',
      'mood': mood.trim().toLowerCase(),
    };

    final res = await _client.post('/api/standup', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return StandupLog.fromJson(data);
    }
    throw Exception('Failed to create standup');
  }

  /// PUT /api/standup/{id} (No date field on update)
  Future<StandupLog> updateStandup(
    int id, {
    required String did,
    required String plan,
    String? blockers,
    String mood = 'good',
  }) async {
    final payload = {
      'did': did.trim(),
      'plan': plan.trim(),
      'blockers': blockers?.trim() ?? '',
      'mood': mood.trim().toLowerCase(),
    };

    final res = await _client.put('/api/standup/$id', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return StandupLog.fromJson(data);
    }
    throw Exception('Failed to update standup #$id');
  }

  /// DELETE /api/standup/{id}
  Future<bool> deleteStandup(int id) async {
    final res = await _client.delete('/api/standup/$id');
    if (res is Map<String, dynamic>) {
      return res['ok'] == true || res['success'] == true;
    }
    return true;
  }
}
