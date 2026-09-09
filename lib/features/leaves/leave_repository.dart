import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../core/api/api_client.dart';
import '../../shared/models/leave_model.dart';

class LeaveRepository {
  static final LeaveRepository _instance = LeaveRepository._internal();
  factory LeaveRepository() => _instance;
  LeaveRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/leave/mine
  /// Intern balance, summary, and their own leave requests
  Future<LeaveMineResponse> getMine() async {
    final res = await _client.get('/api/leave/mine');
    if (res is Map<String, dynamic>) {
      return LeaveMineResponse.fromJson(res);
    }
    throw Exception('Unexpected response format from /api/leave/mine');
  }

  /// POST /api/leave (multipart FormData)
  /// Fields: start_date, end_date, reason, leave_type (default: casual), attachment (optional file)
  Future<LeaveRequest> createRequest({
    required String startDate,
    required String endDate,
    required String reason,
    String leaveType = 'casual',
    File? attachment,
  }) async {
    final fields = <String, String>{
      'start_date': startDate,
      'end_date': endDate,
      'reason': reason,
      'leave_type': leaveType,
    };

    List<http.MultipartFile>? files;
    if (attachment != null && await attachment.exists()) {
      final multipartFile = await http.MultipartFile.fromPath(
        'attachment',
        attachment.path,
      );
      files = [multipartFile];
    }

    final res = await _client.postMultipart(
      '/api/leave',
      fields: fields,
      files: files,
    );

    if (res is Map<String, dynamic>) {
      // Some backends wrap in data: { ... }
      final data = res['data'] is Map<String, dynamic> ? res['data'] : res;
      return LeaveRequest.fromJson(data as Map<String, dynamic>);
    }
    throw Exception('Failed to create leave request');
  }

  /// GET /api/leave/manage?page={page}&status={status}
  /// Admin/Mentor paginated queue
  Future<PaginatedLeaveResponse> getManage({
    int page = 1,
    String? status,
  }) async {
    final queryParams = <String, dynamic>{
      'page': page,
    };
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      queryParams['status'] = status.toLowerCase();
    }

    final res = await _client.get(
      '/api/leave/manage',
      queryParameters: queryParams,
    );

    return PaginatedLeaveResponse.fromDynamic(res);
  }

  /// POST /api/leave/{id}/review
  /// JSON body: { "decision": "approved" | "rejected", "comment": "..." }
  Future<LeaveRequest> review({
    required int id,
    required String decision,
    String? comment,
  }) async {
    final body = <String, dynamic>{
      'decision': decision,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    };

    final res = await _client.post(
      '/api/leave/$id/review',
      body: body,
    );

    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] : res;
      return LeaveRequest.fromJson(data as Map<String, dynamic>);
    }
    throw Exception('Failed to review leave request');
  }

  /// GET /api/leave/{id}/attachment
  /// Downloads or previews binary attachment bytes with auth headers
  Future<Uint8List> getAttachmentBytes(int id) async {
    return await _client.getBytes('/api/leave/$id/attachment');
  }

  /// GET /api/leave/balance
  Future<LeaveBalance> getBalance() async {
    final res = await _client.get('/api/leave/balance');
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic> ? res['data'] : res;
      return LeaveBalance.fromJson(data as Map<String, dynamic>);
    }
    throw Exception('Failed to fetch leave balance');
  }
}
