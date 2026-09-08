import '../../core/api/api_config.dart';

enum AttendanceStatus {
  present,
  late,
  halfDay,
  absent,
  leave,
  excused;

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
      case 'leave':
        return AttendanceStatus.leave;
      case 'excused':
        return AttendanceStatus.excused;
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
        return 'leave';
      case AttendanceStatus.excused:
        return 'excused';
      case AttendanceStatus.present:
        return 'present';
    }
  }
}

class AttendanceRecord {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final DateTime date;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final AttendanceStatus status;
  final double latitude;
  final double longitude;
  final String locationAddress;
  final bool isInsideGeofence;
  final String? selfieUrl;
  final String? checkOutPhotoUrl;
  final String? overrideReason;
  final String? overriddenBy;
  final Duration? workingHours;

  const AttendanceRecord({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.date,
    required this.checkInTime,
    this.checkOutTime,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.locationAddress,
    this.isInsideGeofence = true,
    this.selfieUrl,
    this.checkOutPhotoUrl,
    this.overrideReason,
    this.overriddenBy,
    this.workingHours,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    DateTime? parseNullableDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    Duration? parseDuration(dynamic v) {
      if (v == null) return null;
      if (v is num) {
        return Duration(minutes: (v * 60).round());
      }
      if (v is String) {
        final hours = double.tryParse(v);
        if (hours != null) {
          return Duration(minutes: (hours * 60).round());
        }
      }
      return null;
    }

    String? resolveUrl(dynamic raw) {
      if (raw == null) return null;
      final s = raw.toString().trim();
      if (s.isEmpty) return null;
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
      return ApiConfig.url(s);
    }

    final rawCheckInPhoto = json['checkin_photo_path'] ??
        json['check_in_photo_url'] ??
        json['selfie_url'] ??
        json['photo'] ??
        json['check_in_photo'];

    final rawCheckOutPhoto = json['checkout_photo_path'] ??
        json['check_out_photo_url'] ??
        json['check_out_photo'];

    final rawAddress = json['location_address'] ??
        json['checkin_location'] ??
        json['address'] ??
        'Recorded Location';

    return AttendanceRecord(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? json['user']?['name']?.toString() ?? 'Intern',
      userAvatar: json['user_avatar']?.toString() ?? json['user']?['avatar_url']?.toString() ?? '',
      date: parseDate(json['date']),
      checkInTime: parseDate(json['check_in'] ?? json['check_in_time'] ?? json['created_at']),
      checkOutTime: parseNullableDate(json['check_out'] ?? json['check_out_time']),
      status: AttendanceStatus.fromString(json['status']?.toString() ?? json['status_override']?.toString()),
      latitude: (json['latitude'] ?? json['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] ?? json['lng'] as num?)?.toDouble() ?? 0.0,
      locationAddress: rawAddress.toString(),
      isInsideGeofence: json['is_inside_geofence'] is bool ? json['is_inside_geofence'] as bool : true,
      selfieUrl: resolveUrl(rawCheckInPhoto),
      checkOutPhotoUrl: resolveUrl(rawCheckOutPhoto),
      overrideReason: json['override_reason']?.toString() ?? json['reason']?.toString(),
      overriddenBy: json['overridden_by']?.toString(),
      workingHours: parseDuration(json['working_hours'] ?? json['hours_worked']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'user_name': userName,
      'date': date.toIso8601String(),
      'check_in': checkInTime.toIso8601String(),
      'check_out': checkOutTime?.toIso8601String(),
      'status': status.toApiValue(),
      'latitude': latitude,
      'longitude': longitude,
      'location_address': locationAddress,
      'selfie_url': selfieUrl,
      'check_out_photo': checkOutPhotoUrl,
      'override_reason': overrideReason,
    };
  }

  AttendanceRecord copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatar,
    DateTime? date,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    AttendanceStatus? status,
    double? latitude,
    double? longitude,
    String? locationAddress,
    bool? isInsideGeofence,
    String? selfieUrl,
    String? checkOutPhotoUrl,
    String? overrideReason,
    String? overriddenBy,
    Duration? workingHours,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      date: date ?? this.date,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      status: status ?? this.status,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAddress: locationAddress ?? this.locationAddress,
      isInsideGeofence: isInsideGeofence ?? this.isInsideGeofence,
      selfieUrl: selfieUrl ?? this.selfieUrl,
      checkOutPhotoUrl: checkOutPhotoUrl ?? this.checkOutPhotoUrl,
      overrideReason: overrideReason ?? this.overrideReason,
      overriddenBy: overriddenBy ?? this.overriddenBy,
      workingHours: workingHours ?? this.workingHours,
    );
  }
}
