import '../../core/api/api_config.dart';

enum AttendanceStatus {
  present,
  late,
  halfDay,
  absent,
  leave,
  onLeave,
  excused,
  weekOff,
  notJoined,
  upcoming;

  static AttendanceStatus fromString(String? val) {
    if (val == null) return AttendanceStatus.present;
    switch (val.toLowerCase().trim()) {
      case 'late':
        return AttendanceStatus.late;
      case 'half_day':
      case 'halfday':
        return AttendanceStatus.halfDay;
      case 'absent':
        return AttendanceStatus.absent;
      case 'on_leave':
      case 'leave':
        return AttendanceStatus.onLeave;
      case 'excused':
        return AttendanceStatus.excused;
      case 'week_off':
      case 'weekoff':
      case 'off':
        return AttendanceStatus.weekOff;
      case 'not_joined':
        return AttendanceStatus.notJoined;
      case 'upcoming':
        return AttendanceStatus.upcoming;
      case 'present':
      default:
        return AttendanceStatus.present;
    }
  }

  String toApiValue() {
    switch (this) {
      case AttendanceStatus.late:
        return 'late';
      case AttendanceStatus.halfDay:
        return 'half_day';
      case AttendanceStatus.absent:
        return 'absent';
      case AttendanceStatus.leave:
      case AttendanceStatus.onLeave:
        return 'on_leave';
      case AttendanceStatus.excused:
        return 'excused';
      case AttendanceStatus.weekOff:
        return 'week_off';
      case AttendanceStatus.notJoined:
        return 'not_joined';
      case AttendanceStatus.upcoming:
        return 'upcoming';
      case AttendanceStatus.present:
        return 'present';
    }
  }

  String get displayName {
    switch (this) {
      case AttendanceStatus.late:
        return 'Late';
      case AttendanceStatus.halfDay:
        return 'Half-Day';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.leave:
      case AttendanceStatus.onLeave:
        return 'On Leave';
      case AttendanceStatus.excused:
        return 'Excused';
      case AttendanceStatus.weekOff:
        return 'Off';
      case AttendanceStatus.notJoined:
        return 'Not Joined';
      case AttendanceStatus.upcoming:
        return 'Upcoming';
      case AttendanceStatus.present:
        return 'Present';
    }
  }
}

class AttendanceLocation {
  final double lat;
  final double lng;
  final String? address;

  const AttendanceLocation({
    required this.lat,
    required this.lng,
    this.address,
  });

  factory AttendanceLocation.fromJson(Map<String, dynamic> json) {
    return AttendanceLocation(
      lat: (json['lat'] ?? json['latitude'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] ?? json['longitude'] as num?)?.toDouble() ?? 0.0,
      address: json['address']?.toString() ?? json['location_address']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
      if (address != null) 'address': address,
    };
  }
}

class AttendanceRecord {
  final int id;
  final int userId;
  final String? userName;
  final String date; // YYYY-MM-DD
  final String? checkIn;
  final String? checkOut;
  final double? hoursWorked;
  final String status;
  final String? notes;
  final String? checkoutSource;
  final bool checkoutMissed;
  final AttendanceLocation? checkInLocation;
  final AttendanceLocation? checkOutLocation;
  final String? checkInPhotoUrl;
  final String? checkOutPhotoUrl;

  // Backward compatibility fields
  final String? overrideReason;
  final String? overriddenBy;
  final String userAvatar;
  final bool isInsideGeofence;

