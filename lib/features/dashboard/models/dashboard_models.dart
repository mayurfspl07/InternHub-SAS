import '../../activity_audit/models/activity_models.dart';

List<T> _parseList<T>(dynamic rawList, T Function(Map<String, dynamic>) mapper) {
  if (rawList is! List) return <T>[];
  final List<T> result = [];
  for (final item in rawList) {
    if (item is Map<String, dynamic>) {
      result.add(mapper(item));
    } else if (item is Map) {
      result.add(mapper(item.cast<String, dynamic>()));
    }
  }
  return result;
}

Map<String, int> _parseCountMap(dynamic v) {
  if (v is! Map) return <String, int>{};
  final map = <String, int>{};
  v.forEach((key, val) {
    if (val is num) {
      map[key.toString()] = val.toInt();
    } else if (val != null) {
      final parsed = int.tryParse(val.toString());
      if (parsed != null) map[key.toString()] = parsed;
    }
  });
  return map;
}

// ==========================================
// 1) INTERN DASHBOARD MODELS
// ==========================================

class InternTodayAttendance {
  final bool hasCheckedIn;
  final bool hasCheckedOut;
  final String status;
  final String? checkIn;
  final String? checkOut;
  final double hoursWorked;
  final String? checkInPhotoUrl;
  final String? checkOutPhotoUrl;
  final String? checkInAddress;

  const InternTodayAttendance({
    this.hasCheckedIn = false,
    this.hasCheckedOut = false,
    this.status = 'absent',
    this.checkIn,
    this.checkOut,
    this.hoursWorked = 0.0,
    this.checkInPhotoUrl,
    this.checkOutPhotoUrl,
    this.checkInAddress,
  });

  factory InternTodayAttendance.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const InternTodayAttendance();
    return InternTodayAttendance(
      hasCheckedIn: json['has_checked_in'] == true || json['check_in'] != null,
      hasCheckedOut: json['has_checked_out'] == true || json['check_out'] != null,
      status: json['status']?.toString() ?? 'absent',
      checkIn: json['check_in']?.toString(),
      checkOut: json['check_out']?.toString(),
      hoursWorked: (json['hours_worked'] as num?)?.toDouble() ?? 0.0,
      checkInPhotoUrl: json['check_in_photo_url']?.toString(),
      checkOutPhotoUrl: json['check_out_photo_url']?.toString(),
      checkInAddress: json['check_in_address']?.toString(),
    );
  }
}

class InternDashboardStats {
  final int presentToday;
  final int totalDaysLogged;
  final double totalHours;
  final int? daysLogged;
  final int activeProjects;
  final int totalProjects;
  final int assignedTasksCount;
  final int completedTasksCount;
  final int openTasks;
  final int overdueTasks;
  final int pendingLeave;
  final int? totalInterns;

  const InternDashboardStats({
    this.presentToday = 0,
    this.totalDaysLogged = 0,
    this.totalHours = 0.0,
    this.daysLogged,
    this.activeProjects = 0,
    this.totalProjects = 0,
    this.assignedTasksCount = 0,
    this.completedTasksCount = 0,
    this.openTasks = 0,
    this.overdueTasks = 0,
    this.pendingLeave = 0,
    this.totalInterns,
  });

  int get effectiveDaysLogged => daysLogged ?? totalDaysLogged;

  double get taskCompletionPercentage {
    if (assignedTasksCount <= 0) return 0.0;
    return (completedTasksCount / assignedTasksCount).clamp(0.0, 1.0);
  }

  factory InternDashboardStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const InternDashboardStats();
    return InternDashboardStats(
      presentToday: (json['present_today'] as num?)?.toInt() ?? 0,
      totalDaysLogged: (json['total_days_logged'] as num?)?.toInt() ?? 0,
      totalHours: (json['total_hours'] as num?)?.toDouble() ?? 0.0,
      daysLogged: (json['days_logged'] as num?)?.toInt(),
      activeProjects: (json['active_projects'] as num?)?.toInt() ?? 0,
      totalProjects: (json['total_projects'] as num?)?.toInt() ?? 0,
      assignedTasksCount: (json['assigned_tasks_count'] ?? json['assigned_tasks'] as num?)?.toInt() ?? 0,
      completedTasksCount: (json['completed_tasks_count'] ?? json['completed_tasks'] as num?)?.toInt() ?? 0,
      openTasks: (json['open_tasks'] as num?)?.toInt() ?? 0,
      overdueTasks: (json['overdue_tasks'] as num?)?.toInt() ?? 0,
      pendingLeave: (json['pending_leave'] as num?)?.toInt() ?? 0,
      totalInterns: (json['total_interns'] as num?)?.toInt(),
    );
  }
}

