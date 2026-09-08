import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/auth_storage.dart';
import '../../shared/models/user_model.dart';
import '../../shared/models/attendance_model.dart';
import '../../shared/models/project_model.dart';
import '../../shared/models/standup_model.dart';
import '../../shared/models/leave_model.dart';
import '../../shared/models/review_model.dart';
import '../../shared/models/cohort_model.dart';
import '../../shared/models/assignment_model.dart';
import '../../shared/models/invite_model.dart';
import '../../shared/models/dashboard_models.dart';
import '../../shared/models/profile_overview_model.dart';

class AppState {
  final UserModel currentUser;
  final ThemeMode themeMode;
  final bool isAuthenticated;
  final bool isSessionLoading;
  final String? authError;

  // Dashboards
  final InternDashboardData? internDashboard;
  final MentorDashboardData? mentorDashboard;
  final AdminDashboardData? adminDashboard;
  final bool isDashboardLoading;

  // Entity Lists
  final List<UserModel> allUsers;
  final List<ProjectModel> projects;
  final List<TaskModel> tasks;
  final List<AttendanceRecord> attendanceRecords;
  final AttendanceRecord? todayAttendance;
  final List<StandupModel> standups;
  final StandupModel? todayStandup;
  final List<LeaveModel> leaveRequests;
  final LeaveBalance leaveBalance;
  final List<ReviewModel> reviews;
  final List<CohortModel> cohorts;
  final List<AnnouncementModel> announcements;
  final List<NotificationItem> notifications;
  final List<ActivityLogItem> activityLogs;
  final List<RecycleBinItem> recycleBin;
  final List<AssignmentModel> assignments;
  final List<InviteLinkModel> inviteLinks;
  final List<SignupRequestModel> signupRequests;

  List<UserModel> get users => allUsers;

  const AppState({
    required this.currentUser,
    this.themeMode = ThemeMode.light,
    this.isAuthenticated = false,
    this.isSessionLoading = true,
    this.authError,
    this.internDashboard,
    this.mentorDashboard,
    this.adminDashboard,
    this.isDashboardLoading = false,
    this.allUsers = const [],
    this.projects = const [],
    this.tasks = const [],
    this.attendanceRecords = const [],
    this.todayAttendance,
    this.standups = const [],
    this.todayStandup,
    this.leaveRequests = const [],
    this.leaveBalance = const LeaveBalance(),
    this.reviews = const [],
    this.cohorts = const [],
    this.announcements = const [],
    this.notifications = const [],
    this.activityLogs = const [],
    this.recycleBin = const [],
    this.assignments = const [],
    this.inviteLinks = const [],
    this.signupRequests = const [],
  });

  static UserModel defaultGuestUser() {
    return const UserModel(
      id: '',
      name: 'Guest User',
      email: '',
      role: UserRole.intern,
      isActive: false,
    );
  }

  AppState copyWith({
    UserModel? currentUser,
    ThemeMode? themeMode,
    bool? isAuthenticated,
    bool? isSessionLoading,
    String? authError,
    bool clearAuthError = false,
    InternDashboardData? internDashboard,
    MentorDashboardData? mentorDashboard,
    AdminDashboardData? adminDashboard,
    bool? isDashboardLoading,
    List<UserModel>? allUsers,
    List<ProjectModel>? projects,
    List<TaskModel>? tasks,
    List<AttendanceRecord>? attendanceRecords,
    AttendanceRecord? todayAttendance,
    bool clearTodayAttendance = false,
    List<StandupModel>? standups,
    StandupModel? todayStandup,
    bool clearTodayStandup = false,
    List<LeaveModel>? leaveRequests,
    LeaveBalance? leaveBalance,
    List<ReviewModel>? reviews,
    List<CohortModel>? cohorts,
    List<AnnouncementModel>? announcements,
    List<NotificationItem>? notifications,
    List<ActivityLogItem>? activityLogs,
    List<RecycleBinItem>? recycleBin,
    List<AssignmentModel>? assignments,
    List<InviteLinkModel>? inviteLinks,
    List<SignupRequestModel>? signupRequests,
  }) {
    return AppState(
      currentUser: currentUser ?? this.currentUser,
      themeMode: themeMode ?? this.themeMode,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isSessionLoading: isSessionLoading ?? this.isSessionLoading,
      authError: clearAuthError ? null : (authError ?? this.authError),
      internDashboard: internDashboard ?? this.internDashboard,
      mentorDashboard: mentorDashboard ?? this.mentorDashboard,
      adminDashboard: adminDashboard ?? this.adminDashboard,
      isDashboardLoading: isDashboardLoading ?? this.isDashboardLoading,
      allUsers: allUsers ?? this.allUsers,
      projects: projects ?? this.projects,
      tasks: tasks ?? this.tasks,
      attendanceRecords: attendanceRecords ?? this.attendanceRecords,
      todayAttendance: clearTodayAttendance ? null : (todayAttendance ?? this.todayAttendance),
      standups: standups ?? this.standups,
      todayStandup: clearTodayStandup ? null : (todayStandup ?? this.todayStandup),
      leaveRequests: leaveRequests ?? this.leaveRequests,
      leaveBalance: leaveBalance ?? this.leaveBalance,
      reviews: reviews ?? this.reviews,
      cohorts: cohorts ?? this.cohorts,
      announcements: announcements ?? this.announcements,
      notifications: notifications ?? this.notifications,
      activityLogs: activityLogs ?? this.activityLogs,
      recycleBin: recycleBin ?? this.recycleBin,
      assignments: assignments ?? this.assignments,
      inviteLinks: inviteLinks ?? this.inviteLinks,
      signupRequests: signupRequests ?? this.signupRequests,
    );
  }
}

