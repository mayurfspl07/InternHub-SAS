import 'user_model.dart';
import 'project_model.dart';
import 'leave_model.dart';
import 'cohort_model.dart';

class InternDashboardData {
  final int totalDaysLogged;
  final double totalHours;
  final int activeProjects;
  final int totalProjects;
  final int assignedTasks;
  final int completedTasks;
  final int openTasks;
  final int overdueTasks;
  final int pendingLeave;
  final int streakDays;
  final bool isCheckedInToday;
  final DateTime? todayCheckIn;
  final DateTime? todayCheckOut;
  final double todayHours;
  final List<ProjectModel> projects;
  final List<TaskModel> tasks;
  final List<LeaveModel> recentLeaves;
  final List<AnnouncementModel> announcements;
  final List<ActivityLogItem> recentActivity;
  final List<Map<String, dynamic>> attendanceChart;

  const InternDashboardData({
    this.totalDaysLogged = 0,
    this.totalHours = 0.0,
    this.activeProjects = 0,
    this.totalProjects = 0,
    this.assignedTasks = 0,
    this.completedTasks = 0,
    this.openTasks = 0,
    this.overdueTasks = 0,
    this.pendingLeave = 0,
    this.streakDays = 0,
    this.isCheckedInToday = false,
    this.todayCheckIn,
    this.todayCheckOut,
    this.todayHours = 0.0,
    this.projects = const [],
    this.tasks = const [],
    this.recentLeaves = const [],
    this.announcements = const [],
    this.recentActivity = const [],
    this.attendanceChart = const [],
  });

  factory InternDashboardData.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : json;
    final att = json['attendance'] is Map<String, dynamic> ? json['attendance'] as Map<String, dynamic> : {};

    DateTime? parseNullableDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    List<ProjectModel> projs = [];
    if (json['projects'] is List) {
      projs = (json['projects'] as List)
          .whereType<Map<String, dynamic>>()
          .map((p) => ProjectModel.fromJson(p))
          .toList();
    }

    List<TaskModel> ts = [];
    if (json['tasks'] is List) {
      ts = (json['tasks'] as List)
          .whereType<Map<String, dynamic>>()
          .map((t) => TaskModel.fromJson(t))
          .toList();
    }

    List<LeaveModel> leaves = [];
    if (json['recent_leave'] is List) {
      leaves = (json['recent_leave'] as List)
          .whereType<Map<String, dynamic>>()
          .map((l) => LeaveModel.fromJson(l))
          .toList();
    }

    List<AnnouncementModel> anns = [];
    if (json['announcements'] is List) {
      anns = (json['announcements'] as List)
          .whereType<Map<String, dynamic>>()
          .map((a) => AnnouncementModel.fromJson(a))
          .toList();
    }

    List<ActivityLogItem> acts = [];
    if (json['recent_activity'] is List) {
      acts = (json['recent_activity'] as List)
          .whereType<Map<String, dynamic>>()
          .map((a) => ActivityLogItem.fromJson(a))
          .toList();
    }

    List<Map<String, dynamic>> chart = [];
    if (json['attendance_chart'] is List) {
      chart = (json['attendance_chart'] as List).whereType<Map<String, dynamic>>().toList();
    }

    final inTime = parseNullableDate(att['check_in'] ?? json['check_in']);
    final outTime = parseNullableDate(att['check_out'] ?? json['check_out']);
    final checkedIn = att['present_today'] == true || inTime != null;

    return InternDashboardData(
      totalDaysLogged: (stats['total_days_logged'] ?? stats['days_logged'] as num?)?.toInt() ?? 0,
      totalHours: (stats['total_hours'] as num?)?.toDouble() ?? 0.0,
      activeProjects: (stats['active_projects'] as num?)?.toInt() ?? projs.length,
      totalProjects: (stats['total_projects'] as num?)?.toInt() ?? projs.length,
      assignedTasks: (stats['assigned_tasks'] as num?)?.toInt() ?? ts.length,
      completedTasks: (stats['completed_tasks'] as num?)?.toInt() ?? 0,
      openTasks: (stats['open_tasks'] as num?)?.toInt() ?? ts.length,
      overdueTasks: (stats['overdue_tasks'] as num?)?.toInt() ?? 0,
      pendingLeave: (stats['pending_leave'] as num?)?.toInt() ?? 0,
      streakDays: (stats['streak'] ?? stats['attendance_streak'] as num?)?.toInt() ?? 0,
      isCheckedInToday: checkedIn,
      todayCheckIn: inTime,
      todayCheckOut: outTime,
      todayHours: (att['hours_worked'] as num?)?.toDouble() ?? 0.0,
      projects: projs,
      tasks: ts,
      recentLeaves: leaves,
      announcements: anns,
      recentActivity: acts,
      attendanceChart: chart,
    );
  }
}