class InternDashboardProject {
  final int id;
  final String name;
  final String? description;
  final String status;
  final int? mentorId;
  final String? mentorName;
  final int myTasksCount;
  final int completedTasksCount;
  final String? createdAt;

  const InternDashboardProject({
    required this.id,
    required this.name,
    this.description,
    this.status = 'active',
    this.mentorId,
    this.mentorName,
    this.myTasksCount = 0,
    this.completedTasksCount = 0,
    this.createdAt,
  });

  double get progress {
    if (myTasksCount <= 0) return 0.0;
    return (completedTasksCount / myTasksCount).clamp(0.0, 1.0);
  }

  factory InternDashboardProject.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return InternDashboardProject(
      id: parseInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? 'Untitled Project',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'active',
      mentorId: parseInt(json['mentor_id']),
      mentorName: json['mentor_name']?.toString(),
      myTasksCount: (json['my_tasks_count'] ?? json['tasks_count'] as num?)?.toInt() ?? 0,
      completedTasksCount: (json['completed_tasks_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at']?.toString(),
    );
  }
}

class InternDashboardTask {
  final int id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String? deadline;
  final String? dueDate;
  final bool isOverdue;
  final int projectId;
  final String? projectName;
  final String? createdAt;

  const InternDashboardTask({
    required this.id,
    required this.title,
    this.description,
    this.status = 'todo',
    this.priority = 'medium',
    this.deadline,
    this.dueDate,
    this.isOverdue = false,
    required this.projectId,
    this.projectName,
    this.createdAt,
  });

  String? get effectiveDeadline => deadline ?? dueDate;