class AppStateNotifier extends StateNotifier<AppState> {
  final ApiClient _api = ApiClient();

  List<T> _extractList<T>(dynamic res, T Function(Map<String, dynamic>) fromJson, {List<String> keys = const []}) {
    if (res == null) return [];
    if (res is List) {
      return res.whereType<Map<String, dynamic>>().map(fromJson).toList();
    }
    if (res is Map) {
      final searchKeys = [...keys, 'items', 'data', 'list', 'results'];
      for (final k in searchKeys) {
        if (res[k] is List) {
          return (res[k] as List).whereType<Map<String, dynamic>>().map(fromJson).toList();
        }
      }
    }
    return [];
  }

  AppStateNotifier() : super(AppState(currentUser: AppState.defaultGuestUser())) {
    _api.onUnauthorized = () {
      logout();
    };
    bootstrap();
  }

  Future<void> bootstrap() async {
    state = state.copyWith(isSessionLoading: true, clearAuthError: true);
    try {
      final token = await AuthStorage.getToken();
      if (token == null || token.isEmpty) {
        state = state.copyWith(
          isAuthenticated: false,
          isSessionLoading: false,
          currentUser: AppState.defaultGuestUser(),
        );
        return;
      }

      final meJson = await _api.get('/api/auth/me');
      if (meJson is Map<String, dynamic>) {
        final user = UserModel.fromJson(meJson);
        state = state.copyWith(
          currentUser: user,
          isAuthenticated: true,
          isSessionLoading: false,
        );
        await refreshAllData();
      } else {
        await logout();
      }
    } catch (_) {
      state = state.copyWith(
        isAuthenticated: false,
        isSessionLoading: false,
        currentUser: AppState.defaultGuestUser(),
      );
    }
  }