  const AttendanceRecord({
    required this.id,
    required this.userId,
    this.userName,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.hoursWorked,
    required this.status,
    this.notes,
    this.checkoutSource,
    this.checkoutMissed = false,
    this.checkInLocation,
    this.checkOutLocation,
    this.checkInPhotoUrl,
    this.checkOutPhotoUrl,
    this.overrideReason,
    this.overriddenBy,
    this.userAvatar = '',
    this.isInsideGeofence = true,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic val, [int fallback = 0]) {
      if (val == null) return fallback;
      if (val is int) return val;
      return int.tryParse(val.toString()) ?? fallback;
    }

    double? parseDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString());
    }

    String? resolveUrl(dynamic raw) {
      if (raw == null) return null;
      final s = raw.toString().trim();
      if (s.isEmpty) return null;
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      return ApiConfig.url(s);
    }

    AttendanceLocation? parseLocation(dynamic locData, [dynamic rawLat, dynamic rawLng, dynamic rawAddr]) {
      if (locData is Map<String, dynamic>) {
        return AttendanceLocation.fromJson(locData);
      }
      if (rawLat != null || rawLng != null || rawAddr != null) {
        return AttendanceLocation(
          lat: (rawLat as num?)?.toDouble() ?? 0.0,
          lng: (rawLng as num?)?.toDouble() ?? 0.0,
          address: rawAddr?.toString(),
        );
      }
      return null;
    }

    final rawCheckInPhoto = json['check_in_photo_url'] ??
        json['checkin_photo_path'] ??
        json['selfie_url'] ??
        json['photo'] ??
        json['check_in_photo'];

    final rawCheckOutPhoto = json['check_out_photo_url'] ??
        json['checkout_photo_path'] ??
        json['check_out_photo'];

    final checkInLoc = parseLocation(
      json['check_in_location'] ?? json['checkin_location'],
      json['lat'] ?? json['latitude'],
      json['lng'] ?? json['longitude'],
      json['location_address'] ?? json['address'],
    );

    final checkOutLoc = parseLocation(
      json['check_out_location'] ?? json['checkout_location'],
      json['checkout_lat'],
      json['checkout_lng'],
      json['checkout_address'],
    );

    return AttendanceRecord(
      id: parseInt(json['id']),
      userId: parseInt(json['user_id'] ?? json['userId']),
      userName: json['user_name']?.toString() ?? json['user']?['name']?.toString(),
      date: json['date']?.toString() ?? DateTime.now().toIso8601String().substring(0, 10),
      checkIn: json['check_in']?.toString() ?? json['check_in_time']?.toString(),
      checkOut: json['check_out']?.toString() ?? json['check_out_time']?.toString(),
      hoursWorked: parseDouble(json['hours_worked'] ?? json['working_hours']),
      status: json['status']?.toString() ?? json['status_override']?.toString() ?? 'present',
      notes: json['notes']?.toString(),
      checkoutSource: json['checkout_source']?.toString(),
      checkoutMissed: json['checkout_missed'] == true,
      checkInLocation: checkInLoc,
      checkOutLocation: checkOutLoc,
      checkInPhotoUrl: resolveUrl(rawCheckInPhoto),
      checkOutPhotoUrl: resolveUrl(rawCheckOutPhoto),
      overrideReason: json['override_reason']?.toString() ?? json['reason']?.toString(),
      overriddenBy: json['overridden_by']?.toString(),
      userAvatar: json['user_avatar']?.toString() ?? json['user']?['avatar_url']?.toString() ?? '',
      isInsideGeofence: json['is_inside_geofence'] is bool ? json['is_inside_geofence'] as bool : true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      if (userName != null) 'user_name': userName,
      'date': date,
      if (checkIn != null) 'check_in': checkIn,
      if (checkOut != null) 'check_out': checkOut,
      if (hoursWorked != null) 'hours_worked': hoursWorked,
      'status': status,
      if (notes != null) 'notes': notes,
      if (checkoutSource != null) 'checkout_source': checkoutSource,
      'checkout_missed': checkoutMissed,
      if (checkInLocation != null) 'check_in_location': checkInLocation!.toJson(),
      if (checkOutLocation != null) 'check_out_location': checkOutLocation!.toJson(),
      if (checkInPhotoUrl != null) 'check_in_photo_url': checkInPhotoUrl,
      if (checkOutPhotoUrl != null) 'check_out_photo_url': checkOutPhotoUrl,
    };
  }

  // Backward compatibility getters
  DateTime get dateTime {
    return DateTime.tryParse(date) ?? DateTime.now();
  }

  DateTime get checkInTime {
    if (checkIn != null) {
      final parsed = DateTime.tryParse(checkIn!);
      if (parsed != null) return parsed;
      // Try combining date and time string
      final combo = DateTime.tryParse('${date}T$checkIn');
      if (combo != null) return combo;
    }
    return dateTime;
  }

  DateTime? get checkOutTime {
    if (checkOut != null) {
      final parsed = DateTime.tryParse(checkOut!);
      if (parsed != null) return parsed;
      final combo = DateTime.tryParse('${date}T$checkOut');
      if (combo != null) return combo;
    }
    return null;
  }

  double get latitude => checkInLocation?.lat ?? 0.0;
  double get longitude => checkInLocation?.lng ?? 0.0;
  String get locationAddress => checkInLocation?.address ?? 'Recorded Location';
  String? get selfieUrl => checkInPhotoUrl;
  AttendanceStatus get statusEnum => AttendanceStatus.fromString(status);

  Duration? get workingHours {
    if (hoursWorked != null) {
      return Duration(minutes: (hoursWorked! * 60).round());
    }
    return null;
  }

  AttendanceRecord copyWith({
    int? id,
    int? userId,
    String? userName,
    String? date,
    String? checkIn,
    String? checkOut,
    double? hoursWorked,
    String? status,
    String? notes,
    String? checkoutSource,
    bool? checkoutMissed,
    AttendanceLocation? checkInLocation,
    AttendanceLocation? checkOutLocation,
    String? checkInPhotoUrl,
    String? checkOutPhotoUrl,
    String? overrideReason,
    String? overriddenBy,
    String? userAvatar,
    bool? isInsideGeofence,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      date: date ?? this.date,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      hoursWorked: hoursWorked ?? this.hoursWorked,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      checkoutSource: checkoutSource ?? this.checkoutSource,
      checkoutMissed: checkoutMissed ?? this.checkoutMissed,
      checkInLocation: checkInLocation ?? this.checkInLocation,
      checkOutLocation: checkOutLocation ?? this.checkOutLocation,
      checkInPhotoUrl: checkInPhotoUrl ?? this.checkInPhotoUrl,
      checkOutPhotoUrl: checkOutPhotoUrl ?? this.checkOutPhotoUrl,
      overrideReason: overrideReason ?? this.overrideReason,
      overriddenBy: overriddenBy ?? this.overriddenBy,
      userAvatar: userAvatar ?? this.userAvatar,
      isInsideGeofence: isInsideGeofence ?? this.isInsideGeofence,
    );
  }
}