  factory InternDashboardTask.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return InternDashboardTask(
      id: parseInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? 'Task',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'todo',
      priority: json['priority']?.toString() ?? 'medium',
      deadline: json['deadline']?.toString(),
      dueDate: json['due_date']?.toString(),
      isOverdue: json['is_overdue'] == true,
      projectId: parseInt(json['project_id']) ?? 0,
      projectName: json['project_name']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class DashboardAttendancePoint {
  final String date;
  final double hours;
  final int? present;
  final String status;

  const DashboardAttendancePoint({
    required this.date,
    this.hours = 0.0,
    this.present,
    this.status = 'present',
  });

  factory DashboardAttendancePoint.fromJson(Map<String, dynamic> json) {
    return DashboardAttendancePoint(
      date: json['date']?.toString() ?? '',
      hours: (json['hours'] as num?)?.toDouble() ?? 0.0,
      present: (json['present'] as num?)?.toInt(),
      status: json['status']?.toString() ?? 'present',
    );
  }
}

class InternDashboardLeave {
  final int id;
  final String startDate;
  final String endDate;
  final int days;
  final String leaveType;
  final String status;
  final String? reason;
  final String? createdAt;

  const InternDashboardLeave({
    required this.id,
    required this.startDate,
    required this.endDate,
    this.days = 1,
    this.leaveType = 'casual',
    this.status = 'pending',
    this.reason,
    this.createdAt,
  });

  factory InternDashboardLeave.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return InternDashboardLeave(
      id: parseInt(json['id']) ?? 0,
      startDate: json['start_date']?.toString() ?? '',
      endDate: json['end_date']?.toString() ?? '',
      days: parseInt(json['days'] ?? json['days_count']) ?? 1,
      leaveType: json['leave_type']?.toString() ?? 'casual',
      status: json['status']?.toString() ?? 'pending',
      reason: json['reason']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class DashboardAnnouncement {
  final int id;
  final String title;
  final String? content;
  final String? body;
  final bool isPinned;
  final String? createdAt;

  const DashboardAnnouncement({
    required this.id,
    required this.title,
    this.content,
    this.body,
    this.isPinned = false,
    this.createdAt,
  });

  String get effectiveContent => body ?? content ?? '';

  factory DashboardAnnouncement.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return DashboardAnnouncement(
      id: parseInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? 'Announcement',
      content: json['content']?.toString(),
      body: json['body']?.toString(),
      isPinned: json['is_pinned'] == true,
      createdAt: json['created_at']?.toString(),
    );
  }
}

class InternDashboardData {
  final String role;
  final InternTodayAttendance todayAttendance;
  final int streak;
  final InternDashboardStats stats;
  final List<InternDashboardProject> assignedProjects;
  final List<InternDashboardProject> activeProjects;
  final List<InternDashboardTask> assignedTasks;
  final List<InternDashboardTask> openTasks;
  final List<DashboardAttendancePoint> attendanceChart;
  final Map<String, int> projectStatus;
  final Map<String, int> taskStatus;
  final List<InternDashboardLeave> recentLeaveRequests;
  final List<DashboardAnnouncement> announcements;
  final List<AuditLogEntry> recentActivity;

  const InternDashboardData({
    this.role = 'intern',
    this.todayAttendance = const InternTodayAttendance(),
    this.streak = 0,
    this.stats = const InternDashboardStats(),
    this.assignedProjects = const [],
    this.activeProjects = const [],
    this.assignedTasks = const [],
    this.openTasks = const [],
    this.attendanceChart = const [],
    this.projectStatus = const {},
    this.taskStatus = const {},
    this.recentLeaveRequests = const [],
    this.announcements = const [],
    this.recentActivity = const [],
  });

  factory InternDashboardData.fromJson(Map<String, dynamic> json) {
    final attRaw = json['today_attendance'] ?? json['attendance'];
    final att = attRaw is Map<String, dynamic>
        ? InternTodayAttendance.fromJson(attRaw)
        : const InternTodayAttendance();

    final statsRaw = json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : json;
    final stats = InternDashboardStats.fromJson(statsRaw);

    final assignedProjs = _parseList<InternDashboardProject>(
      json['assigned_projects'] ?? json['projects'],
      InternDashboardProject.fromJson,
    );

    final activeProjs = json['active_projects'] != null
        ? _parseList<InternDashboardProject>(json['active_projects'], InternDashboardProject.fromJson)
        : assignedProjs;

    final assignedTasksList = _parseList<InternDashboardTask>(
      json['assigned_tasks'] ?? json['tasks'],
      InternDashboardTask.fromJson,
    );

    final openTasksList = json['open_tasks'] != null
        ? _parseList<InternDashboardTask>(json['open_tasks'], InternDashboardTask.fromJson)
        : assignedTasksList;

    final chart = _parseList<DashboardAttendancePoint>(
      json['attendance_chart'],
      DashboardAttendancePoint.fromJson,
    );

    final leaves = _parseList<InternDashboardLeave>(
      json['recent_leave_requests'] ?? json['recent_leave'],
      InternDashboardLeave.fromJson,
    );

    final anns = _parseList<DashboardAnnouncement>(
      json['announcements'],
      DashboardAnnouncement.fromJson,
    );

    final activities = _parseList<AuditLogEntry>(
      json['recent_activity'] ?? json['activity'],
      AuditLogEntry.fromJson,
    );

    return InternDashboardData(
      role: json['role']?.toString() ?? 'intern',
      todayAttendance: att,
      streak: (json['streak'] ?? statsRaw['streak'] as num?)?.toInt() ?? 0,
      stats: stats,
      assignedProjects: assignedProjs,
      activeProjects: activeProjs,
      assignedTasks: assignedTasksList,
      openTasks: openTasksList,
      attendanceChart: chart,
      projectStatus: _parseCountMap(json['project_status']),
      taskStatus: _parseCountMap(json['task_status']),
      recentLeaveRequests: leaves,
      announcements: anns,
      recentActivity: activities,
    );
  }
}

// ==========================================
// 2) MENTOR DASHBOARD MODELS
// ==========================================

class MentorDashboardIntern {
  final int userId;
  final String name;
  final String email;
  final String? department;
  final String todayStatus;
  final String? checkIn;
  final String? checkOut;
  final double hoursWorked;
  final String? checkInPhotoUrl;
  final int openTasksCount;
  final int streak;

  const MentorDashboardIntern({
    required this.userId,
    required this.name,
    required this.email,
    this.department,
    this.todayStatus = 'absent',
    this.checkIn,
    this.checkOut,
    this.hoursWorked = 0.0,
    this.checkInPhotoUrl,
    this.openTasksCount = 0,
    this.streak = 0,
  });

  bool get isPresent => todayStatus.toLowerCase() == 'present' || checkIn != null;

  factory MentorDashboardIntern.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return MentorDashboardIntern(
      userId: parseInt(json['user_id'] ?? json['id']) ?? 0,
      name: json['name']?.toString() ?? 'Intern',
      email: json['email']?.toString() ?? '',
      department: json['department']?.toString(),
      todayStatus: json['today_status']?.toString() ?? json['status']?.toString() ?? 'absent',
      checkIn: json['check_in']?.toString(),
      checkOut: json['check_out']?.toString(),
      hoursWorked: (json['hours_worked'] as num?)?.toDouble() ?? 0.0,
      checkInPhotoUrl: json['check_in_photo_url']?.toString(),
      openTasksCount: (json['open_tasks_count'] ?? json['open_tasks'] as num?)?.toInt() ?? 0,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
    );
  }
}

class MentorDashboardProject {
  final int id;
  final String name;
  final String? description;
  final String status;
  final int membersCount;
  final int tasksCount;
  final int completedTasksCount;
  final String? createdAt;

  const MentorDashboardProject({
    required this.id,
    required this.name,
    this.description,
    this.status = 'active',
    this.membersCount = 0,
    this.tasksCount = 0,
    this.completedTasksCount = 0,
    this.createdAt,
  });

  double get progress {
    if (tasksCount <= 0) return 0.0;
    return (completedTasksCount / tasksCount).clamp(0.0, 1.0);
  }

  factory MentorDashboardProject.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return MentorDashboardProject(
      id: parseInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? 'Project',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'active',
      membersCount: (json['members_count'] as num?)?.toInt() ?? 0,
      tasksCount: (json['tasks_count'] as num?)?.toInt() ?? 0,
      completedTasksCount: (json['completed_tasks_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at']?.toString(),
    );
  }
}

class MentorDashboardTask {
  final int id;
  final String title;
  final String? description;
  final int? projectId;
  final String? projectName;
  final int? assignedUserId;
  final String? assignedUserName;
  final String priority;
  final String? deadline;
  final String status;
  final bool isOverdue;

  const MentorDashboardTask({
    required this.id,
    required this.title,
    this.description,
    this.projectId,
    this.projectName,
    this.assignedUserId,
    this.assignedUserName,
    this.priority = 'medium',
    this.deadline,
    this.status = 'todo',
    this.isOverdue = false,
  });

  factory MentorDashboardTask.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return MentorDashboardTask(
      id: parseInt(json['id']) ?? 0,
      title: json['title']?.toString() ?? 'Task',
      description: json['description']?.toString(),
      projectId: parseInt(json['project_id']),
      projectName: json['project_name']?.toString(),
      assignedUserId: parseInt(json['assignee_id']),
      assignedUserName: json['assignee_name']?.toString(),
      priority: json['priority']?.toString() ?? 'medium',
      deadline: json['deadline']?.toString() ?? json['due_date']?.toString(),
      status: json['status']?.toString() ?? 'todo',
      isOverdue: json['is_overdue'] == true,
    );
  }
}

class MentorDashboardLeaveRequest {
  final int id;
  final int userId;
  final String userName;
  final String leaveType;
  final String startDate;
  final String endDate;
  final int days;
  final String? reason;
  final String status;