  Future<void> login({
    required String email,
    required String password,
    bool remember = true,
  }) async {
    state = state.copyWith(isSessionLoading: true, clearAuthError: true);
    try {
      final res = await _api.post('/api/auth/login', body: {
        'email': email.trim(),
        'password': password,
        'remember': remember,
      });

      String? token;
      String? orgId;

      if (res is Map<String, dynamic>) {
        token = res['token']?.toString() ??
            res['access_token']?.toString() ??
            res['auth_token']?.toString();
        orgId = res['organization_id']?.toString() ??
            res['user']?['organization_id']?.toString();
      }

      if (token != null && token.isNotEmpty) {
        await AuthStorage.saveSession(
          token: token,
          remember: remember,
          orgId: orgId,
          email: email.trim(),
        );
      }

      final meJson = await _api.get('/api/auth/me');
      final user = UserModel.fromJson(meJson as Map<String, dynamic>);

      state = state.copyWith(
        currentUser: user,
        isAuthenticated: true,
        isSessionLoading: false,
      );

      await refreshAllData();
    } catch (e) {
      final message = e is ApiException ? e.message : e.toString();
      state = state.copyWith(
        isAuthenticated: false,
        isSessionLoading: false,
        authError: message,
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await _api.post('/api/auth/logout');
    } catch (_) {}
    await AuthStorage.clearSession();
    state = AppState(
      currentUser: AppState.defaultGuestUser(),
      themeMode: state.themeMode,
      isAuthenticated: false,
      isSessionLoading: false,
    );
  }

  void toggleThemeMode() {
    final next = state.themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    state = state.copyWith(themeMode: next);
  }

  Future<void> refreshAllData() async {
    await Future.wait([
      fetchDashboard(),
      fetchNotifications(),
      fetchAnnouncements(),
      fetchProjects(),
      fetchAttendance(),
      fetchLeave(),
      fetchStandup(),
    ]);

    if (state.currentUser.role == UserRole.admin || state.currentUser.role == UserRole.mentor) {
      await Future.wait([
        fetchUsers(),
        fetchCohorts(),
        fetchReviews(),
        fetchAssignments(),
        fetchInviteLinks(),
        fetchActivityLogs(),
      ]);
    }

    if (state.currentUser.role == UserRole.admin) {
      await fetchRecycleBin();
    }
  }

  // Dashboard API
  Future<void> fetchDashboard() async {
    state = state.copyWith(isDashboardLoading: true);
    try {
      switch (state.currentUser.role) {
        case UserRole.intern:
          final res = await _api.get('/api/intern/dashboard');
          if (res is Map<String, dynamic>) {
            final data = InternDashboardData.fromJson(res);
            state = state.copyWith(
              internDashboard: data,
              isDashboardLoading: false,
              projects: data.projects.isNotEmpty ? data.projects : state.projects,
              tasks: data.tasks.isNotEmpty ? data.tasks : state.tasks,
              leaveRequests: data.recentLeaves.isNotEmpty ? data.recentLeaves : state.leaveRequests,
              announcements: data.announcements.isNotEmpty ? data.announcements : state.announcements,
            );
          }
          break;

        case UserRole.mentor:
          final res = await _api.get('/api/mentor/dashboard');
          if (res is Map<String, dynamic>) {
            final data = MentorDashboardData.fromJson(res);
            state = state.copyWith(
              mentorDashboard: data,
              isDashboardLoading: false,
              projects: data.projects.isNotEmpty ? data.projects : state.projects,
              leaveRequests: data.pendingLeaves.isNotEmpty ? data.pendingLeaves : state.leaveRequests,
            );
          }
          break;

        case UserRole.admin:
        case UserRole.superadmin:
          final res = await _api.get('/api/admin/dashboard');
          if (res is Map<String, dynamic>) {
            final data = AdminDashboardData.fromJson(res);
            state = state.copyWith(
              adminDashboard: data,
              isDashboardLoading: false,
              projects: data.projects.isNotEmpty ? data.projects : state.projects,
              allUsers: data.recentUsers.isNotEmpty ? data.recentUsers : state.allUsers,
            );
          }
          break;
      }
    } catch (_) {
      state = state.copyWith(isDashboardLoading: false);
    }
  }

  // Attendance API
  Future<void> fetchAttendance() async {
    try {
      if (state.currentUser.role == UserRole.intern) {
        final todayRes = await _api.get('/api/attendance/today');
        AttendanceRecord? today;
        if (todayRes is Map<String, dynamic>) {
          final rec = todayRes['record'] is Map<String, dynamic>
              ? todayRes['record'] as Map<String, dynamic>
              : todayRes;
          if (rec['id'] != null) {
            today = AttendanceRecord.fromJson(rec);
          }
        }

        final histRes = await _api.get('/api/attendance/history');
        final records = _extractList(histRes, AttendanceRecord.fromJson, keys: ['history', 'records']);

        state = state.copyWith(
          todayAttendance: today,
          attendanceRecords: records,
        );
      } else if (state.currentUser.role == UserRole.mentor) {
        final res = await _api.get('/api/mentor/students/today');
        final records = _extractList(res, AttendanceRecord.fromJson, keys: ['students', 'attendance', 'records']);
        state = state.copyWith(attendanceRecords: records);
      } else {
        final res = await _api.get('/api/admin/students/today');
        final records = _extractList(res, AttendanceRecord.fromJson, keys: ['students', 'attendance', 'records']);
        state = state.copyWith(attendanceRecords: records);
      }
    } catch (_) {}
  }

  Future<void> checkIn({required File photo, required double latitude, required double longitude}) async {
    final file = await http.MultipartFile.fromPath('photo', photo.path);
    final res = await _api.postMultipart(
      '/api/attendance/check-in',
      fields: {
        'lat': latitude.toString(),
        'lng': longitude.toString(),
      },
      files: [file],
    );

    if (res is Map<String, dynamic>) {
      final record = AttendanceRecord.fromJson(res);
      state = state.copyWith(
        todayAttendance: record,
        attendanceRecords: [record, ...state.attendanceRecords],
      );
    }
    await fetchDashboard();
  }

  Future<void> checkOut({File? photo, double? latitude, double? longitude}) async {
    List<http.MultipartFile> files = [];
    if (photo != null) {
      files.add(await http.MultipartFile.fromPath('photo', photo.path));
    }

    final fields = <String, String>{};
    if (latitude != null) fields['lat'] = latitude.toString();
    if (longitude != null) fields['lng'] = longitude.toString();

    final res = await _api.postMultipart(
      '/api/attendance/check-out',
      fields: fields,
      files: files,
    );

    if (res is Map<String, dynamic>) {
      final record = AttendanceRecord.fromJson(res);
      state = state.copyWith(
        todayAttendance: record,
        attendanceRecords: state.attendanceRecords.map((r) => r.id == record.id ? record : r).toList(),
      );
    }
    await fetchDashboard();
  }

  // Projects & Tasks API
  Future<void> fetchProjects() async {
    try {
      final res = await _api.get('/api/projects');
      final list = _extractList(res, ProjectModel.fromJson, keys: ['projects']);
      state = state.copyWith(projects: list);
    } catch (_) {}
  }

  Future<void> createProject(Map<String, dynamic> data) async {
    final res = await _api.post('/api/projects', body: data);
    if (res is Map<String, dynamic>) {
      final p = ProjectModel.fromJson(res);
      state = state.copyWith(projects: [p, ...state.projects]);
    }
    await fetchDashboard();
  }

  Future<void> updateProject(String id, Map<String, dynamic> data) async {
    final res = await _api.put('/api/projects/$id', body: data);
    if (res is Map<String, dynamic>) {
      final p = ProjectModel.fromJson(res);
      state = state.copyWith(
        projects: state.projects.map((item) => item.id == id ? p : item).toList(),
      );
    }
  }

  Future<void> deleteProject(String id) async {
    await _api.delete('/api/projects/$id');
    state = state.copyWith(
      projects: state.projects.where((p) => p.id != id).toList(),
    );
    await fetchDashboard();
  }

  Future<void> fetchTasks([String? projectId]) async {
    try {
      if (projectId != null && projectId.isNotEmpty) {
        final res = await _api.get('/api/projects/$projectId');
        List<TaskModel> list = [];
        if (res is Map<String, dynamic> && res['tasks'] is List) {
          list = (res['tasks'] as List)
              .whereType<Map<String, dynamic>>()
              .map((t) => TaskModel.fromJson(t))
              .toList();
        }
        state = state.copyWith(tasks: list);
      } else {
        final res = await _api.get('/api/dashboard/open-tasks');
        final list = _extractList(res, TaskModel.fromJson, keys: ['tasks']);
        if (list.isNotEmpty) {
          state = state.copyWith(tasks: list);
        }
      }
    } catch (_) {}
  }

  Future<void> createTask(String projectId, Map<String, dynamic> data) async {
    final res = await _api.post('/api/projects/$projectId/tasks', body: data);
    if (res is Map<String, dynamic>) {
      final t = TaskModel.fromJson(res);
      state = state.copyWith(tasks: [t, ...state.tasks]);
    }
    await fetchDashboard();
  }

  Future<void> updateTask(String taskId, Map<String, dynamic> data) async {
    final res = await _api.put('/api/projects/tasks/$taskId', body: data);
    if (res is Map<String, dynamic>) {
      final t = TaskModel.fromJson(res);
      state = state.copyWith(
        tasks: state.tasks.map((item) => item.id == taskId ? t : item).toList(),
      );
    }
  }

  Future<void> updateTaskStatus(String taskId, KanbanStatus status) async {
    try {
      dynamic res;
      try {
        res = await _api.patch('/api/projects/tasks/$taskId/status', body: {
          'status': status.toApiValue(),
        });
      } catch (_) {
        res = await _api.put('/api/projects/tasks/$taskId', body: {
          'status': status.toApiValue(),
        });
      }

      if (res is Map<String, dynamic>) {
        final t = TaskModel.fromJson(res);
        state = state.copyWith(
          tasks: state.tasks.map((item) => item.id == taskId ? t : item).toList(),
        );
      } else {
        state = state.copyWith(
          tasks: state.tasks.map((item) => item.id == taskId ? item.copyWith(status: status) : item).toList(),
        );
      }
    } catch (_) {
      state = state.copyWith(
        tasks: state.tasks.map((item) => item.id == taskId ? item.copyWith(status: status) : item).toList(),
      );
    }
    await fetchDashboard();
  }

  Future<void> deleteTask(String taskId) async {
    try {
      await _api.delete('/api/tasks/$taskId');
    } catch (_) {
      await _api.delete('/api/projects/tasks/$taskId');
    }
    state = state.copyWith(
      tasks: state.tasks.where((t) => t.id != taskId).toList(),
    );
    await fetchDashboard();
  }

  // Leave API
  Future<void> fetchLeave() async {
    try {
      if (state.currentUser.role == UserRole.intern) {
        final balRes = await _api.get('/api/leave/balance');
        if (balRes is Map<String, dynamic>) {
          state = state.copyWith(leaveBalance: LeaveBalance.fromJson(balRes));
        }

        final myRes = await _api.get('/api/leave/mine');
        final list = _extractList(myRes, LeaveModel.fromJson, keys: ['requests', 'pending_requests', 'leaves', 'items']);
        
        if (balRes == null && myRes is Map<String, dynamic> && myRes['balance'] is Map<String, dynamic>) {
          state = state.copyWith(leaveBalance: LeaveBalance.fromJson(myRes['balance']));
        }
        
        state = state.copyWith(leaveRequests: list);
      } else {
        final manageRes = await _api.get('/api/leave/manage');
        final list = _extractList(manageRes, LeaveModel.fromJson, keys: ['requests', 'leaves', 'items', 'pending_requests']);
        state = state.copyWith(leaveRequests: list);
      }
    } catch (_) {}
  }

  Future<void> applyLeave({
    required LeaveType type,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    File? attachment,
  }) async {
    dynamic res;
    if (attachment != null) {
      final files = [await http.MultipartFile.fromPath('attachment', attachment.path)];
      res = await _api.postMultipart(
        '/api/leave',
        fields: {
          'leave_type': type.toApiValue(),
          'start_date': startDate.toIso8601String().substring(0, 10),
          'end_date': endDate.toIso8601String().substring(0, 10),
          'reason': reason,
        },
        files: files,
      );
    } else {
      res = await _api.post(
        '/api/leave',
        body: {
          'leave_type': type.toApiValue(),
          'start_date': startDate.toIso8601String().substring(0, 10),
          'end_date': endDate.toIso8601String().substring(0, 10),
          'reason': reason,
        },
      );
    }

    if (res is Map<String, dynamic>) {
      final leave = LeaveModel.fromJson(res);
      state = state.copyWith(leaveRequests: [leave, ...state.leaveRequests]);
    }
    await fetchLeave();
    await fetchDashboard();
  }

  Future<void> reviewLeave({required String leaveId, required String decision, String? comment}) async {
    await _api.post('/api/leave/$leaveId/review', body: {
      'decision': decision,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    await fetchLeave();
    await fetchDashboard();
  }

  // Standup API
  Future<void> fetchStandup() async {
    try {
      final todayRes = await _api.get('/api/standup/today');
      StandupModel? today;
      if (todayRes is Map<String, dynamic> && todayRes['id'] != null) {
        today = StandupModel.fromJson(todayRes);
      }

      final feedRes = await _api.get('/api/standup');
      List<StandupModel> list = [];
      if (feedRes is List) {
        list = feedRes.whereType<Map<String, dynamic>>().map((s) => StandupModel.fromJson(s)).toList();
      }
      state = state.copyWith(todayStandup: today, standups: list);
    } catch (_) {}
  }

  Future<void> submitStandup({
    required String did,
    required String plan,
    String? blockers,
    StandupMood mood = StandupMood.productive,
  }) async {
    final body = {
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'did': did,
      'plan': plan,
      'blockers': blockers ?? '',
      'mood': mood.toApiValue(),
    };

    if (state.todayStandup != null) {
      final res = await _api.put('/api/standup/${state.todayStandup!.id}', body: body);
      if (res is Map<String, dynamic>) {
        final s = StandupModel.fromJson(res);
        state = state.copyWith(todayStandup: s);
      }
    } else {
      final res = await _api.post('/api/standup', body: body);
      if (res is Map<String, dynamic>) {
        final s = StandupModel.fromJson(res);
        state = state.copyWith(
          todayStandup: s,
          standups: [s, ...state.standups],
        );
      }
    }
    await fetchStandup();
  }

  Future<void> deleteStandup(String id) async {
    await _api.delete('/api/standup/$id');
    await fetchStandup();
  }

  // Announcements API
  Future<void> fetchAnnouncements() async {
    try {
      final res = await _api.get('/api/announcements');
      final list = _extractList(res, AnnouncementModel.fromJson, keys: ['announcements', 'items']);
      state = state.copyWith(announcements: list);
    } catch (_) {}
  }

  Future<void> createAnnouncement(Map<String, dynamic> data) async {
    final res = await _api.post('/api/announcements', body: data);
    if (res is Map<String, dynamic>) {
      final a = AnnouncementModel.fromJson(res);
      state = state.copyWith(announcements: [a, ...state.announcements]);
    }
  }

  Future<void> deleteAnnouncement(String id) async {
    await _api.delete('/api/announcements/$id');
    state = state.copyWith(
      announcements: state.announcements.where((a) => a.id != id).toList(),
    );
  }

  // Reviews API
  Future<void> fetchReviews() async {
    try {
      final res = await _api.get('/api/reviews');
      final list = _extractList(res, ReviewModel.fromJson, keys: ['reviews', 'items']);
      state = state.copyWith(reviews: list);
    } catch (_) {}
  }

  Future<void> createReview(Map<String, dynamic> data) async {
    final res = await _api.post('/api/reviews', body: data);
    if (res is Map<String, dynamic>) {
      final r = ReviewModel.fromJson(res);
      state = state.copyWith(reviews: [r, ...state.reviews]);
    }
  }

  // Cohorts API
  Future<void> fetchCohorts() async {
    try {
      final res = await _api.get('/api/cohorts');
      final list = _extractList(res, CohortModel.fromJson, keys: ['cohorts', 'items']);
      state = state.copyWith(cohorts: list);
    } catch (_) {}
  }

  Future<void> createCohort(Map<String, dynamic> data) async {
    final res = await _api.post('/api/cohorts', body: data);
    if (res is Map<String, dynamic>) {
      final c = CohortModel.fromJson(res);
      state = state.copyWith(cohorts: [c, ...state.cohorts]);
    }
  }

  Future<void> updateCohort(String id, Map<String, dynamic> data) async {
    final res = await _api.put('/api/cohorts/$id', body: data);
    if (res is Map<String, dynamic>) {
      final c = CohortModel.fromJson(res);
      state = state.copyWith(
        cohorts: state.cohorts.map((item) => item.id == id ? c : item).toList(),
      );
    }
  }

  Future<void> deleteCohort(String id) async {
    await _api.delete('/api/cohorts/$id');
    state = state.copyWith(
      cohorts: state.cohorts.where((item) => item.id != id).toList(),
    );
  }

  // Notifications API
  Future<void> fetchNotifications() async {
    try {
      final res = await _api.get('/api/notifications');
      final list = _extractList(res, NotificationItem.fromJson, keys: ['notifications', 'items']);
      state = state.copyWith(notifications: list);
    } catch (_) {}
  }

  Future<void> markNotificationRead(String id) async {
    try {
      await _api.post('/api/notifications/mark-read', body: {'notification_id': id});
      state = state.copyWith(
        notifications: state.notifications.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList(),
      );
    } catch (_) {}
  }

  Future<void> markAllNotificationsRead() async {
    try {
      await _api.post('/api/notifications/mark-read');
      state = state.copyWith(
        notifications: state.notifications.map((n) => n.copyWith(isRead: true)).toList(),
      );
    } catch (_) {}
  }

  Future<void> deleteNotification(String id) async {
    try {
      await _api.delete('/api/notifications/$id');
      state = state.copyWith(
        notifications: state.notifications.where((n) => n.id != id).toList(),
      );
    } catch (_) {}
  }

  // Users API
  Future<Map<String, dynamic>> fetchUsers({
    String? role,
    String? search,
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      dynamic res;
      final isMentor = state.currentUser.role == UserRole.mentor;
      final isAdmin = state.currentUser.role == UserRole.admin || state.currentUser.role == UserRole.superadmin;

      if (isAdmin || isMentor) {
        final queryParams = <String, dynamic>{
          'page': page,
          'page_size': pageSize,
        };
        if (isMentor) {
          queryParams['role'] = 'intern';
        } else if (role != null && role.isNotEmpty && role != 'all') {
          queryParams['role'] = role;
        }
        if (search != null && search.trim().isNotEmpty) {
          queryParams['search'] = search.trim();
        }
        res = await _api.get('/api/admin/users', queryParameters: queryParams);
      } else {
        res = await _api.get('/api/users/dropdown');
      }

      var list = _extractList(res, UserModel.fromJson, keys: ['users', 'students', 'interns']);

      int currentPage = page;
      int totalPages = 1;
      int totalCount = list.length;
      int curPageSize = pageSize;

      if (res is Map<String, dynamic>) {
        if (res['page'] != null) {
          currentPage = int.tryParse(res['page'].toString()) ?? page;
        }
        if (res['total_pages'] != null) {
          totalPages = int.tryParse(res['total_pages'].toString()) ?? 1;
        } else if (res['pages'] != null) {
          totalPages = int.tryParse(res['pages'].toString()) ?? 1;
        } else if (res['totalPages'] != null) {
          totalPages = int.tryParse(res['totalPages'].toString()) ?? 1;
        }
        if (res['total'] != null) {
          totalCount = int.tryParse(res['total'].toString()) ?? list.length;
        } else if (res['total_count'] != null) {
          totalCount = int.tryParse(res['total_count'].toString()) ?? list.length;
        } else if (res['count'] != null) {
          totalCount = int.tryParse(res['count'].toString()) ?? list.length;
        }
        if (res['page_size'] != null) {
          curPageSize = int.tryParse(res['page_size'].toString()) ?? pageSize;
        }
      }

      // Mentor enrichment for intern rows via /api/admin/intern-assignments
      if (isAdmin || isMentor) {
        try {
          final assignRes = await _api.get('/api/admin/intern-assignments');
          final assignments = <Map<String, dynamic>>[];
          if (assignRes is List) {
            assignments.addAll(assignRes.whereType<Map<String, dynamic>>());
          } else if (assignRes is Map) {
            for (final k in ['assignments', 'items', 'data']) {
              if (assignRes[k] is List) {
                assignments.addAll((assignRes[k] as List).whereType<Map<String, dynamic>>());
                break;
              }
            }
          }

          if (assignments.isNotEmpty) {
            final mentorMap = <String, Map<String, String>>{};
            for (final a in assignments) {
              final internId = a['intern_id']?.toString() ??
                  a['user_id']?.toString() ??
                  a['student_id']?.toString() ??
                  (a['intern'] is Map ? a['intern']['id']?.toString() : null);
              if (internId == null || internId.isEmpty) continue;

              final mentorId = a['mentor_id']?.toString() ??
                  (a['mentor'] is Map ? a['mentor']['id']?.toString() : null);
              final mentorName = a['mentor_name']?.toString() ??
                  (a['mentor'] is Map ? a['mentor']['name']?.toString() : null);

              final itemMap = <String, String>{};
              if (mentorId != null) itemMap['mentor_id'] = mentorId;
              if (mentorName != null) itemMap['mentor_name'] = mentorName;
              mentorMap[internId] = itemMap;
            }

            list = list.map((u) {
              if (u.role == UserRole.intern && mentorMap.containsKey(u.id)) {
                final match = mentorMap[u.id]!;
                final mId = match['mentor_id'] ?? u.mentorId;
                String? mName = match['mentor_name'] ?? u.mentorName;
                if ((mName == null || mName.isEmpty) && mId != null) {
                  final foundMentor = list.where((m) => m.id == mId).firstOrNull;
                  if (foundMentor != null) mName = foundMentor.name;
                }
                return u.copyWith(
                  mentorId: mId,
                  mentorName: mName,
                );
              }
              return u;
            }).toList();
          }
        } catch (_) {}
      }

      state = state.copyWith(allUsers: list);
      return {
        'page': currentPage,
        'total_pages': totalPages,
        'total': totalCount,
        'page_size': curPageSize,
        'users': list,
      };
    } catch (_) {
      return {
        'page': page,
        'total_pages': 1,
        'total': state.allUsers.length,
        'page_size': pageSize,
        'users': state.allUsers,
      };
    }
  }

  Future<List<UserModel>> fetchMentorsForPicker({String? search, int page = 1, int pageSize = 20}) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
        'role': 'mentor',
      };
      if (search != null && search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }
      final res = await _api.get('/api/admin/users', queryParameters: queryParams);
      final list = _extractList(res, UserModel.fromJson, keys: ['users', 'items']);
      if (list.isNotEmpty) return list;
    } catch (_) {}
    return state.allUsers.where((u) => u.role == UserRole.mentor).toList();
  }

