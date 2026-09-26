import 'dart:math';
import 'user_model.dart';
import 'leave_model.dart';

class ProfileOverviewProject {
  final int id;
  final String name;
  final String status;
  final double progress;
  final String? startDate;
  final String? endDate;
  final int? internCount;

  const ProfileOverviewProject({
    required this.id,
    required this.name,
    required this.status,
    required this.progress,
    this.startDate,
    this.endDate,
    this.internCount,
  });

  // Backward compatibility getters
  String get title => name;
  int get totalTasks => internCount ?? 0;

  factory ProfileOverviewProject.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    double toDouble(dynamic v, [double fallback = 0.0]) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? fallback;
    }

    return ProfileOverviewProject(
      id: toInt(json['id']),
      name: json['name']?.toString() ?? json['title']?.toString() ?? 'Project',
      status: json['status']?.toString() ?? 'active',
      progress: toDouble(json['progress']),
      startDate: json['start_date']?.toString(),
      endDate: json['end_date']?.toString(),
      internCount: json['intern_count'] != null ? toInt(json['intern_count']) : null,
    );
  }
}

class ProfileOverviewTask {
  final int id;
  final String title;
  final int projectId;
  final String? projectName;
  final String status;
  final String priority;
  final String? dueDate;

  const ProfileOverviewTask({
    required this.id,
    required this.title,
    required this.projectId,
    this.projectName,
    required this.status,
    required this.priority,
    this.dueDate,
  });

  bool get isActive => isTaskActive(status);

  factory ProfileOverviewTask.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    return ProfileOverviewTask(
      id: toInt(json['id']),
      title: json['title']?.toString() ?? 'Task',
      projectId: toInt(json['project_id']),
      projectName: json['project_name']?.toString(),
      status: json['status']?.toString() ?? 'todo',
      priority: json['priority']?.toString() ?? 'medium',
      dueDate: json['due_date']?.toString(),
    );
  }
}

class ProfileOverviewAttendance {
  final String date;
  final String? checkIn;
  final String? checkOut;
  final double? hours;
  final String status;

  const ProfileOverviewAttendance({
    required this.date,
    this.checkIn,
    this.checkOut,
    this.hours,
    required this.status,
  });

  String get locationAddress => checkIn != null
      ? 'In: $checkIn${checkOut != null ? " • Out: $checkOut" : ""}'
      : 'Office / Remote';

  factory ProfileOverviewAttendance.fromJson(Map<String, dynamic> json) {
    double? toDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return ProfileOverviewAttendance(
      date: json['date']?.toString() ?? '',
      checkIn: json['check_in']?.toString(),
      checkOut: json['check_out']?.toString(),
      hours: toDouble(json['hours'] ?? json['total_hours']),
      status: json['status']?.toString() ?? 'present',
    );
  }
}

class ProfileOverviewIntern {
  final int id;
  final String name;
  final String email;
  final bool isActive;
  final String? department;

  const ProfileOverviewIntern({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    this.department,
  });

  factory ProfileOverviewIntern.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    return ProfileOverviewIntern(
      id: toInt(json['id']),
      name: json['name']?.toString() ?? 'Intern',
      email: json['email']?.toString() ?? '',
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      department: json['department']?.toString(),
    );
  }
}

class ProfileLeaveSummary {
  final int total;
  final int approved;
  final int rejected;
  final int pending;
  final int daysTaken;

  const ProfileLeaveSummary({
    required this.total,
    required this.approved,
    required this.rejected,
    required this.pending,
    required this.daysTaken,
  });

  factory ProfileLeaveSummary.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    return ProfileLeaveSummary(
      total: toInt(json['total'] ?? json['leave_total'] ?? json['total_leaves']),
      approved: toInt(json['approved'] ?? json['leave_approved'] ?? json['approved_leaves']),
      rejected: toInt(json['rejected'] ?? json['leave_rejected'] ?? json['rejected_leaves']),
      pending: toInt(json['pending'] ?? json['leave_pending'] ?? json['pending_leaves']),
      daysTaken: toInt(json['days_taken'] ?? json['leave_days_taken'] ?? json['days']),
    );
  }
}

class ProfileAttendanceSummary {
  final int present;
  final int late;
  final int halfDay;
  final int onLeave;
  final int absent;
  final int absentIncludingLeave;

  const ProfileAttendanceSummary({
    required this.present,
    required this.late,
    required this.halfDay,
    required this.onLeave,
    required this.absent,
    required this.absentIncludingLeave,
  });
}