  const MentorDashboardLeaveRequest({
    required this.id,
    required this.userId,
    required this.userName,
    this.leaveType = 'casual',
    required this.startDate,
    required this.endDate,
    this.days = 1,
    this.reason,
    this.status = 'pending',
  });

  factory MentorDashboardLeaveRequest.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return MentorDashboardLeaveRequest(
      id: parseInt(json['id']) ?? 0,
      userId: parseInt(json['user_id']) ?? 0,
      userName: json['user_name']?.toString() ?? json['name']?.toString() ?? 'User',
      leaveType: json['leave_type']?.toString() ?? 'casual',
      startDate: json['start_date']?.toString() ?? '',
      endDate: json['end_date']?.toString() ?? '',
      days: parseInt(json['days'] ?? json['days_count']) ?? 1,
      reason: json['reason']?.toString(),
      status: json['status']?.toString() ?? 'pending',
    );
  }
}

class MentorDashboardStats {
  final int presentToday;
  final int absentToday;
  final int assignedInternsCount;
  final int activeProjects;
  final int totalProjects;
  final int openTasks;
  final int overdueTasks;
  final int pendingLeave;
  final double totalHours;
  final int daysLogged;
  final int totalInterns;

  const MentorDashboardStats({
    this.presentToday = 0,
    this.absentToday = 0,
    this.assignedInternsCount = 0,
    this.activeProjects = 0,
    this.totalProjects = 0,
    this.openTasks = 0,
    this.overdueTasks = 0,
    this.pendingLeave = 0,
    this.totalHours = 0.0,
    this.daysLogged = 0,
    this.totalInterns = 0,
  });