  Future<void> createUser(Map<String, dynamic> data) async {
    final res = await _api.post('/api/admin/users', body: data);
    if (res is Map<String, dynamic>) {
      final u = UserModel.fromJson(res);
      state = state.copyWith(allUsers: [u, ...state.allUsers]);
    } else {
      await fetchUsers();
    }
  }

  Future<void> updateUser(String id, Map<String, dynamic> data) async {
    final res = await _api.put('/api/admin/users/$id', body: data);
    if (res is Map<String, dynamic>) {
      final updated = UserModel.fromJson(res);
      state = state.copyWith(
        allUsers: state.allUsers.map((u) => u.id == id ? updated : u).toList(),
      );
    } else {
      await fetchUsers();
    }
  }

  Future<void> toggleUserActive(String id) async {
    await _api.post('/api/admin/users/$id/toggle');
    state = state.copyWith(
      allUsers: state.allUsers.map((u) => u.id == id ? u.copyWith(isActive: !u.isActive) : u).toList(),
    );
  }

  Future<void> deleteUser(String id) async {
    await _api.delete('/api/admin/users/$id');
    state = state.copyWith(
      allUsers: state.allUsers.where((u) => u.id != id).toList(),
    );
  }

  // Assignments API
  Future<void> fetchAssignments() async {
    try {
      final res = await _api.get('/api/assignments');
      final list = _extractList(res, AssignmentModel.fromJson, keys: ['assignments', 'items']);
      state = state.copyWith(assignments: list);
    } catch (_) {}
  }

