enum LeaveType {
  casual,
  sick,
  earned,
  compOff;

  static LeaveType fromString(String? val) {
    if (val == null) return LeaveType.casual;
    switch (val.toLowerCase().trim()) {
      case 'sick':
        return LeaveType.sick;
      case 'earned':
        return LeaveType.earned;
      case 'comp':
      case 'compoff':
      case 'comp_off':
        return LeaveType.compOff;
      case 'casual':
      default:
        return LeaveType.casual;
    }
  }

  String toApiValue() {
    switch (this) {
      case LeaveType.casual:
        return 'casual';
      case LeaveType.sick:
        return 'sick';
      case LeaveType.earned:
        return 'earned';
      case LeaveType.compOff:
        return 'comp';
    }
  }

  String get label {
    switch (this) {
      case LeaveType.casual:
        return 'Casual Leave';
      case LeaveType.sick:
        return 'Sick Leave';
      case LeaveType.earned:
        return 'Earned Leave';
      case LeaveType.compOff:
        return 'Comp Off';
    }
  }
}

enum LeaveStatus {
  pending,
  approved,
  rejected;

  static LeaveStatus fromString(String? val) {
    if (val == null) return LeaveStatus.pending;
    switch (val.toLowerCase().trim()) {
      case 'approved':
        return LeaveStatus.approved;
      case 'rejected':
        return LeaveStatus.rejected;
      case 'pending':
      default:
        return LeaveStatus.pending;
    }
  }

  String toApiValue() => name;
}

class LeaveModel {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final LeaveType type;
  final DateTime startDate;
  final DateTime endDate;
  final int totalDays;
  final String reason;
  final LeaveStatus status;
  final DateTime requestedAt;
  final String? approvedBy;
  final String? rejectionReason;
  final String emergencyContact;
  final String? attachmentUrl;

  const LeaveModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.reason,
    this.status = LeaveStatus.pending,
    required this.requestedAt,
    this.approvedBy,
    this.rejectionReason,
    this.emergencyContact = '+1 (555) 987-6543',
    this.attachmentUrl,
  });

  factory LeaveModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    final start = parseDate(json['start_date'] ?? json['from_date']);
    final end = parseDate(json['end_date'] ?? json['to_date']);
    int days = (json['total_days'] ?? json['days'] as num?)?.toInt() ?? 0;
    if (days <= 0) {
      days = end.difference(start).inDays + 1;
      if (days <= 0) days = 1;
    }

    return LeaveModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['user']?['id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? json['user']?['name']?.toString() ?? 'Intern',
      userAvatar: json['user_avatar']?.toString() ?? json['user']?['avatar_url']?.toString() ?? '',
      type: LeaveType.fromString(json['leave_type']?.toString() ?? json['type']?.toString()),
      startDate: start,
      endDate: end,
      totalDays: days,
      reason: json['reason']?.toString() ?? '',
      status: LeaveStatus.fromString(json['status']?.toString()),
      requestedAt: parseDate(json['created_at'] ?? json['requested_at']),
      approvedBy: json['approved_by']?.toString() ?? json['reviewer_name']?.toString(),
      rejectionReason: json['rejection_reason']?.toString() ?? json['comment']?.toString(),
      attachmentUrl: json['attachment_url']?.toString() ?? json['attachment']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'leave_type': type.toApiValue(),
      'start_date': startDate.toIso8601String().substring(0, 10),
      'end_date': endDate.toIso8601String().substring(0, 10),
      'reason': reason,
      'status': status.toApiValue(),
    };
  }

  LeaveModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatar,
    LeaveType? type,
    DateTime? startDate,
    DateTime? endDate,
    int? totalDays,
    String? reason,
    LeaveStatus? status,
    DateTime? requestedAt,
    String? approvedBy,
    String? rejectionReason,
    String? emergencyContact,
    String? attachmentUrl,
  }) {
    return LeaveModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      type: type ?? this.type,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      totalDays: totalDays ?? this.totalDays,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      emergencyContact: emergencyContact ?? this.emergencyContact,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
    );
  }
}

class LeaveBalance {
  final int used;
  final int pending;
  final int quota;
  final int remaining;
  final int availableAfterPending;

  // Breakdown fields for UI backwards-compatibility
  final int casualRemaining;
  final int casualTotal;
  final int sickRemaining;
  final int sickTotal;
  final int earnedRemaining;
  final int earnedTotal;
  final int compOffRemaining;
  final int compOffTotal;

  const LeaveBalance({
    this.used = 0,
    this.pending = 0,
    this.quota = 24,
    this.remaining = 24,
    this.availableAfterPending = 24,
    this.casualRemaining = 6,
    this.casualTotal = 6,
    this.sickRemaining = 6,
    this.sickTotal = 6,
    this.earnedRemaining = 10,
    this.earnedTotal = 10,
    this.compOffRemaining = 2,
    this.compOffTotal = 2,
  });

  factory LeaveBalance.fromJson(Map<String, dynamic> json) {
    final used = (json['used'] as num?)?.toInt() ?? 0;
    final pending = (json['pending'] as num?)?.toInt() ?? 0;
    final quota = (json['quota'] as num?)?.toInt() ?? 24;
    final remaining = (json['remaining'] as num?)?.toInt() ?? (quota - used);
    final avail = (json['available_after_pending'] as num?)?.toInt() ?? (remaining - pending);

    return LeaveBalance(
      used: used,
      pending: pending,
      quota: quota,
      remaining: remaining,
      availableAfterPending: avail,
      casualRemaining: (remaining * 0.25).round(),
      casualTotal: (quota * 0.25).round(),
      sickRemaining: (remaining * 0.25).round(),
      sickTotal: (quota * 0.25).round(),
      earnedRemaining: (remaining * 0.40).round(),
      earnedTotal: (quota * 0.40).round(),
      compOffRemaining: (remaining * 0.10).round(),
      compOffTotal: (quota * 0.10).round(),
    );
  }
}