class AttendanceHistory {
  final List<AttendanceRecord> records;
  final int page;
  final int totalPages;
  final int total;

  const AttendanceHistory({
    required this.records,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  factory AttendanceHistory.fromJson(Map<String, dynamic> json) {
    final list = (json['records'] ?? json['history'] ?? json['data']) as List<dynamic>? ?? [];
    return AttendanceHistory(
      records: list.map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>)).toList(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      total: (json['total'] as num?)?.toInt() ?? list.length,
    );
  }
}

class AttendanceOverview {
  final int windowDays;
  final int totalRecords;
  final int present;
  final int late;
  final int halfDay;
  final int absent;
  final int onLeave;
  final int excused;
  final int attended;
  final double attendanceRate;
  final double totalHours;
  final String? lastCheckIn;

  const AttendanceOverview({
    required this.windowDays,
    required this.totalRecords,
    required this.present,
    required this.late,
    required this.halfDay,
    required this.absent,
    required this.onLeave,
    required this.excused,
    required this.attended,
    required this.attendanceRate,
    required this.totalHours,
    this.lastCheckIn,
  });

  factory AttendanceOverview.fromJson(Map<String, dynamic> json) {
    num toNum(dynamic v) => (v as num?) ?? 0;
    return AttendanceOverview(
      windowDays: toNum(json['window_days']).toInt(),
      totalRecords: toNum(json['total_records']).toInt(),
      present: toNum(json['present']).toInt(),
      late: toNum(json['late']).toInt(),
      halfDay: toNum(json['half_day']).toInt(),
      absent: toNum(json['absent']).toInt(),
      onLeave: toNum(json['on_leave']).toInt(),
      excused: toNum(json['excused']).toInt(),
      attended: toNum(json['attended']).toInt(),
      attendanceRate: toNum(json['attendance_rate']).toDouble(),
      totalHours: toNum(json['total_hours']).toDouble(),
      lastCheckIn: json['last_check_in']?.toString(),
    );
  }
}

class AdminStudent {
  final int id;
  final String name;
  final String email;
  final String? department;
  final String? phone;
  final String? jobTitle;
  final bool isActive;
  final String? joiningDate;
  final int? mentorId;
  final String? mentorName;
  final String? createdAt;
  final int? activeProjects;
  final AttendanceOverview? attendanceOverview;

  const AdminStudent({
    required this.id,
    required this.name,
    required this.email,
    this.department,
    this.phone,
    this.jobTitle,
    this.isActive = true,
    this.joiningDate,
    this.mentorId,
    this.mentorName,
    this.createdAt,
    this.activeProjects,
    this.attendanceOverview,
  });