  // Invite Links & Signups API
  Future<void> fetchInviteLinks() async {
    try {
      final res = await _api.get('/api/admin/invite-link');
      List<InviteLinkModel> list = [];
      if (res is List) {
        list = res.whereType<Map<String, dynamic>>().map((i) => InviteLinkModel.fromJson(i)).toList();
      } else if (res is Map) {
        if (res['links'] is List) {
          list = (res['links'] as List).whereType<Map<String, dynamic>>().map((i) => InviteLinkModel.fromJson(i)).toList();
        }
        if (list.isEmpty && res['link'] is Map<String, dynamic>) {
          list = [InviteLinkModel.fromJson(res['link'] as Map<String, dynamic>)];
        }
      }
      state = state.copyWith(inviteLinks: list);

      final reqRes = await _api.get('/api/admin/intern-signup-requests');
      final requests = _extractList(reqRes, SignupRequestModel.fromJson, keys: ['requests', 'signup_requests', 'items']);
      state = state.copyWith(signupRequests: requests);
    } catch (_) {}
  }

  // Activity Audit API
  Future<void> fetchActivityLogs() async {
    try {
      final res = await _api.get('/api/audit');
      final list = _extractList(res, ActivityLogItem.fromJson, keys: ['logs', 'audit_logs', 'items']);
      state = state.copyWith(activityLogs: list);
    } catch (_) {}
  }

