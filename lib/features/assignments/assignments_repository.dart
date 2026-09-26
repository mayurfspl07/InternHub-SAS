import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../shared/models/assignment_model.dart';
import '../../shared/models/cohort_model.dart';

class AssignmentPickerOption {
  final int id;
  final String name;

  const AssignmentPickerOption({
    required this.id,
    required this.name,
  });
}

class AssignmentsRepository {
  static final AssignmentsRepository _instance = AssignmentsRepository._internal();
  factory AssignmentsRepository() => _instance;
  AssignmentsRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/assignments?page=&page_size=20&search=&status=&project_id=
  Future<AssignmentListResponse> getAssignments({
    int page = 1,
    int pageSize = 20,
    String? search,
    String? status,
    int? projectId,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'page_size': pageSize,
    };

    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }

    if (status != null && status.trim().isNotEmpty && status.trim().toLowerCase() != 'all') {
      query['status'] = status.trim().toLowerCase();
    }

    if (projectId != null && projectId > 0) {
      query['project_id'] = projectId;
    }

    final res = await _client.get('/api/assignments', queryParameters: query);
    return normalizeAssignmentListResponse(
      res,
      requestedPage: page,
      requestedPageSize: pageSize,
    );
  }

  /// GET /api/assignments/{id}
  Future<AssignmentItem> getAssignment(int id) async {
    final res = await _client.get('/api/assignments/$id');
    return normalizeAssignmentItem(res);
  }

  /// POST /api/assignments (JSON)
  Future<AssignmentItem> createAssignment({
    required String title,
    String? description,
    int? projectId,
    int? cohortId,
    String? dueDate,
    double? maxScore,
    String status = 'active',
  }) async {
    final payload = <String, dynamic>{
      'title': title.trim(),
      'status': status.trim().toLowerCase(),
    };

    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }

    // Explicitly send null when None / not selected
    payload['project_id'] = (projectId != null && projectId > 0) ? projectId : null;
    payload['cohort_id'] = (cohortId != null && cohortId > 0) ? cohortId : null;

    if (dueDate != null && dueDate.trim().isNotEmpty) {
      payload['due_date'] = dueDate.trim();
    }

    if (maxScore != null) {
      payload['max_score'] = maxScore;
    }

    final res = await _client.post('/api/assignments', body: payload);
    return normalizeAssignmentItem(res);
  }

  /// PUT /api/assignments/{id} (JSON)
  Future<AssignmentItem> updateAssignment(
    int id, {
    required String title,
    String? description,
    int? projectId,
    int? cohortId,
    String? dueDate,
    double? maxScore,
    String status = 'active',
  }) async {
    final payload = <String, dynamic>{
      'title': title.trim(),
      'status': status.trim().toLowerCase(),
    };

    if (description != null && description.trim().isNotEmpty) {
      payload['description'] = description.trim();
    }

    payload['project_id'] = (projectId != null && projectId > 0) ? projectId : null;
    payload['cohort_id'] = (cohortId != null && cohortId > 0) ? cohortId : null;

    if (dueDate != null && dueDate.trim().isNotEmpty) {
      payload['due_date'] = dueDate.trim();
    }

    if (maxScore != null) {
      payload['max_score'] = maxScore;
    }

    final res = await _client.put('/api/assignments/$id', body: payload);
    return normalizeAssignmentItem(res);
  }

  /// DELETE /api/assignments/{id}
  Future<bool> deleteAssignment(int id) async {
    final res = await _client.delete('/api/assignments/$id');
    if (res is Map<String, dynamic>) {
      return res['ok'] == true || res['success'] == true;
    }
    return true;
  }

  /// POST /api/assignments/{id}/attachment (multipart: field `file`, max 2MB)
  Future<dynamic> uploadAttachment(int id, File file) async {
    final bytes = await file.length();
    if (bytes > 2 * 1024 * 1024) {
      throw Exception('Attachment file size exceeds 2MB limit');
    }

    final multipartFile = await http.MultipartFile.fromPath('file', file.path);
    return await _client.postMultipart(
      '/api/assignments/$id/attachment',
      files: [multipartFile],
    );
  }

  /// Download assignment brief: uses attachment_url or fallback GET /api/assignments/{id}/attachment
  Future<void> downloadBrief(AssignmentItem assignment) async {
    try {
      String? rawUrl = assignment.attachmentUrl;
      if (rawUrl != null && rawUrl.trim().isNotEmpty && rawUrl.startsWith('http')) {
        final uri = Uri.parse(rawUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      // Authenticated download via API endpoint
      final bytes = await _client.getBytes('/api/assignments/${assignment.id}/attachment');
      final tempDir = await getTemporaryDirectory();
      final fileName = assignment.attachmentName?.isNotEmpty == true
          ? assignment.attachmentName!
          : 'assignment_${assignment.id}_brief.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Assignment Brief: ${assignment.title}',
      );
    } catch (e) {
      // Fallback: try opening backend direct URL
      final fallbackUri = Uri.parse('${ApiConfig.baseUrl}/api/assignments/${assignment.id}/attachment');
      if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Failed to download project brief: $e');
      }
    }
  }

  /// POST /api/assignments/{id}/submit (Intern)
  /// If file present: multipart (`file`, `submission_text`, `github_url`)
  /// Else JSON: `{ "submission_text"?: "...", "github_url"?: "..." }`
  Future<Map<String, dynamic>> submitAssignment(
    int id, {
    String? submissionText,
    String? githubUrl,
    File? file,
  }) async {
    if (file != null) {
      final bytes = await file.length();
      if (bytes > 2 * 1024 * 1024) {
        throw Exception('Submission file size exceeds 2MB limit');
      }

      final fields = <String, String>{};
      if (submissionText != null && submissionText.trim().isNotEmpty) {
        fields['submission_text'] = submissionText.trim();
      }
      if (githubUrl != null && githubUrl.trim().isNotEmpty) {
        fields['github_url'] = githubUrl.trim();
      }

      final multipartFile = await http.MultipartFile.fromPath('file', file.path);
      final res = await _client.postMultipart(
        '/api/assignments/$id/submit',
        fields: fields,
        files: [multipartFile],
      );
      if (res is Map<String, dynamic>) return res;
      return {'success': true, 'message': 'Assignment submitted successfully'};
    } else {
      final payload = <String, dynamic>{};
      if (submissionText != null && submissionText.trim().isNotEmpty) {
        payload['submission_text'] = submissionText.trim();
      }
      if (githubUrl != null && githubUrl.trim().isNotEmpty) {
        payload['github_url'] = githubUrl.trim();
      }

      final res = await _client.post('/api/assignments/$id/submit', body: payload);
      if (res is Map<String, dynamic>) return res;
      return {'success': true, 'message': 'Assignment submitted successfully'};
    }
  }

  /// GET /api/assignments/{id}/submissions (Admin / Mentor)
  Future<SubmissionsResponse> getSubmissions(int id, {String fallbackTitle = 'Assignment'}) async {
    final res = await _client.get('/api/assignments/$id/submissions');
    return normalizeSubmissionsResponse(res, id, fallbackTitle);
  }

  /// POST /api/assignments/submissions/{submissionId}/review (Admin / Mentor)
  Future<Map<String, dynamic>> reviewSubmission(
    int submissionId, {
    required String status,
    double? score,
    String? feedback,
  }) async {
    final payload = <String, dynamic>{
      'status': status.trim().toLowerCase(),
    };

    if (score != null) {
      payload['score'] = score;
    }

    if (feedback != null && feedback.trim().isNotEmpty) {
      payload['feedback'] = feedback.trim();
    }

    final res = await _client.post(
      '/api/assignments/submissions/$submissionId/review',
      body: payload,
    );
    if (res is Map<String, dynamic>) return res;
    return {'ok': true};
  }

  /// Picker helper: Load projects list
  /// GET /api/projects?page=1&page_size=50&search=
  Future<List<AssignmentPickerOption>> getProjectOptions({String? search}) async {
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
            final name = p['name']?.toString() ?? p['title']?.toString() ?? 'Project #$id';
            return AssignmentPickerOption(id: id, name: name);
          })
          .where((o) => o.id > 0)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Picker helper: Load cohorts list
  /// GET /api/cohorts?page=1&page_size=50&search=
  Future<List<AssignmentPickerOption>> getCohortOptions({String? search}) async {
    try {
      final query = <String, dynamic>{
        'page': 1,
        'page_size': 50,
      };
      if (search != null && search.trim().isNotEmpty) {
        query['search'] = search.trim();
      }

      final res = await _client.get('/api/cohorts', queryParameters: query);
      final normalized = normalizeCohortListResponse(res);
      return normalized.items
          .map((c) => AssignmentPickerOption(id: c.id, name: c.name))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
