import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../core/api/api_client.dart';
import '../../shared/models/attendance_model.dart';
import '../../shared/models/project_model.dart';

class AttendanceRepository {
  final ApiClient _api = ApiClient();

  // -------------------------------------------------------------
  // INTERN ENDPOINTS
  // -------------------------------------------------------------

  /// GET /api/attendance/today
  Future<({AttendanceRecord? record, String today})> fetchTodayAttendance() async {
    final res = await _api.get('/api/attendance/today');
    if (res is Map<String, dynamic>) {
      final todayStr = res['today']?.toString() ?? DateTime.now().toIso8601String().substring(0, 10);
      final rawRec = res['record'];
      if (rawRec is Map<String, dynamic> && rawRec.isNotEmpty && rawRec['id'] != null) {
        return (record: AttendanceRecord.fromJson(rawRec), today: todayStr);
      }
      return (record: null, today: todayStr);
    }
    return (record: null, today: DateTime.now().toIso8601String().substring(0, 10));
  }

  /// POST /api/attendance/check-in (Multipart FormData: photo, lat, lng)
  Future<AttendanceRecord> checkIn({
    required File photo,
    required double latitude,
    required double longitude,
  }) async {
    final file = await http.MultipartFile.fromPath(
      'photo',
      photo.path,
      filename: 'checkin.jpg',
    );
    final res = await _api.postMultipart(
      '/api/attendance/check-in',
      fields: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
      },
      files: [file],
    );

