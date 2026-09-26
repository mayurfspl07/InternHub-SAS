enum OrgSmtpEncryption {
  tls,
  ssl,
  none;

  String toApi() {
    switch (this) {
      case OrgSmtpEncryption.ssl:
        return 'ssl';
      case OrgSmtpEncryption.none:
        return 'none';
      case OrgSmtpEncryption.tls:
        return 'tls';
    }
  }

  static OrgSmtpEncryption fromString(dynamic value) {
    final str = value?.toString().toLowerCase().trim();
    if (str == 'ssl') return OrgSmtpEncryption.ssl;
    if (str == 'none') return OrgSmtpEncryption.none;
    return OrgSmtpEncryption.tls;
  }
}

class OrgSmtpConfig {
  final int? id;
  final int? organizationId;
  final bool isEnabled;
  final String host;
  final int port;
  final String username;
  final String? password;
  final bool hasPassword;
  final String senderEmail;
  final String senderName;
  final OrgSmtpEncryption encryption;
  final bool notifyWelcome;
  final bool notifyLeaveRequest;
  final bool notifyLeaveDecision;
  final bool notifyAssignmentNew;
  final bool notifyAssignmentSubmit;
  final bool notifyAssignmentGrade;
  final bool notifyTaskAssigned;
  final bool notifyAttendanceAlert;
  final String? createdAt;
  final String? updatedAt;

  const OrgSmtpConfig({
    this.id,
    this.organizationId,
    this.isEnabled = false,
    this.host = '',
    this.port = 587,
    this.username = '',
    this.password,
    this.hasPassword = false,
    this.senderEmail = '',
    this.senderName = '',
    this.encryption = OrgSmtpEncryption.tls,
    this.notifyWelcome = true,
    this.notifyLeaveRequest = true,
    this.notifyLeaveDecision = true,
    this.notifyAssignmentNew = true,
    this.notifyAssignmentSubmit = true,
    this.notifyAssignmentGrade = true,
    this.notifyTaskAssigned = true,
    this.notifyAttendanceAlert = false,
    this.createdAt,
    this.updatedAt,
  });

  factory OrgSmtpConfig.fromJson(Map<String, dynamic> raw) {
    return normalizeOrgSmtpConfig(raw);
  }