class MentorInternItem {
  final String id;
  final String name;
  final String email;
  final String department;
  final String avatarUrl;
  final bool isPresent;
  final String? checkIn;
  final String? checkOut;
  final double hoursWorked;
  final int openTasks;
  final int streak;

  const MentorInternItem({
    required this.id,
    required this.name,
    required this.email,
    required this.department,
    required this.avatarUrl,
    this.isPresent = false,
    this.checkIn,
    this.checkOut,
    this.hoursWorked = 0.0,
    this.openTasks = 0,
    this.streak = 0,
  });

  factory MentorInternItem.fromJson(Map<String, dynamic> json) {
    return MentorInternItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Intern',
      email: json['email']?.toString() ?? '',
      department: json['department']?.toString() ?? 'Engineering',
      avatarUrl: json['avatar_url']?.toString() ?? '',
      isPresent: json['is_present'] == true || json['attendance_status'] == 'present',
      checkIn: json['check_in']?.toString(),
      checkOut: json['check_out']?.toString(),
      hoursWorked: (json['hours_worked'] as num?)?.toDouble() ?? 0.0,
      openTasks: (json['open_tasks'] as num?)?.toInt() ?? 0,
      streak: (json['streak'] as num?)?.toInt() ?? 0,
    );
  }
}

class MentorDashboardData {
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
  final List<MentorInternItem> assignedInterns;
  final List<ProjectModel> projects;
  final List<LeaveModel> pendingLeaves;
  final List<ActivityLogItem> recentActivity;
  final List<Map<String, dynamic>> attendanceChart;

  const MentorDashboardData({
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
    this.assignedInterns = const [],
    this.projects = const [],
    this.pendingLeaves = const [],
    this.recentActivity = const [],
    this.attendanceChart = const [],
  });

  factory MentorDashboardData.fromJson(Map<String, dynamic> json) {
    final kpis = json['kpis'] is Map<String, dynamic> ? json['kpis'] as Map<String, dynamic> : json;

    List<MentorInternItem> interns = [];
    if (json['assigned_interns'] is List) {
      interns = (json['assigned_interns'] as List)
          .whereType<Map<String, dynamic>>()
          .map((i) => MentorInternItem.fromJson(i))
          .toList();
    }

    List<ProjectModel> projs = [];
    if (json['projects'] is List) {
      projs = (json['projects'] as List)
          .whereType<Map<String, dynamic>>()
          .map((p) => ProjectModel.fromJson(p))
          .toList();
    }

    List<LeaveModel> leaves = [];
    if (json['pending_leave_requests'] is List) {
      leaves = (json['pending_leave_requests'] as List)
          .whereType<Map<String, dynamic>>()
          .map((l) => LeaveModel.fromJson(l))
          .toList();
    }

    List<ActivityLogItem> acts = [];
    if (json['recent_activity'] is List) {
      acts = (json['recent_activity'] as List)
          .whereType<Map<String, dynamic>>()
          .map((a) => ActivityLogItem.fromJson(a))
          .toList();
    }

    List<Map<String, dynamic>> chart = [];
    if (json['attendance_chart'] is List) {
      chart = (json['attendance_chart'] as List).whereType<Map<String, dynamic>>().toList();
    }

    return MentorDashboardData(
      presentToday: (kpis['present_today'] as num?)?.toInt() ?? 0,
      absentToday: (kpis['absent_today'] as num?)?.toInt() ?? 0,
      assignedInternsCount: (kpis['assigned_interns'] as num?)?.toInt() ?? interns.length,
      activeProjects: (kpis['active_projects'] as num?)?.toInt() ?? projs.length,
      totalProjects: (kpis['total_projects'] as num?)?.toInt() ?? projs.length,
      openTasks: (kpis['open_tasks'] as num?)?.toInt() ?? 0,
      overdueTasks: (kpis['overdue_tasks'] as num?)?.toInt() ?? 0,
      pendingLeave: (kpis['pending_leave'] as num?)?.toInt() ?? leaves.length,
      totalHours: (kpis['total_hours'] as num?)?.toDouble() ?? 0.0,
      daysLogged: (kpis['days_logged'] as num?)?.toInt() ?? 0,
      assignedInterns: interns,
      projects: projs,
      pendingLeaves: leaves,
      recentActivity: acts,
      attendanceChart: chart,
    );
  }
}