class UserProfileOverview {
  final UserModel user;
  final Map<String, dynamic> stats;
  final List<ProfileOverviewProject> projects;
  final List<ProfileOverviewTask> tasks;
  final List<ProfileOverviewAttendance> attendance;
  final List<ProfileOverviewIntern> interns;
  final List<LeaveModel> leaveRequests;
  final ProfileLeaveSummary? leaveSummary;
  final LeaveBalance? leaveBalance;

  const UserProfileOverview({
    required this.user,
    this.stats = const {},
    this.projects = const [],
    this.tasks = const [],
    this.attendance = const [],
    this.interns = const [],
    this.leaveRequests = const [],
    this.leaveSummary,
    this.leaveBalance,
  });

  // Client aggregations
  List<ProfileOverviewTask> get activeTasks => tasks.where((t) => isTaskActive(t.status)).toList();

  int get completedTasksCount {
    if (stats['completed_tasks'] != null) {
      return int.tryParse(stats['completed_tasks'].toString()) ?? 0;
    }
    return tasks.length - activeTasks.length;
  }

  int get totalProjectsCount {
    if (stats['projects'] != null) {
      return int.tryParse(stats['projects'].toString()) ?? 0;
    }
    return projects.length;
  }

  int get activeTasksCount {
    if (stats['active_tasks'] != null) {
      return int.tryParse(stats['active_tasks'].toString()) ?? 0;
    }
    return activeTasks.length;
  }

  ProfileLeaveSummary get resolvedLeaveSummary {
    if (leaveSummary != null) return leaveSummary!;
    final fromStats = profileLeaveSummaryFromStats(stats);
    if (fromStats != null) return fromStats;
    return summarizeLeaveRequests(leaveRequests);
  }

  ProfileAttendanceSummary get resolvedAttendanceSummary {
    return summarizeProfileAttendance(attendance, stats, leaveRequests);
  }

  factory UserProfileOverview.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : json;
    final user = UserModel.fromJson(userJson);

    final stats = json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : <String, dynamic>{};

    List<ProfileOverviewProject> projs = [];
    if (json['projects'] is List) {
      projs = (json['projects'] as List)
          .whereType<Map<String, dynamic>>()
          .map((p) => ProfileOverviewProject.fromJson(p))
          .toList();
    }

    List<ProfileOverviewTask> ts = [];
    if (json['tasks'] is List) {
      ts = (json['tasks'] as List)
          .whereType<Map<String, dynamic>>()
          .map((t) => ProfileOverviewTask.fromJson(t))
          .toList();
    }

    List<ProfileOverviewAttendance> atts = [];
    if (json['attendance'] is List) {
      atts = (json['attendance'] as List)
          .whereType<Map<String, dynamic>>()
          .map((a) => ProfileOverviewAttendance.fromJson(a))
          .toList();
    }

    List<ProfileOverviewIntern> itns = [];
    if (json['interns'] is List) {
      itns = (json['interns'] as List)
          .whereType<Map<String, dynamic>>()
          .map((u) => ProfileOverviewIntern.fromJson(u))
          .toList();
    }

    List<LeaveModel> leaves = [];
    if (json['leave_requests'] is List) {
      leaves = (json['leave_requests'] as List)
          .whereType<Map<String, dynamic>>()
          .map((l) => LeaveModel.fromJson(l))
          .toList();
    }

    ProfileLeaveSummary? summary;
    if (json['leave_summary'] is Map<String, dynamic>) {
      summary = ProfileLeaveSummary.fromJson(json['leave_summary'] as Map<String, dynamic>);
    }

    LeaveBalance? balance;
    if (json['leave_balance'] is Map<String, dynamic>) {
      balance = LeaveBalance.fromJson(json['leave_balance'] as Map<String, dynamic>);
    }

    return UserProfileOverview(
      user: user,
      stats: stats,
      projects: projs,
      tasks: ts,
      attendance: atts,
      interns: itns,
      leaveRequests: leaves,
      leaveSummary: summary,
      leaveBalance: balance,
    );
  }
}

// Helpers

bool isTaskActive(String? status) {
  if (status == null) return true;
  final s = status.toLowerCase().trim();
  return s != 'done' && s != 'completed';
}

String nationalPhoneDigits(String? phone) {
  if (phone == null) return '';
  final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.length == 12 && digitsOnly.startsWith('91')) {
    return digitsOnly.substring(2);
  }
  if (digitsOnly.length == 11 && digitsOnly.startsWith('0')) {
    return digitsOnly.substring(1);
  }
  return digitsOnly;
}