  factory MentorDashboardStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MentorDashboardStats();
    return MentorDashboardStats(
      presentToday: (json['present_today'] as num?)?.toInt() ?? 0,
      absentToday: (json['absent_today'] as num?)?.toInt() ?? 0,
      assignedInternsCount: (json['assigned_interns_count'] ?? json['assigned_interns'] as num?)?.toInt() ?? 0,
      activeProjects: (json['active_projects'] as num?)?.toInt() ?? 0,
      totalProjects: (json['total_projects'] as num?)?.toInt() ?? 0,
      openTasks: (json['open_tasks'] as num?)?.toInt() ?? 0,
      overdueTasks: (json['overdue_tasks'] as num?)?.toInt() ?? 0,
      pendingLeave: (json['pending_leave'] as num?)?.toInt() ?? 0,
      totalHours: (json['total_hours'] as num?)?.toDouble() ?? 0.0,
      daysLogged: (json['days_logged'] as num?)?.toInt() ?? 0,
      totalInterns: (json['total_interns'] as num?)?.toInt() ?? 0,
    );
  }
}

class MentorDashboardData {
  final String role;
  final MentorDashboardStats stats;
  final List<MentorDashboardIntern> assignedInterns;
  final List<MentorDashboardIntern> presentTodayList;
  final List<MentorDashboardProject> projects;
  final List<MentorDashboardProject> activeProjects;
  final List<MentorDashboardTask> openTasks;
  final List<MentorDashboardLeaveRequest> pendingLeaveRequests;
  final List<DashboardAttendancePoint> attendanceChart;
  final Map<String, int> projectStatus;
  final Map<String, int> taskStatus;
  final List<AuditLogEntry> recentActivity;
  final int? streak;

  const MentorDashboardData({
    this.role = 'mentor',
    this.stats = const MentorDashboardStats(),
    this.assignedInterns = const [],
    this.presentTodayList = const [],
    this.projects = const [],
    this.activeProjects = const [],
    this.openTasks = const [],
    this.pendingLeaveRequests = const [],
    this.attendanceChart = const [],
    this.projectStatus = const {},
    this.taskStatus = const {},
    this.recentActivity = const [],
    this.streak,
  });

  factory MentorDashboardData.fromJson(Map<String, dynamic> json) {
    final stats = MentorDashboardStats.fromJson(
        json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : json);

    final interns = _parseList<MentorDashboardIntern>(
      json['assigned_interns'],
      MentorDashboardIntern.fromJson,
    );

    final presentList = json['present_today_list'] != null
        ? _parseList<MentorDashboardIntern>(json['present_today_list'], MentorDashboardIntern.fromJson)
        : interns.where((i) => i.isPresent).toList();

    final projs = _parseList<MentorDashboardProject>(
      json['projects'] ?? json['active_projects'],
      MentorDashboardProject.fromJson,
    );

    final activeProjs = json['active_projects'] != null
        ? _parseList<MentorDashboardProject>(json['active_projects'], MentorDashboardProject.fromJson)
        : projs;

    final tasks = _parseList<MentorDashboardTask>(
      json['open_tasks'] ?? json['tasks'],
      MentorDashboardTask.fromJson,
    );

    final leaves = _parseList<MentorDashboardLeaveRequest>(
      json['pending_leave_requests'] ?? json['pending_leaves'],
      MentorDashboardLeaveRequest.fromJson,
    );

    final chart = _parseList<DashboardAttendancePoint>(
      json['attendance_chart'],
      DashboardAttendancePoint.fromJson,
    );

    final activities = _parseList<AuditLogEntry>(
      json['recent_activity'] ?? json['activity'],
      AuditLogEntry.fromJson,
    );

    return MentorDashboardData(
      role: json['role']?.toString() ?? 'mentor',
      stats: stats,
      assignedInterns: interns,
      presentTodayList: presentList,
      projects: projs,
      activeProjects: activeProjs,
      openTasks: tasks,
      pendingLeaveRequests: leaves,
      attendanceChart: chart,
      projectStatus: _parseCountMap(json['project_status']),
      taskStatus: _parseCountMap(json['task_status']),
      recentActivity: activities,
      streak: (json['streak'] as num?)?.toInt(),
    );
  }
}

