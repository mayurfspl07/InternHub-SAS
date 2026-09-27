import '../../core/api/api_client.dart';
import 'models/masters_models.dart';

class MastersRepository {
  static final MastersRepository _instance = MastersRepository._internal();
  factory MastersRepository() => _instance;
  MastersRepository._internal();

  final ApiClient _client = ApiClient();

  // ==========================================
  // TASK STATUSES
  // ==========================================

  /// GET /api/admin/task-statuses
  Future<List<TaskStatus>> getTaskStatuses() async {
    final res = await _client.get('/api/admin/task-statuses');
    return normalizeTaskStatusList(res);
  }

  /// Read-only: GET /api/projects/task-statuses (for boards)
  Future<List<TaskStatus>> getProjectTaskStatusesReadonly() async {
    final res = await _client.get('/api/projects/task-statuses');
    return normalizeTaskStatusList(res);
  }

  /// POST /api/admin/task-statuses
  Future<TaskStatus> createTaskStatus({
    required String name,
    String? slug,
    String color = '#8B5CF6',
    String statusCategory = 'in_progress',
    bool isDefault = false,
    int orderIndex = 1,
  }) async {
    final payload = {
      'name': name.trim(),
      'slug': (slug != null && slug.trim().isNotEmpty) ? slug.trim() : generateSlug(name),
      'color': color.trim(),
      'status_category': statusCategory.trim(),
      'is_default': isDefault,
      'order_index': orderIndex,
    };
    final res = await _client.post('/api/admin/task-statuses', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return TaskStatus.fromJson(data);
    }
    throw Exception('Failed to create task status');
  }

  /// PUT /api/admin/task-statuses/{id}
  Future<TaskStatus> updateTaskStatus(
    int id, {
    required String name,
    String? slug,
    String color = '#8B5CF6',
    String statusCategory = 'in_progress',
    bool isDefault = false,
    int orderIndex = 1,
  }) async {
    final payload = {
      'name': name.trim(),
      'color': color.trim(),
      'status_category': statusCategory.trim(),
      'is_default': isDefault,
      'order_index': orderIndex,
    };
    final res = await _client.put('/api/admin/task-statuses/$id', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return TaskStatus.fromJson(data);
    }
    throw Exception('Failed to update task status #$id');
  }

  /// PUT /api/admin/task-statuses/reorder
  Future<void> reorderTaskStatuses(List<int> statusIds) async {
    await _client.put(
      '/api/admin/task-statuses/reorder',
      body: {'status_ids': statusIds},
    );
  }

  /// DELETE /api/admin/task-statuses/{id}
  Future<bool> deleteTaskStatus(int id) async {
    final res = await _client.delete('/api/admin/task-statuses/$id');
    if (res is Map<String, dynamic>) {
      return res['ok'] == true || res['success'] == true;
    }
    return true;
  }

  // ==========================================
  // PROJECT STATUSES
  // ==========================================

  /// GET /api/admin/project-statuses
  Future<List<ProjectStatus>> getProjectStatuses() async {
    final res = await _client.get('/api/admin/project-statuses');
    return normalizeProjectStatusList(res);
  }

  /// Read-only: GET /api/projects/project-statuses
  Future<List<ProjectStatus>> getProjectStatusesReadonly() async {
    final res = await _client.get('/api/projects/project-statuses');
    return normalizeProjectStatusList(res);
  }

  /// POST /api/admin/project-statuses
  Future<ProjectStatus> createProjectStatus({
    required String name,
    String? slug,
    String color = '#3B82F6',
    int orderIndex = 1,
    bool isDefault = false,
  }) async {
    final payload = {
      'name': name.trim(),
      'slug': (slug != null && slug.trim().isNotEmpty) ? slug.trim() : generateSlug(name),
      'color': color.trim(),
      'order_index': orderIndex,
      'is_default': isDefault,
    };
    final res = await _client.post('/api/admin/project-statuses', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return ProjectStatus.fromJson(data);
    }
    throw Exception('Failed to create project status');
  }

  /// PUT /api/admin/project-statuses/{id}
  Future<ProjectStatus> updateProjectStatus(
    int id, {
    required String name,
    String? slug,
    String color = '#3B82F6',
    int orderIndex = 1,
    bool isDefault = false,
  }) async {
    final payload = {
      'name': name.trim(),
      'color': color.trim(),
      'order_index': orderIndex,
      'is_default': isDefault,
    };
    final res = await _client.put('/api/admin/project-statuses/$id', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return ProjectStatus.fromJson(data);
    }
    throw Exception('Failed to update project status #$id');
  }

  /// PUT /api/admin/project-statuses/reorder
  Future<void> reorderProjectStatuses(List<int> statusIds) async {
    await _client.put(
      '/api/admin/project-statuses/reorder',
      body: {'status_ids': statusIds},
    );
  }

  /// DELETE /api/admin/project-statuses/{id}
  Future<bool> deleteProjectStatus(int id) async {
    final res = await _client.delete('/api/admin/project-statuses/$id');
    if (res is Map<String, dynamic>) {
      return res['ok'] == true || res['success'] == true;
    }
    return true;
  }

  // ==========================================
  // INTERNSHIP DURATIONS
  // ==========================================

  /// GET /api/admin/internship-durations
  Future<List<InternshipDuration>> getInternshipDurations() async {
    final res = await _client.get('/api/admin/internship-durations');
    return normalizeInternshipDurationList(res);
  }

  /// GET /api/admin/internship-durations/dropdown
  Future<List<InternshipDuration>> getInternshipDurationsDropdown() async {
    final res = await _client.get('/api/admin/internship-durations/dropdown');
    return normalizeInternshipDurationList(res);
  }

  /// POST /api/admin/internship-durations
  Future<InternshipDuration> createInternshipDuration({
    required String title,
    required int durationMonths,
    required int durationDays,
    required int leaves,
    bool isDefault = false,
    bool isActive = true,
    int? orderIndex,
  }) async {
    final payload = {
      'title': title.trim(),
      'internship_duration': durationMonths,
      'duration_months': durationMonths,
      'duration_days': durationDays,
      'leaves': leaves,
      'is_default': isDefault,
      'is_active': isActive,
      'order_index': orderIndex ?? durationMonths,
    };
    final res = await _client.post('/api/admin/internship-durations', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return InternshipDuration.fromJson(data);
    }
    throw Exception('Failed to create internship duration');
  }

  /// PUT /api/admin/internship-durations/{id}
  Future<InternshipDuration> updateInternshipDuration(
    int id, {
    required String title,
    required int durationMonths,
    required int durationDays,
    required int leaves,
    bool? isDefault,
    bool? isActive,
    int? orderIndex,
  }) async {
    final payload = <String, dynamic>{
      'title': title.trim(),
      'internship_duration': durationMonths,
      'duration_months': durationMonths,
      'duration_days': durationDays,
      'leaves': leaves,
    };
    if (isDefault != null) payload['is_default'] = isDefault;
    if (isActive != null) payload['is_active'] = isActive;
    if (orderIndex != null) payload['order_index'] = orderIndex;

    final res = await _client.put('/api/admin/internship-durations/$id', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] as Map<String, dynamic> : res;
      return InternshipDuration.fromJson(data);
    }
    throw Exception('Failed to update internship duration #$id');
  }

  /// DELETE /api/admin/internship-durations/{id}
  Future<bool> deleteInternshipDuration(int id) async {
    final res = await _client.delete('/api/admin/internship-durations/$id');
    if (res is Map<String, dynamic>) {
      return res['ok'] == true || res['success'] == true;
    }
    return true;
  }
}
