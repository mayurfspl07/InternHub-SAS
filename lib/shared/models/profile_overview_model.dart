import 'user_model.dart';
import 'project_model.dart';
import 'attendance_model.dart';
import 'leave_model.dart';

class UserProfileOverview {
  final UserModel user;
  final Map<String, dynamic> stats;
  final List<ProjectModel> projects;
  final List<TaskModel> tasks;
  final List<AttendanceRecord> attendance;
  final List<UserModel> interns;
  final List<LeaveModel> leaveRequests;
  final LeaveBalance? leaveBalance;

  const UserProfileOverview({
    required this.user,
    this.stats = const {},
    this.projects = const [],
    this.tasks = const [],
    this.attendance = const [],
    this.interns = const [],
    this.leaveRequests = const [],
    this.leaveBalance,
  });

  factory UserProfileOverview.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : json;
    final user = UserModel.fromJson(userJson);

    final stats = json['stats'] is Map<String, dynamic> ? json['stats'] as Map<String, dynamic> : <String, dynamic>{};

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

    List<AttendanceRecord> atts = [];
    if (json['attendance'] is List) {
      atts = (json['attendance'] as List)
          .whereType<Map<String, dynamic>>()
          .map((a) => AttendanceRecord.fromJson(a))
          .toList();
    }

    List<UserModel> itns = [];
    if (json['interns'] is List) {
      itns = (json['interns'] as List)
          .whereType<Map<String, dynamic>>()
          .map((u) => UserModel.fromJson(u))
          .toList();
    }

    List<LeaveModel> leaves = [];
    if (json['leave_requests'] is List) {
      leaves = (json['leave_requests'] as List)
          .whereType<Map<String, dynamic>>()
          .map((l) => LeaveModel.fromJson(l))
          .toList();
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
      leaveBalance: balance,
    );
  }
}