// ==========================================
// 3) ADMIN DASHBOARD MODELS
// ==========================================

class AdminDashboardOrg {
  final int id;
  final String name;
  final String slug;
  final String? type;

  const AdminDashboardOrg({
    required this.id,
    required this.name,
    required this.slug,
    this.type,
  });

  factory AdminDashboardOrg.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AdminDashboardOrg(id: 0, name: '', slug: '');
    }
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return AdminDashboardOrg(
      id: parseInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? '',
      slug: json['slug']?.toString() ?? '',
      type: json['type']?.toString(),
    );
  }
}

class AdminDashboardPresentIntern {
  final int userId;
  final String name;
  final String email;
  final String? department;
  final String status;
  final String? checkIn;
  final String? checkOut;
  final double hoursWorked;
  final String? checkInPhotoUrl;

  const AdminDashboardPresentIntern({
    required this.userId,
    required this.name,
    required this.email,
    this.department,
    this.status = 'present',
    this.checkIn,
    this.checkOut,
    this.hoursWorked = 0.0,
    this.checkInPhotoUrl,
  });

  factory AdminDashboardPresentIntern.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return AdminDashboardPresentIntern(
      userId: parseInt(json['user_id'] ?? json['id']) ?? 0,
      name: json['name']?.toString() ?? 'Intern',
      email: json['email']?.toString() ?? '',
      department: json['department']?.toString(),
      status: json['status']?.toString() ?? 'present',
      checkIn: json['check_in']?.toString(),
      checkOut: json['check_out']?.toString(),
      hoursWorked: (json['hours_worked'] as num?)?.toDouble() ?? 0.0,
      checkInPhotoUrl: json['check_in_photo_url']?.toString(),
    );
  }
}

class AdminDashboardProject {
  final int id;
  final String name;
  final String? description;
  final String status;
  final int? mentorId;
  final String? mentorName;
  final int membersCount;
  final int tasksCount;
  final int completedTasksCount;
  final String? createdAt;

  const AdminDashboardProject({
    required this.id,
    required this.name,
    this.description,
    this.status = 'active',
    this.mentorId,
    this.mentorName,
    this.membersCount = 0,
    this.tasksCount = 0,
    this.completedTasksCount = 0,
    this.createdAt,
  });

  double get progress {
    if (tasksCount <= 0) return 0.0;
    return (completedTasksCount / tasksCount).clamp(0.0, 1.0);
  }

  factory AdminDashboardProject.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return AdminDashboardProject(
      id: parseInt(json['id']) ?? 0,
      name: json['name']?.toString() ?? 'Project',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'active',
      mentorId: parseInt(json['mentor_id']),
      mentorName: json['mentor_name']?.toString(),
      membersCount: (json['members_count'] as num?)?.toInt() ?? 0,
      tasksCount: (json['tasks_count'] as num?)?.toInt() ?? 0,
      completedTasksCount: (json['completed_tasks_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at']?.toString(),
    );
  }
}

class AdminDashboardStats {
  final int presentToday;
  final int absentToday;
  final int onLeaveToday;
  final int totalInterns;
  final int totalMentors;
  final int activeProjects;
  final int totalProjects;
  final int openTasks;
  final int overdueTasks;
  final int pendingLeave;
  final double totalHours;
  final int daysLogged;

