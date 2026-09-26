import '../../core/api/api_client.dart';
import 'models/dashboard_models.dart';

class DashboardRepository {
  final ApiClient _client;

  DashboardRepository({ApiClient? client}) : _client = client ?? ApiClient();

  /// GET /api/intern/dashboard
  Future<InternDashboardData> getInternDashboard() async {
    final res = await _client.get('/api/intern/dashboard');
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return InternDashboardData.fromJson(data);
    }
    throw Exception('Failed to load intern dashboard');
  }

  /// GET /api/mentor/dashboard
  Future<MentorDashboardData> getMentorDashboard() async {
    final res = await _client.get('/api/mentor/dashboard');
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return MentorDashboardData.fromJson(data);
    }
    throw Exception('Failed to load mentor dashboard');
  }

  /// GET /api/admin/dashboard
  Future<AdminDashboardData> getAdminDashboard() async {
    final res = await _client.get('/api/admin/dashboard');
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return AdminDashboardData.fromJson(data);
    }
    throw Exception('Failed to load admin dashboard');
  }

  /// POST /api/leave/{id}/review
  /// Body: { "decision": "approved" | "rejected", "comment"?: string }
  Future<bool> reviewLeave(
    int id, {
    required String decision,
    String? comment,
  }) async {
    final payload = <String, dynamic>{
      'decision': decision,
    };
    if (comment != null && comment.trim().isNotEmpty) {
      payload['comment'] = comment.trim();
    }

    final res = await _client.post(
      '/api/leave/$id/review',
      body: payload,
    );

    if (res is Map<String, dynamic>) {
      return res['ok'] == true || res['success'] == true || res.containsKey('id') || res.containsKey('data');
    }
    return true;
  }
}
