import '../../core/api/api_client.dart';
import 'models/activity_models.dart';

class ActivityRepository {
  static final ActivityRepository _instance = ActivityRepository._internal();
  factory ActivityRepository() => _instance;
  ActivityRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/audit?page&action&date&search&project_id
  Future<AuditLogList> fetchAudit({
    int page = 1,
    String? action,
    String? date,
    String? actor,
    int? projectId,
  }) async {
    final params = <String, dynamic>{
      'page': page,
    };

    if (action != null && action.isNotEmpty && action != 'all' && action != 'announcement') {
      params['action'] = action;
    }

    if (date != null && date.trim().isNotEmpty) {
      params['date'] = date.trim();
    }

    // Free-text search over who did it, what they did and what it was done to.
    if (actor != null && actor.trim().isNotEmpty) {
      params['search'] = actor.trim();
    }

    if (projectId != null) {
      params['project_id'] = projectId;
    }

    final res = await _client.get('/api/audit', queryParameters: params);
    if (res is Map<String, dynamic>) {
      return AuditLogList.fromJson(res);
    }
    return const AuditLogList(logs: [], page: 1, pageSize: 30, totalPages: 1, total: 0);
  }

  /// GET /api/announcements?page=&page_size=20
  Future<AnnouncementsPageResult> fetchAnnouncementsPage({
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = {
      'page': page,
      'page_size': pageSize,
    };

    final res = await _client.get('/api/announcements', queryParameters: params);
    return AnnouncementsPageResult.fromJson(res);
  }
}