  const AdminDashboardStats({
    this.presentToday = 0,
    this.absentToday = 0,
    this.onLeaveToday = 0,
    this.totalInterns = 0,
    this.totalMentors = 0,
    this.activeProjects = 0,
    this.totalProjects = 0,
    this.openTasks = 0,
    this.overdueTasks = 0,
    this.pendingLeave = 0,
    this.totalHours = 0.0,
    this.daysLogged = 0,
  });

  int get totalMembers => totalInterns + totalMentors;

  factory AdminDashboardStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AdminDashboardStats();
    return AdminDashboardStats(
      presentToday: (json['present_today'] as num?)?.toInt() ?? 0,
      absentToday: (json['absent_today'] as num?)?.toInt() ?? 0,
      onLeaveToday: (json['on_leave_today'] as num?)?.toInt() ?? 0,
      totalInterns: (json['total_interns'] ?? json['interns_count'] as num?)?.toInt() ?? 0,
      totalMentors: (json['total_mentors'] ?? json['mentors_count'] as num?)?.toInt() ?? 0,
      activeProjects: (json['active_projects'] as num?)?.toInt() ?? 0,
      totalProjects: (json['total_projects'] as num?)?.toInt() ?? 0,
      openTasks: (json['open_tasks'] as num?)?.toInt() ?? 0,
      overdueTasks: (json['overdue_tasks'] as num?)?.toInt() ?? 0,
      pendingLeave: (json['pending_leave'] as num?)?.toInt() ?? 0,
      totalHours: (json['total_hours'] as num?)?.toDouble() ?? 0.0,
      daysLogged: (json['days_logged'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminDashboardData {
  final String role;
  final AdminDashboardOrg organization;
  final AdminDashboardStats stats;
  final List<AdminDashboardPresentIntern> presentTodayList;
  final List<MentorDashboardTask> openTasks;
  final List<AdminDashboardProject> activeProjects;
  final List<MentorDashboardLeaveRequest> pendingLeaveRequests;
  final List<DashboardAttendancePoint> attendanceChart;
  final Map<String, int> projectStatus;
  final Map<String, int> taskStatus;
  final List<AuditLogEntry> recentActivity;
  final int? streak;

  const AdminDashboardData({
    this.role = 'admin',
    this.organization = const AdminDashboardOrg(id: 0, name: '', slug: ''),
    this.stats = const AdminDashboardStats(),
    this.presentTodayList = const [],
    this.openTasks = const [],
    this.activeProjects = const [],
    this.pendingLeaveRequests = const [],
    this.attendanceChart = const [],
    this.projectStatus = const {},
    this.taskStatus = const {},
    this.recentActivity = const [],
    this.streak,
  });

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    final org = AdminDashboardOrg.fromJson(
        json['organization'] is Map<String, dynamic> ? json['organization'] as Map<String, dynamic> : null);

    final stats = AdminDashboardStats.fromJson(
        json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : json);

    final presentList = _parseList<AdminDashboardPresentIntern>(
      json['present_today_list'] ?? json['present_today'],
      AdminDashboardPresentIntern.fromJson,
    );

    final tasks = _parseList<MentorDashboardTask>(
      json['open_tasks'] ?? json['tasks'],
      MentorDashboardTask.fromJson,
    );

    final projects = _parseList<AdminDashboardProject>(
      json['active_projects'] ?? json['projects'],
      AdminDashboardProject.fromJson,
    );

    final leaves = _parseList<MentorDashboardLeaveRequest>(
      json['pending_leave_requests'] ?? json['pending_leaves'],
      MentorDashboardLeaveRequest.fromJson,
    );

    final chart = _parseList<DashboardAttendancePoint>(
      json['attendance_chart'],
      DashboardAttendancePoint.fromJson,
    );

    final activities = _parseList<AuditLogEntry>(
      json['recent_activity'] ?? json['activity'],
      AuditLogEntry.fromJson,
    );

    return AdminDashboardData(
      role: json['role']?.toString() ?? 'admin',
      organization: org,
      stats: stats,
      presentTodayList: presentList,
      openTasks: tasks,
      activeProjects: projects,
      pendingLeaveRequests: leaves,
      attendanceChart: chart,
      projectStatus: _parseCountMap(json['project_status']),
      taskStatus: _parseCountMap(json['task_status']),
      recentActivity: activities,
      streak: (json['streak'] as num?)?.toInt(),
    );
  }
}