class AdminDashboardData {
  final int totalInterns;
  final int totalMentors;
  final int totalUsers;
  final int activeProjects;
  final int activeCohorts;
  final int presentToday;
  final int absentToday;
  final int pendingLeave;
  final int openTasks;
  final int completedTasks;
  final double averageAttendanceRate;
  final List<ProjectModel> projects;
  final List<ActivityLogItem> recentActivity;
  final List<UserModel> recentUsers;
  final List<Map<String, dynamic>> attendanceChart;

  const AdminDashboardData({
    this.totalInterns = 0,
    this.totalMentors = 0,
    this.totalUsers = 0,
    this.activeProjects = 0,
    this.activeCohorts = 0,
    this.presentToday = 0,
    this.absentToday = 0,
    this.pendingLeave = 0,
    this.openTasks = 0,
    this.completedTasks = 0,
    this.averageAttendanceRate = 96.0,
    this.projects = const [],
    this.recentActivity = const [],
    this.recentUsers = const [],
    this.attendanceChart = const [],
  });

  factory AdminDashboardData.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : json;

    List<ProjectModel> projs = [];
    if (json['projects'] is List) {
      projs = (json['projects'] as List)
          .whereType<Map<String, dynamic>>()
          .map((p) => ProjectModel.fromJson(p))
          .toList();
    }

    List<ActivityLogItem> acts = [];
    if (json['recent_activity'] is List) {
      acts = (json['recent_activity'] as List)
          .whereType<Map<String, dynamic>>()
          .map((a) => ActivityLogItem.fromJson(a))
          .toList();
    }

    List<UserModel> users = [];
    if (json['recent_users'] is List) {
      users = (json['recent_users'] as List)
          .whereType<Map<String, dynamic>>()
          .map((u) => UserModel.fromJson(u))
          .toList();
    }

    List<Map<String, dynamic>> chart = [];
    if (json['attendance_chart'] is List) {
      chart = (json['attendance_chart'] as List).whereType<Map<String, dynamic>>().toList();
    }

    return AdminDashboardData(
      totalInterns: (stats['total_interns'] ?? stats['interns_count'] as num?)?.toInt() ?? 0,
      totalMentors: (stats['total_mentors'] ?? stats['mentors_count'] as num?)?.toInt() ?? 0,
      totalUsers: (stats['total_users'] as num?)?.toInt() ?? 0,
      activeProjects: (stats['active_projects'] as num?)?.toInt() ?? projs.length,
      activeCohorts: (stats['active_cohorts'] as num?)?.toInt() ?? 0,
      presentToday: (stats['present_today'] as num?)?.toInt() ?? 0,
      absentToday: (stats['absent_today'] as num?)?.toInt() ?? 0,
      pendingLeave: (stats['pending_leave'] as num?)?.toInt() ?? 0,
      openTasks: (stats['open_tasks'] as num?)?.toInt() ?? 0,
      completedTasks: (stats['completed_tasks'] as num?)?.toInt() ?? 0,
      averageAttendanceRate: (stats['avg_attendance_rate'] as num?)?.toDouble() ?? 96.0,
      projects: projs,
      recentActivity: acts,
      recentUsers: users,
      attendanceChart: chart,
    );
  }
}