  // Recycle Bin API
  Future<void> fetchRecycleBin() async {
    try {
      final res = await _api.get('/api/admin/bin');
      final list = _extractList(res, RecycleBinItem.fromJson, keys: ['items', 'bin']);
      state = state.copyWith(recycleBin: list);
    } catch (_) {}
  }

  Future<void> restoreRecycleItem(String id) async {
    await _api.post('/api/admin/bin/$id/restore');
    state = state.copyWith(recycleBin: state.recycleBin.where((r) => r.id != id).toList());
    await refreshAllData();
  }

  Future<void> permanentlyDeleteRecycleItem(String id) async {
    await _api.delete('/api/admin/bin/$id');
    state = state.copyWith(recycleBin: state.recycleBin.where((r) => r.id != id).toList());
  }

  Future<void> clearRecycleBin() async {
    await _api.delete('/api/admin/bin');
    state = state.copyWith(recycleBin: const []);
  }

  // Database Reset (Danger Zone)
  Future<void> clearDatabase(String password) async {
    await _api.post('/api/admin/clear-database', body: {'password': password});
    await logout();
  }

  // User 360 Profile Overview API
  Future<UserProfileOverview?> fetchUserOverview(String userId) async {
    try {
      final res = await _api.get('/api/users/$userId/overview');
      if (res is Map<String, dynamic>) {
        return UserProfileOverview.fromJson(res);
      }
    } catch (_) {}
    return null;
  }

  Future<void> fetchCurrentUser() async {
    try {
      final res = await _api.get('/api/auth/me');
      if (res is Map<String, dynamic>) {
        final user = UserModel.fromJson(res);
        state = state.copyWith(currentUser: user);
      }
    } catch (_) {}
  }

  Future<void> fetchLeaves() async => fetchLeave();

  void switchRole(UserRole role) {
    state = state.copyWith(
      currentUser: state.currentUser.copyWith(role: role),
    );
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['skills'] is List) {
      payload['skills'] = (payload['skills'] as List)
          .map((s) => s.toString().trim())
          .where((s) => s.isNotEmpty)
          .join(', ');
    }
    final res = await _api.put('/api/profile', body: payload);
    if (res is Map<String, dynamic>) {
      final updated = UserModel.fromJson(res);
      state = state.copyWith(currentUser: updated);
    } else {
      await fetchCurrentUser();
    }
  }
}

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});