  factory AdminStudent.fromJson(Map<String, dynamic> json) {
    int parseInt(dynamic val) {
      if (val == null) return 0;
      if (val is int) return val;
      return int.tryParse(val.toString()) ?? 0;
    }

    return AdminStudent(
      id: parseInt(json['id']),
      name: json['name']?.toString() ?? 'Student',
      email: json['email']?.toString() ?? '',
      department: json['department']?.toString(),
      phone: json['phone']?.toString(),
      jobTitle: json['job_title']?.toString(),
      isActive: json['is_active'] != false,
      joiningDate: json['joining_date']?.toString(),
      mentorId: json['mentor_id'] != null ? parseInt(json['mentor_id']) : null,
      mentorName: json['mentor_name']?.toString() ?? json['mentor']?['name']?.toString(),
      createdAt: json['created_at']?.toString(),
      activeProjects: json['active_projects'] != null ? parseInt(json['active_projects']) : null,
      attendanceOverview: json['attendance_overview'] is Map<String, dynamic>
          ? AttendanceOverview.fromJson(json['attendance_overview'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AdminStudentListResponse {
  final List<AdminStudent> students;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final Map<String, dynamic>? filters;

  const AdminStudentListResponse({
    required this.students,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    this.filters,
  });

  factory AdminStudentListResponse.fromJson(Map<String, dynamic> json) {
    final rawList = (json['students'] ?? json['items'] ?? json['data']) as List<dynamic>? ?? [];
    return AdminStudentListResponse(
      students: rawList.map((e) => AdminStudent.fromJson(e as Map<String, dynamic>)).toList(),
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 20,
      total: (json['total'] as num?)?.toInt() ?? rawList.length,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      filters: json['filters'] is Map<String, dynamic> ? json['filters'] as Map<String, dynamic> : null,
    );
  }
}

class MonthlySummary {
  final String yearMonth; // YYYY-MM
  final int present;
  final int late;
  final int halfDay;
  final int absent;
  final int onLeave;
  final int attended;
  final int totalDays;
  final double totalHours;
  final double attendanceRate;

  const MonthlySummary({
    required this.yearMonth,
    required this.present,
    required this.late,
    required this.halfDay,
    required this.absent,
    required this.onLeave,
    required this.attended,
    required this.totalDays,
    required this.totalHours,
    required this.attendanceRate,
  });

  factory MonthlySummary.fromJson(Map<String, dynamic> json) {
    num toNum(dynamic v) => (v as num?) ?? 0;
    return MonthlySummary(
      yearMonth: json['year_month']?.toString() ?? '',
      present: toNum(json['present']).toInt(),
      late: toNum(json['late']).toInt(),
      halfDay: toNum(json['half_day']).toInt(),
      absent: toNum(json['absent']).toInt(),
      onLeave: toNum(json['on_leave']).toInt(),
      attended: toNum(json['attended']).toInt(),
      totalDays: toNum(json['total_days']).toInt(),
      totalHours: toNum(json['total_hours']).toDouble(),
      attendanceRate: toNum(json['attendance_rate']).toDouble(),
    );
  }
}

class AttendanceTotals {
  final int present;
  final int late;
  final int halfDay;
  final int absent;
  final int onLeave;
  final int excused;
  final double totalHours;
  final int totalDays;
  final int attended;
  final double attendanceRate;

  const AttendanceTotals({
    required this.present,
    required this.late,
    required this.halfDay,
    required this.absent,
    required this.onLeave,
    required this.excused,
    required this.totalHours,
    required this.totalDays,
    required this.attended,
    required this.attendanceRate,
  });

  factory AttendanceTotals.fromJson(Map<String, dynamic> json) {
    num toNum(dynamic v) => (v as num?) ?? 0;
    return AttendanceTotals(
      present: toNum(json['present']).toInt(),
      late: toNum(json['late']).toInt(),
      halfDay: toNum(json['half_day']).toInt(),
      absent: toNum(json['absent']).toInt(),
      onLeave: toNum(json['on_leave']).toInt(),
      excused: toNum(json['excused']).toInt(),
      totalHours: toNum(json['total_hours']).toDouble(),
      totalDays: toNum(json['total_days']).toInt(),
      attended: toNum(json['attended']).toInt(),
      attendanceRate: toNum(json['attendance_rate']).toDouble(),
    );
  }
}

class AdminStudentAttendanceResponse {
  final AdminStudent student;
  final List<AttendanceRecord> records;
  final List<MonthlySummary> monthlySummary;
  final AttendanceTotals totals;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final Map<String, dynamic>? filters;

  const AdminStudentAttendanceResponse({
    required this.student,
    required this.records,
    required this.monthlySummary,
    required this.totals,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    this.filters,
  });

  factory AdminStudentAttendanceResponse.fromJson(Map<String, dynamic> json) {
    final recList = (json['records'] as List<dynamic>? ?? [])
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();

    final monthList = (json['monthly_summary'] as List<dynamic>? ?? [])
        .map((e) => MonthlySummary.fromJson(e as Map<String, dynamic>))
        .toList();

    return AdminStudentAttendanceResponse(
      student: AdminStudent.fromJson(json['student'] as Map<String, dynamic>? ?? {}),
      records: recList,
      monthlySummary: monthList,
      totals: AttendanceTotals.fromJson(json['totals'] as Map<String, dynamic>? ?? {}),
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 31,
      total: (json['total'] as num?)?.toInt() ?? recList.length,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      filters: json['filters'] is Map<String, dynamic> ? json['filters'] as Map<String, dynamic> : null,
    );
  }
}

class AdminTodayStudentItem {
  final AdminStudent student;
  final String todayStatus;
  final bool isCheckedIn;
  final bool isCheckedOut;
  final AttendanceRecord? attendance;

  const AdminTodayStudentItem({
    required this.student,
    required this.todayStatus,
    required this.isCheckedIn,
    required this.isCheckedOut,
    this.attendance,
  });

  factory AdminTodayStudentItem.fromJson(Map<String, dynamic> json) {
    return AdminTodayStudentItem(
      student: AdminStudent.fromJson(json['student'] as Map<String, dynamic>? ?? {}),
      todayStatus: json['today_status']?.toString() ?? 'not_checked_in',
      isCheckedIn: json['is_checked_in'] == true,
      isCheckedOut: json['is_checked_out'] == true,
      attendance: json['attendance'] is Map<String, dynamic>
          ? AttendanceRecord.fromJson(json['attendance'] as Map<String, dynamic>)
          : null,
    );
  }
}

class AdminTodaySummary {
  final int totalInterns;
  final int checkedIn;
  final int notCheckedIn;
  final int checkedOut;
  final int present;
  final int late;
  final int halfDay;
  final int absent;
  final int onLeave;
  final int excused;
  final int attended;
  final double attendanceRate;

  const AdminTodaySummary({
    required this.totalInterns,
    required this.checkedIn,
    required this.notCheckedIn,
    required this.checkedOut,
    required this.present,
    required this.late,
    required this.halfDay,
    required this.absent,
    required this.onLeave,
    required this.excused,
    required this.attended,
    required this.attendanceRate,
  });

  factory AdminTodaySummary.fromJson(Map<String, dynamic> json) {
    num toNum(dynamic v) => (v as num?) ?? 0;
    return AdminTodaySummary(
      totalInterns: toNum(json['total_interns']).toInt(),
      checkedIn: toNum(json['checked_in']).toInt(),
      notCheckedIn: toNum(json['not_checked_in']).toInt(),
      checkedOut: toNum(json['checked_out']).toInt(),
      present: toNum(json['present']).toInt(),
      late: toNum(json['late']).toInt(),
      halfDay: toNum(json['half_day']).toInt(),
      absent: toNum(json['absent']).toInt(),
      onLeave: toNum(json['on_leave']).toInt(),
      excused: toNum(json['excused']).toInt(),
      attended: toNum(json['attended']).toInt(),
      attendanceRate: toNum(json['attendance_rate']).toDouble(),
    );
  }
}

class AdminTodayStudentsResponse {
  final String today; // YYYY-MM-DD
  final AdminTodaySummary summary;
  final List<AdminTodayStudentItem> students;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final Map<String, dynamic>? filters;

  const AdminTodayStudentsResponse({
    required this.today,
    required this.summary,
    required this.students,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    this.filters,
  });

  factory AdminTodayStudentsResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['students'] as List<dynamic>? ?? [])
        .map((e) => AdminTodayStudentItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return AdminTodayStudentsResponse(
      today: json['today']?.toString() ?? DateTime.now().toIso8601String().substring(0, 10),
      summary: AdminTodaySummary.fromJson(json['summary'] as Map<String, dynamic>? ?? {}),
      students: list,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 20,
      total: (json['total'] as num?)?.toInt() ?? list.length,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      filters: json['filters'] is Map<String, dynamic> ? json['filters'] as Map<String, dynamic> : null,
    );
  }
}

class AttendanceAuditEntry {
  final int id;
  final int? editorId;
  final String editorName;
  final String fieldName;
  final String? oldValue;
  final String? newValue;
  final String reason;
  final String createdAt;

  const AttendanceAuditEntry({
    required this.id,
    this.editorId,
    required this.editorName,
    required this.fieldName,
    this.oldValue,
    this.newValue,
    required this.reason,
    required this.createdAt,
  });

  factory AttendanceAuditEntry.fromJson(Map<String, dynamic> json) {
    return AttendanceAuditEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      editorId: (json['editor_id'] as num?)?.toInt(),
      editorName: json['editor_name']?.toString() ?? 'System / Admin',
      fieldName: json['field_name']?.toString() ?? '',
      oldValue: json['old_value']?.toString(),
      newValue: json['new_value']?.toString(),
      reason: json['reason']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}