String? normalizePhoneForSubmit(String? input) {
  if (input == null) return null;
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('+')) return trimmed;
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  return '+91 $digits';
}

String formatSkills(dynamic skills) {
  if (skills == null) return '';
  if (skills is List) {
    return skills.map((s) => s.toString().trim()).where((s) => s.isNotEmpty).join(', ');
  }
  return skills.toString();
}

List<String> skillList(dynamic skills) {
  if (skills == null) return [];
  if (skills is List) {
    return skills.map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList();
  }
  return skills
      .toString()
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

ProfileLeaveSummary? profileLeaveSummaryFromStats(Map<String, dynamic> stats) {
  int toInt(dynamic v) => v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

  final hasLeaveData = stats.keys.any((k) => k.startsWith('leave_') || k.contains('leaves'));
  if (!hasLeaveData) return null;

  return ProfileLeaveSummary(
    total: toInt(stats['leave_total'] ?? stats['total_leaves'] ?? stats['leaves_total']),
    approved: toInt(stats['leave_approved'] ?? stats['approved_leaves']),
    rejected: toInt(stats['leave_rejected'] ?? stats['rejected_leaves']),
    pending: toInt(stats['leave_pending'] ?? stats['pending_leaves']),
    daysTaken: toInt(stats['leave_days_taken'] ?? stats['days_taken'] ?? stats['leave_days']),
  );
}

ProfileLeaveSummary summarizeLeaveRequests(List<LeaveModel> requests) {
  int total = requests.length;
  int approved = 0;
  int rejected = 0;
  int pending = 0;
  int daysTaken = 0;

  for (final r in requests) {
    final s = r.status.toLowerCase().trim();
    if (s == 'approved') {
      approved++;
      daysTaken += r.days;
    } else if (s == 'rejected') {
      rejected++;
    } else {
      pending++;
    }
  }

  return ProfileLeaveSummary(
    total: total,
    approved: approved,
    rejected: rejected,
    pending: pending,
    daysTaken: daysTaken,
  );
}

int approvedLeaveDaysInRange(List<LeaveModel> requests, DateTime from, DateTime to) {
  int count = 0;
  for (final r in requests) {
    if (r.status.toLowerCase().trim() == 'approved') {
      final start = DateTime.tryParse(r.start_date);
      final end = DateTime.tryParse(r.end_date) ?? start;
      if (start != null && end != null) {
        if (!end.isBefore(from) && !start.isAfter(to)) {
          count += r.days;
        }
      }
    }
  }
  return count;
}

ProfileAttendanceSummary summarizeProfileAttendance(
  List<ProfileOverviewAttendance> attendance,
  Map<String, dynamic> stats,
  List<LeaveModel> leaveRequests,
) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = today.subtract(const Duration(days: 30));

  final recordsInWindow = attendance.where((a) {
    final dt = DateTime.tryParse(a.date);
    if (dt == null) return false;
    final clean = DateTime(dt.year, dt.month, dt.day);
    return !clean.isBefore(from) && !clean.isAfter(today);
  }).toList();

  int toInt(dynamic v) => v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '') ?? 0);

  int present = 0;
  int late = 0;
  int halfDay = 0;
  int onLeave = 0;
  int absent = 0;

  if (recordsInWindow.isNotEmpty) {
    for (final a in recordsInWindow) {
      final s = a.status.toLowerCase().trim();
      switch (s) {
        case 'present':
          present++;
          break;
        case 'late':
          late++;
          break;
        case 'half_day':
        case 'halfday':
          halfDay++;
          break;
        case 'on_leave':
        case 'leave':
          onLeave++;
          break;
        case 'absent':
          absent++;
          break;
      }
    }
  } else {
    present = toInt(stats['present_30d'] ?? stats['present_14d']);
    late = toInt(stats['late_30d'] ?? stats['late_14d']);
    halfDay = toInt(stats['half_day_30d'] ?? stats['half_day_14d']);
    onLeave = toInt(stats['on_leave_30d'] ?? stats['on_leave_14d']);
    absent = toInt(stats['absent_30d'] ?? stats['absent_14d']);
  }

  final leaveDays = approvedLeaveDaysInRange(leaveRequests, from, today);
  final absentIncludingLeave = max(absent + onLeave, leaveDays);

  return ProfileAttendanceSummary(
    present: present,
    late: late,
    halfDay: halfDay,
    onLeave: onLeave,
    absent: absent,
    absentIncludingLeave: absentIncludingLeave,
  );
}