    if (res is Map<String, dynamic>) {
      final rec = res['record'] is Map<String, dynamic> ? res['record'] as Map<String, dynamic> : res;
      return AttendanceRecord.fromJson(rec);
    }
    throw Exception('Unexpected response format from check-in');
  }

  /// POST /api/attendance/check-out (Multipart FormData: photo, lat, lng)
  Future<AttendanceRecord> checkOut({
    required File photo,
    required double latitude,
    required double longitude,
  }) async {
    final file = await http.MultipartFile.fromPath(
      'photo',
      photo.path,
      filename: 'checkout.jpg',
    );
    final res = await _api.postMultipart(
      '/api/attendance/check-out',
      fields: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
      },
      files: [file],
    );

    if (res is Map<String, dynamic>) {
      final rec = res['record'] is Map<String, dynamic> ? res['record'] as Map<String, dynamic> : res;
      return AttendanceRecord.fromJson(rec);
    }
    throw Exception('Unexpected response format from check-out');
  }

  /// GET /api/attendance/history?page=1&page_size=100&month=YYYY-MM?
  Future<AttendanceHistory> fetchHistory({
    int page = 1,
    int pageSize = 100,
    String? month,
  }) async {
    final q = <String, dynamic>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };
    if (month != null && month.isNotEmpty) {
      q['month'] = month;
    }

    final res = await _api.get('/api/attendance/history', queryParameters: q);
    if (res is Map<String, dynamic>) {
      return AttendanceHistory.fromJson(res);
    } else if (res is List) {
      return AttendanceHistory(
        records: res.map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)).toList(),
        page: page,
        totalPages: 1,
        total: res.length,
      );
    }
    return AttendanceHistory(records: [], page: 1, totalPages: 1, total: 0);
  }

  /// GET /api/attendance/my/export?from_date=&to_date=
  Future<Uint8List> exportMyAttendance({
    required String fromDate,
    required String toDate,
  }) async {
    return await _api.getBytes('/api/attendance/my/export', queryParameters: {
      'from_date': fromDate,
      'to_date': toDate,
    });
  }

  /// GET /api/audit?actor_id=&action=task.&date=YYYY-MM-DD
  Future<List<Map<String, dynamic>>> fetchDayTaskAudits({
    required int actorId,
    required String date,
  }) async {
    try {
      final res = await _api.get('/api/audit', queryParameters: {
        'actor_id': actorId.toString(),
        'action': 'task.',
        'date': date,
      });
      if (res is List) {
        return res.cast<Map<String, dynamic>>();
      } else if (res is Map<String, dynamic> && res['logs'] is List) {
        return (res['logs'] as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  /// GET /api/projects?page=1&page_size=20
  Future<List<ProjectModel>> fetchProjects() async {
    try {
      final res = await _api.get('/api/projects', queryParameters: {
        'page': '1',
        'page_size': '20',
      });
      if (res is Map<String, dynamic> && res['projects'] is List) {
        return (res['projects'] as List)
            .map((e) => ProjectModel.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (res is List) {
        return res.map((e) => ProjectModel.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  // -------------------------------------------------------------
  // STAFF (ADMIN / MENTOR) ENDPOINTS
  // -------------------------------------------------------------

  String _getPrefix(bool isMentor) => isMentor ? '/api/mentor/students' : '/api/admin/students';

  /// GET {prefix}?page=&page_size=20&is_active=&sort=name&window_days=30
  /// OR GET {prefix}/search?page=&page_size=20&q=&search=&is_active=
  Future<AdminStudentListResponse> fetchStaffStudents({
    required bool isMentor,
    int page = 1,
    int pageSize = 20,
    String? search,
    bool? isActive,
    String sort = 'name',
    int windowDays = 30,
  }) async {
    final prefix = _getPrefix(isMentor);
    final hasSearch = search != null && search.trim().isNotEmpty;
    final path = hasSearch ? '$prefix/search' : prefix;

    final q = <String, dynamic>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    if (hasSearch) {
      q['q'] = search.trim();
      q['search'] = search.trim();
    } else {
      q['sort'] = sort;
      q['window_days'] = windowDays.toString();
    }

    if (isActive != null) {
      q['is_active'] = isActive.toString();
    }

    final res = await _api.get(path, queryParameters: q);
    if (res is Map<String, dynamic>) {
      return AdminStudentListResponse.fromJson(res);
    }
    return AdminStudentListResponse(students: [], page: 1, pageSize: pageSize, total: 0, totalPages: 1);
  }

  /// GET {prefix}/today?page=&page_size=20&search=&department=&status=
  Future<AdminTodayStudentsResponse> fetchStaffToday({
    required bool isMentor,
    int page = 1,
    int pageSize = 20,
    String? search,
    String? department,
    String? status,
    bool? isActive,
  }) async {
    final prefix = _getPrefix(isMentor);
    final q = <String, dynamic>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    if (search != null && search.trim().isNotEmpty) {
      q['search'] = search.trim();
    }
    if (department != null && department.trim().isNotEmpty && department != 'All') {
      q['department'] = department.trim();
    }
    if (status != null && status.trim().isNotEmpty && status.toLowerCase() != 'all' && status.toLowerCase() != 'all statuses') {
      q['status'] = status.trim().toLowerCase();
    }
    if (isActive != null) {
      q['is_active'] = isActive.toString();
    }

    final res = await _api.get('$prefix/today', queryParameters: q);
    if (res is Map<String, dynamic>) {
      return AdminTodayStudentsResponse.fromJson(res);
    }
    return AdminTodayStudentsResponse(
      today: DateTime.now().toIso8601String().substring(0, 10),
      summary: const AdminTodaySummary(
        totalInterns: 0,
        checkedIn: 0,
        notCheckedIn: 0,
        checkedOut: 0,
        present: 0,
        late: 0,
        halfDay: 0,
        absent: 0,
        onLeave: 0,
        excused: 0,
        attended: 0,
        attendanceRate: 0.0,
      ),
      students: [],
      page: 1,
      pageSize: pageSize,
      total: 0,
      totalPages: 1,
    );
  }

  /// GET {prefix}/{userId}/attendance?page=&page_size=31&start=&end=&status=&month=
  Future<AdminStudentAttendanceResponse> fetchStudentAttendanceDetail({
    required bool isMentor,
    required int userId,
    int page = 1,
    int pageSize = 31,
    String? start,
    String? end,
    String? status,
    String? month,
  }) async {
    final prefix = _getPrefix(isMentor);
    final q = <String, dynamic>{
      'page': page.toString(),
      'page_size': pageSize.toString(),
    };

    if (start != null && start.isNotEmpty) q['start'] = start;
    if (end != null && end.isNotEmpty) q['end'] = end;
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all' && status.toLowerCase() != 'all statuses') {
      q['status'] = status.toLowerCase();
    }
    if (month != null && month.isNotEmpty) q['month'] = month;

    final res = await _api.get('$prefix/$userId/attendance', queryParameters: q);
    if (res is Map<String, dynamic>) {
      return AdminStudentAttendanceResponse.fromJson(res);
    }
    throw Exception('Failed to load student attendance detail');
  }

  /// GET {prefix}/export?from_date=&to_date=&user_id?&department?&status?&month?
  Future<Uint8List> exportStaffAttendance({
    required bool isMentor,
    String? fromDate,
    String? toDate,
    int? userId,
    String? department,
    String? status,
    String? month,
  }) async {
    final prefix = _getPrefix(isMentor);
    final q = <String, dynamic>{};
    if (fromDate != null && fromDate.isNotEmpty) q['from_date'] = fromDate;
    if (toDate != null && toDate.isNotEmpty) q['to_date'] = toDate;
    if (userId != null) q['user_id'] = userId.toString();
    if (department != null && department.isNotEmpty && department != 'All') q['department'] = department;
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') q['status'] = status.toLowerCase();
    if (month != null && month.isNotEmpty) q['month'] = month;

    return await _api.getBytes('$prefix/export', queryParameters: q);
  }

  // -------------------------------------------------------------
  // MUTATIONS (Admin / Staff)
  // -------------------------------------------------------------

  /// PUT /api/attendance/{id}
  /// body: { check_in?, check_out?|"clear"|null, status_override?, reason }
  Future<AttendanceRecord> updateAttendanceRecord({
    required int id,
    String? checkIn,
    dynamic checkOut,
    String? statusOverride,
    required String reason,
  }) async {
    final body = <String, dynamic>{
      'reason': reason,
    };
    if (checkIn != null) body['check_in'] = checkIn;
    if (checkOut != null) body['check_out'] = checkOut;
    if (statusOverride != null) body['status_override'] = statusOverride;

    final res = await _api.put('/api/attendance/$id', body: body);
    if (res is Map<String, dynamic>) {
      final rec = res['record'] is Map<String, dynamic> ? res['record'] as Map<String, dynamic> : res;
      return AttendanceRecord.fromJson(rec);
    }
    throw Exception('Failed to update attendance record');
  }

  /// POST /api/attendance/manual
  /// body: { user_id, date: YYYY-MM-DD, check_in, check_out?, status_override?, reason }
  Future<AttendanceRecord> createManualAttendance({
    required int userId,
    required String date,
    required String checkIn,
    String? checkOut,
    String? statusOverride,
    required String reason,
  }) async {
    final body = <String, dynamic>{
      'user_id': userId,
      'date': date,
      'check_in': checkIn,
      'reason': reason,
    };
    if (checkOut != null && checkOut.isNotEmpty) {
      body['check_out'] = checkOut;
    }
    if (statusOverride != null && statusOverride.isNotEmpty) {
      body['status_override'] = statusOverride;
    }

    final res = await _api.post('/api/attendance/manual', body: body);
    if (res is Map<String, dynamic>) {
      final rec = res['record'] is Map<String, dynamic> ? res['record'] as Map<String, dynamic> : res;
      return AttendanceRecord.fromJson(rec);
    }
    throw Exception('Failed to create manual attendance');
  }

  /// DELETE /api/attendance/{id} with body { reason }
  Future<void> deleteAttendanceRecord({
    required int id,
    required String reason,
  }) async {
    await _api.delete('/api/attendance/$id', body: {
      'reason': reason,
    });
  }

  /// GET /api/attendance/{id}/audit -> { logs: AttendanceAuditEntry[] }
  Future<List<AttendanceAuditEntry>> fetchRecordAuditLogs(int id) async {
    try {
      final res = await _api.get('/api/attendance/$id/audit');
      if (res is Map<String, dynamic> && res['logs'] is List) {
        return (res['logs'] as List)
            .map((e) => AttendanceAuditEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (res is List) {
        return res.map((e) => AttendanceAuditEntry.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// GET /api/attendance/{id}/photo/{type} bytes
  Future<Uint8List?> fetchAttendancePhotoBytes({
    required int attendanceId,
    required String type, // 'checkin' | 'checkout'
  }) async {
    try {
      return await _api.getBytes('/api/attendance/$attendanceId/photo/$type');
    } catch (_) {
      return null;
    }
  }
}