  OrgSmtpConfig copyWith({
    int? id,
    int? organizationId,
    bool? isEnabled,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? hasPassword,
    String? senderEmail,
    String? senderName,
    OrgSmtpEncryption? encryption,
    bool? notifyWelcome,
    bool? notifyLeaveRequest,
    bool? notifyLeaveDecision,
    bool? notifyAssignmentNew,
    bool? notifyAssignmentSubmit,
    bool? notifyAssignmentGrade,
    bool? notifyTaskAssigned,
    bool? notifyAttendanceAlert,
    String? createdAt,
    String? updatedAt,
  }) {
    return OrgSmtpConfig(
      id: id ?? this.id,
      organizationId: organizationId ?? this.organizationId,
      isEnabled: isEnabled ?? this.isEnabled,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      hasPassword: hasPassword ?? this.hasPassword,
      senderEmail: senderEmail ?? this.senderEmail,
      senderName: senderName ?? this.senderName,
      encryption: encryption ?? this.encryption,
      notifyWelcome: notifyWelcome ?? this.notifyWelcome,
      notifyLeaveRequest: notifyLeaveRequest ?? this.notifyLeaveRequest,
      notifyLeaveDecision: notifyLeaveDecision ?? this.notifyLeaveDecision,
      notifyAssignmentNew: notifyAssignmentNew ?? this.notifyAssignmentNew,
      notifyAssignmentSubmit: notifyAssignmentSubmit ?? this.notifyAssignmentSubmit,
      notifyAssignmentGrade: notifyAssignmentGrade ?? this.notifyAssignmentGrade,
      notifyTaskAssigned: notifyTaskAssigned ?? this.notifyTaskAssigned,
      notifyAttendanceAlert: notifyAttendanceAlert ?? this.notifyAttendanceAlert,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

OrgSmtpConfig normalizeOrgSmtpConfig(dynamic raw) {
  if (raw is! Map) return const OrgSmtpConfig();
  final Map<String, dynamic> json = raw['config'] is Map
      ? (raw['config'] as Map).cast<String, dynamic>()
      : raw['data'] is Map
          ? (raw['data'] as Map).cast<String, dynamic>()
          : raw.cast<String, dynamic>();

  int? parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  final id = parseInt(json['id']);
  final orgId = parseInt(json['organization_id']);
  final isEnabled = json['is_enabled'] == true;
  final host = json['host']?.toString() ?? '';
  final username = json['username']?.toString() ?? '';
  final password = json['password']?.toString();
  final hasPassword = json['has_password'] == true ||
      (password != null && password.isNotEmpty && !password.contains('•'));

  int port = parseInt(json['port']) ?? 0;
  if (port <= 0) {
    port = (host.isNotEmpty || username.isNotEmpty || id != null || hasPassword) ? 587 : 0;
  }

  final encryption = OrgSmtpEncryption.fromString(json['encryption']);

  return OrgSmtpConfig(
    id: id,
    organizationId: orgId,
    isEnabled: isEnabled,
    host: host,
    port: port,
    username: username,
    password: password,
    hasPassword: hasPassword,
    senderEmail: json['sender_email']?.toString() ?? '',
    senderName: json['sender_name']?.toString() ?? '',
    encryption: encryption,
    notifyWelcome: json['notify_welcome'] == true,
    notifyLeaveRequest: json['notify_leave_request'] == true,
    notifyLeaveDecision: json['notify_leave_decision'] == true,
    notifyAssignmentNew: json['notify_assignment_new'] == true,
    notifyAssignmentSubmit: json['notify_assignment_submit'] == true,
    notifyAssignmentGrade: json['notify_assignment_grade'] == true,
    notifyTaskAssigned: json['notify_task_assigned'] == true,
    notifyAttendanceAlert: json['notify_attendance_alert'] == true,
    createdAt: json['created_at']?.toString(),
    updatedAt: json['updated_at']?.toString(),
  );
}

class SmtpDeliveryLog {
  final int id;
  final String recipientEmail;
  final String? recipientName;
  final String subject;
  final String emailType;
  final String status;
  final String sentAt;
  final String? errorMessage;

  const SmtpDeliveryLog({
    required this.id,
    required this.recipientEmail,
    this.recipientName,
    required this.subject,
    required this.emailType,
    required this.status,
    required this.sentAt,
    this.errorMessage,
  });

  bool get isSent => status.toLowerCase() == 'sent';
  bool get isFailed => status.toLowerCase() == 'failed';
  bool get isSimulated => status.toLowerCase() == 'simulated';

  String get typeDisplay {
    switch (emailType.toLowerCase()) {
      case 'welcome':
        return 'Welcome';
      case 'leave_request':
        return 'Leave Req';
      case 'leave_decision':
        return 'Leave Dec';
      case 'assignment_new':
        return 'New Task/Assign';
      case 'assignment_submit':
        return 'Submitted';
      case 'assignment_grade':
        return 'Graded';
      case 'task_assigned':
        return 'Task Assigned';
      case 'test':
        return 'Test';
      default:
        return emailType.replaceAll('_', ' ');
    }
  }

  factory SmtpDeliveryLog.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return SmtpDeliveryLog(
      id: parseInt(json['id']) ?? 0,
      recipientEmail: json['recipient_email']?.toString() ?? '',
      recipientName: json['recipient_name']?.toString(),
      subject: json['subject']?.toString() ?? '(No subject)',
      emailType: json['email_type']?.toString() ?? 'general',
      status: json['status']?.toString() ?? 'sent',
      sentAt: json['sent_at']?.toString() ?? json['created_at']?.toString() ?? '',
      errorMessage: json['error_message']?.toString(),
    );
  }
}

class SmtpDeliveryLogsResponse {
  final List<SmtpDeliveryLog> logs;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  const SmtpDeliveryLogsResponse({
    this.logs = const [],
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.totalPages = 1,
  });

  factory SmtpDeliveryLogsResponse.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    final rawLogs = json['logs'] ?? json['items'] ?? json['data'];
    final List<SmtpDeliveryLog> items = [];
    if (rawLogs is List) {
      for (final item in rawLogs) {
        if (item is Map) {
          items.add(SmtpDeliveryLog.fromJson(item.cast<String, dynamic>()));
        }
      }
    }

    final page = parseInt(json['page']) ?? 1;
    final pageSize = parseInt(json['page_size'] ?? json['per_page']) ?? 20;
    final total = parseInt(json['total']) ?? items.length;
    final totalPages = parseInt(json['total_pages']) ??
        ((total / (pageSize > 0 ? pageSize : 1)).ceil().clamp(1, 99999));

    return SmtpDeliveryLogsResponse(
      logs: items,
      page: page,
      pageSize: pageSize,
      total: total,
      totalPages: totalPages,
    );
  }
}

class TestOrgSmtpResponse {
  final bool success;
  final String message;
  final String? error;

  const TestOrgSmtpResponse({
    required this.success,
    required this.message,
    this.error,
  });

  factory TestOrgSmtpResponse.fromJson(Map<String, dynamic> json) {
    return TestOrgSmtpResponse(
      success: json['success'] == true || json['ok'] == true,
      message: json['message']?.toString() ?? (json['success'] == true ? 'Test email sent successfully' : 'Failed to send test email'),
      error: json['error']?.toString(),
    );
  }
}
