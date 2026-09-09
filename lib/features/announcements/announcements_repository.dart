import '../../core/api/api_client.dart';
import '../../shared/models/announcement_model.dart';

class AnnouncementsRepository {
  static final AnnouncementsRepository _instance = AnnouncementsRepository._internal();
  factory AnnouncementsRepository() => _instance;
  AnnouncementsRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/announcements?page=&page_size=20&search=&pinned=
  Future<AnnouncementListResponse> getAnnouncements({
    int page = 1,
    int pageSize = 20,
    String? search,
    bool? pinned,
    int? projectId,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };

    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }

    if (pinned == true) {
      query['pinned'] = 'true';
    }

    if (projectId != null) {
      query['project_id'] = projectId;
    }

    final res = await _client.get('/api/announcements', queryParameters: query);
    return normalizeAnnouncementListResponse(
      res,
      requestedPage: page,
      requestedPageSize: pageSize,
    );
  }

  /// POST /api/announcements (JSON)
  Future<Announcement> createAnnouncement({
    required String title,
    required String body,
    bool isPinned = false,
  }) async {
    final payload = <String, dynamic>{
      'title': title.trim(),
      'body': body.trim(),
      'is_pinned': isPinned,
    };

    final res = await _client.post('/api/announcements', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] : res;
      return Announcement.fromJson(data as Map<String, dynamic>);
    }
    throw Exception('Failed to create announcement');
  }

  /// PUT /api/announcements/{id} (JSON)
  Future<Announcement> updateAnnouncement({
    required int id,
    required String title,
    required String body,
    bool isPinned = false,
  }) async {
    final payload = <String, dynamic>{
      'title': title.trim(),
      'body': body.trim(),
      'is_pinned': isPinned,
    };

    final res = await _client.put('/api/announcements/$id', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] : res;
      return Announcement.fromJson(data as Map<String, dynamic>);
    }
    throw Exception('Failed to update announcement');
  }

  /// DELETE /api/announcements/{id}
  Future<void> deleteAnnouncement(int id) async {
    await _client.delete('/api/announcements/$id');
  }
}
