import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/auth_storage.dart';
import '../../shared/models/user_model.dart';
import '../../shared/models/attendance_model.dart';
import '../../shared/models/cohort_model.dart';
import '../../shared/models/invite_model.dart';
import '../../shared/models/profile_overview_model.dart';

/// App-wide state: the signed-in user and the few lists shared by several screens.
///
/// Feature screens load their own data through their repositories; this state only
/// holds what is shown in more than one place (notification badge, users list,
/// today's attendance, recycle bin and invite links). Each list keeps the last load
/// error so screens can show it with a retry instead of an empty list.
class AppState {
  final UserModel currentUser;
  final bool isAuthenticated;
  final bool isSessionLoading;
  final String? authError;

  final List<UserModel> allUsers;
  final bool usersLoading;
  final String? usersError;

  final AttendanceRecord? todayAttendance;

  final List<NotificationItem> notifications;
  final int unreadCount;
  final bool notificationsLoading;
  final String? notificationsError;

  final List<RecycleBinItem> recycleBin;
  final bool recycleBinLoading;
  final String? recycleBinError;

  final List<InviteLinkModel> inviteLinks;
  final List<SignupRequestModel> signupRequests;
  final bool invitesLoading;
  final String? invitesError;

  List<UserModel> get users => allUsers;

  const AppState({
    required this.currentUser,
    this.isAuthenticated = false,
    this.isSessionLoading = true,
    this.authError,
    this.allUsers = const [],
    this.usersLoading = false,
    this.usersError,
    this.todayAttendance,
    this.notifications = const [],
    this.unreadCount = 0,
    this.notificationsLoading = false,
    this.notificationsError,
    this.recycleBin = const [],
    this.recycleBinLoading = false,
    this.recycleBinError,
    this.inviteLinks = const [],
    this.signupRequests = const [],
    this.invitesLoading = false,
    this.invitesError,
  });

  static UserModel defaultGuestUser() {
    return const UserModel(id: '', name: '', email: '', role: UserRole.intern, isActive: false);
  }

  AppState copyWith({
    UserModel? currentUser,
    bool? isAuthenticated,
    bool? isSessionLoading,
    String? authError,
    bool clearAuthError = false,
    List<UserModel>? allUsers,
    bool? usersLoading,
    String? usersError,
    bool clearUsersError = false,
    AttendanceRecord? todayAttendance,
    bool clearTodayAttendance = false,
    List<NotificationItem>? notifications,
    int? unreadCount,
    bool? notificationsLoading,
    String? notificationsError,
    bool clearNotificationsError = false,
    List<RecycleBinItem>? recycleBin,
    bool? recycleBinLoading,
    String? recycleBinError,
    bool clearRecycleBinError = false,
    List<InviteLinkModel>? inviteLinks,
    List<SignupRequestModel>? signupRequests,
    bool? invitesLoading,
    String? invitesError,
    bool clearInvitesError = false,
  }) {
    return AppState(
      currentUser: currentUser ?? this.currentUser,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isSessionLoading: isSessionLoading ?? this.isSessionLoading,
      authError: clearAuthError ? null : (authError ?? this.authError),
      allUsers: allUsers ?? this.allUsers,
      usersLoading: usersLoading ?? this.usersLoading,
      usersError: clearUsersError ? null : (usersError ?? this.usersError),
      todayAttendance: clearTodayAttendance ? null : (todayAttendance ?? this.todayAttendance),
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      notificationsLoading: notificationsLoading ?? this.notificationsLoading,
      notificationsError: clearNotificationsError ? null : (notificationsError ?? this.notificationsError),
      recycleBin: recycleBin ?? this.recycleBin,
      recycleBinLoading: recycleBinLoading ?? this.recycleBinLoading,
      recycleBinError: clearRecycleBinError ? null : (recycleBinError ?? this.recycleBinError),
      inviteLinks: inviteLinks ?? this.inviteLinks,
      signupRequests: signupRequests ?? this.signupRequests,
      invitesLoading: invitesLoading ?? this.invitesLoading,
      invitesError: clearInvitesError ? null : (invitesError ?? this.invitesError),
    );
  }
}

String _message(Object e) {
  if (e is ApiException) {
    return e.isNetworkError ? 'Could not reach the server. Check your connection and try again.' : e.message;
  }
  return 'Something went wrong. Please try again.';
}

List<Map<String, dynamic>> _listAt(dynamic res, String key) {
  if (res is Map && res[key] is List) {
    return (res[key] as List).whereType<Map<String, dynamic>>().toList();
  }
  return const [];
}

class AppStateNotifier extends StateNotifier<AppState> {
  final ApiClient _api = ApiClient();

  AppStateNotifier() : super(AppState(currentUser: AppState.defaultGuestUser())) {
    _api.onUnauthorized = () {
      if (state.isAuthenticated) logout();
    };
    bootstrap();
  }

  // ---------------------------------------------------------------- session

  Future<void> bootstrap() async {
    state = state.copyWith(isSessionLoading: true, clearAuthError: true);
    try {
      final token = await AuthStorage.getToken();
      if (token == null || token.isEmpty) {
        state = AppState(currentUser: AppState.defaultGuestUser(), isSessionLoading: false);
        return;
      }
      await _loadSignedInUser();
      state = state.copyWith(isAuthenticated: true, isSessionLoading: false);
      await refreshAllData();
    } catch (_) {
      state = AppState(currentUser: AppState.defaultGuestUser(), isSessionLoading: false);
    }
  }

  Future<void> login({required String email, required String password, bool remember = true}) async {
    state = state.copyWith(isSessionLoading: true, clearAuthError: true);
    try {
      final res = await _api.post('/api/auth/login', body: {
        'email': email.trim(),
        'password': password,
        'remember': remember,
      });
      final token = res is Map ? res['token']?.toString() : null;
      if (token == null || token.isEmpty) {
        throw ApiException(statusCode: 500, message: 'The server did not return a session token.');
      }
      await AuthStorage.saveSession(token: token, remember: remember, email: email.trim());
      await _loadSignedInUser();
      state = state.copyWith(isAuthenticated: true, isSessionLoading: false);
      await refreshAllData();
    } catch (e) {
      state = state.copyWith(isAuthenticated: false, isSessionLoading: false, authError: _message(e));
      rethrow;
    }
  }

  /// Loads `/api/auth/me` and the active organization (`/api/org/current`), and pins that
  /// organization for all later requests (`X-Organization-Id`).
  Future<void> _loadSignedInUser() async {
    final meJson = await _api.get('/api/auth/me');
    if (meJson is! Map<String, dynamic>) {
      throw ApiException(statusCode: 500, message: 'Unexpected response from /api/auth/me');
    }
    var user = UserModel.fromJson(meJson);
    // Platform admins get the admin experience inside their organization.
    if (user.isPlatformAdmin) user = user.copyWith(role: UserRole.admin);
    try {
      final org = await _api.get('/api/org/current');
      if (org is Map && org['organization'] is Map) {
        final o = org['organization'] as Map;
        await AuthStorage.setOrgId(o['id']?.toString());
        user = user.copyWith(organizationId: o['id']?.toString(), organizationName: o['name']?.toString());
      }
    } on ApiException catch (e) {
      // Public self-sign-ups have no organization yet; everything else is a real error.
      if (!e.isForbidden) rethrow;
    }
    state = state.copyWith(currentUser: user);
  }

  Future<void> logout() async {
    try {
      await _api.post('/api/auth/logout');
    } catch (_) {
      // Signing out locally must work even when the server is unreachable.
    }
    await AuthStorage.clearSession();
    state = AppState(currentUser: AppState.defaultGuestUser(), isSessionLoading: false);
  }

  /// Keep the session after `/api/profile/change-password`, which signs out old tokens.
  Future<void> adoptNewToken(String? token) async {
    if (token != null && token.isNotEmpty) await AuthStorage.updateToken(token);
  }

  Future<void> refreshAllData() async {
    final user = state.currentUser;
    await Future.wait([
      fetchNotifications(),
      if (user.role == UserRole.intern) fetchTodayAttendance(),
      if (user.isAdmin || user.role == UserRole.mentor) fetchInviteLinks(),
      if (user.isAdmin) fetchRecycleBin(),
    ]);
  }

  Future<void> fetchCurrentUser() async {
    await _loadSignedInUser();
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['skills'] is List) {
      payload['skills'] = (payload['skills'] as List)
          .map((s) => s.toString().trim())
          .where((s) => s.isNotEmpty)
          .join(', ');
    }
    await _api.put('/api/profile', body: payload);
    await _loadSignedInUser();
  }

  /// Upload a new profile photo (`POST /api/upload/avatar`) and show it everywhere.
  Future<void> uploadAvatar(File image) async {
    final file = await http.MultipartFile.fromPath('file', image.path);
    final res = await _api.postMultipart('/api/upload/avatar', files: [file]);
    final url = res is Map ? res['avatar_url']?.toString() : null;
    if (url != null && url.isNotEmpty) {
      state = state.copyWith(currentUser: state.currentUser.copyWith(avatarUrl: url));
    }
  }

  // ---------------------------------------------------------------- attendance (intern)

  Future<void> fetchTodayAttendance() async {
    final res = await _api.get('/api/attendance/today');
    final rec = res is Map ? res['record'] : null;
    if (rec is Map<String, dynamic>) {
      state = state.copyWith(todayAttendance: AttendanceRecord.fromJson(rec));
    } else {
      state = state.copyWith(clearTodayAttendance: true);
    }
  }

  Future<void> checkIn({required File photo, required double latitude, required double longitude}) async {
    await _postAttendance('/api/attendance/check-in', photo, latitude, longitude);
  }

  /// Check-out needs the same selfie and location as check-in.
  Future<void> checkOut({required File photo, required double latitude, required double longitude}) async {
    await _postAttendance('/api/attendance/check-out', photo, latitude, longitude);
  }

  Future<void> _postAttendance(String path, File photo, double latitude, double longitude) async {
    final file = await http.MultipartFile.fromPath('photo', photo.path);
    final res = await _api.postMultipart(
      path,
      fields: {'lat': latitude.toString(), 'lng': longitude.toString()},
      files: [file],
    );
    if (res is Map<String, dynamic>) {
      state = state.copyWith(todayAttendance: AttendanceRecord.fromJson(res));
    } else {
      await fetchTodayAttendance();
    }
  }

  // ---------------------------------------------------------------- notifications

  Future<void> fetchNotifications() async {
    state = state.copyWith(notificationsLoading: true, clearNotificationsError: true);
    try {
      final res = await _api.get('/api/notifications');
      state = state.copyWith(
        notifications: _listAt(res, 'notifications').map(NotificationItem.fromJson).toList(),
        unreadCount: res is Map ? (res['unread_count'] as num?)?.toInt() ?? 0 : 0,
        notificationsLoading: false,
      );
    } catch (e) {
      state = state.copyWith(notificationsLoading: false, notificationsError: _message(e));
    }
  }

  /// Badge count from `GET /api/notifications/unread-count` (cheap; called on resume).
  Future<void> fetchUnreadCount() async {
    try {
      final res = await _api.get('/api/notifications/unread-count');
      if (res is Map && res['count'] is num) {
        state = state.copyWith(unreadCount: (res['count'] as num).toInt());
      }
    } catch (_) {
      // The badge keeps its last value; the notification screen shows real errors.
    }
  }

  /// The API marks every notification read at once (there is no per-item call).
  Future<void> markAllNotificationsRead() async {
    await _api.post('/api/notifications/mark-read');
    state = state.copyWith(
      notifications: state.notifications.map((n) => n.copyWith(isRead: true)).toList(),
      unreadCount: 0,
    );
  }

  Future<void> deleteNotification(String id) async {
    await _api.delete('/api/notifications/$id');
    final removed = state.notifications.where((n) => n.id == id).toList();
    state = state.copyWith(
      notifications: state.notifications.where((n) => n.id != id).toList(),
      unreadCount: removed.any((n) => !n.isRead) ? (state.unreadCount - 1).clamp(0, 1 << 30) : state.unreadCount,
    );
  }

  // ---------------------------------------------------------------- users

  /// One page of `/api/admin/users` (admins: everyone in the org, mentors: their interns).
  Future<Map<String, dynamic>> fetchUsers({String? role, String? search, int page = 1, int pageSize = 20}) async {
    state = state.copyWith(usersLoading: true, clearUsersError: true);
    try {
      final isMentor = state.currentUser.role == UserRole.mentor;
      final query = <String, dynamic>{'page': page, 'page_size': pageSize};
      if (isMentor) {
        query['role'] = 'intern';
      } else if (role != null && role.isNotEmpty && role != 'all') {
        query['role'] = role;
      }
      if (search != null && search.trim().isNotEmpty) query['search'] = search.trim();

      final res = await _api.get('/api/admin/users', queryParameters: query);
      final list = _listAt(res, 'users').map(UserModel.fromJson).toList();
      state = state.copyWith(allUsers: list, usersLoading: false);
      return {
        'page': (res['page'] as num?)?.toInt() ?? page,
        'total_pages': (res['total_pages'] as num?)?.toInt() ?? 1,
        'total': (res['total'] as num?)?.toInt() ?? list.length,
        'page_size': (res['page_size'] as num?)?.toInt() ?? pageSize,
        'counts': res['counts'] is Map ? Map<String, dynamic>.from(res['counts'] as Map) : const <String, dynamic>{},
        'users': list,
      };
    } catch (e) {
      state = state.copyWith(usersLoading: false, usersError: _message(e));
      rethrow;
    }
  }

  /// Every user of the organization (all pages), for directory-style screens.
  Future<void> fetchAllUsers() async {
    state = state.copyWith(usersLoading: true, clearUsersError: true);
    try {
      final all = <UserModel>[];
      var page = 1;
      var totalPages = 1;
      do {
        final res = await _api.get('/api/admin/users', queryParameters: {'page': page, 'page_size': 100});
        all.addAll(_listAt(res, 'users').map(UserModel.fromJson));
        totalPages = (res['total_pages'] as num?)?.toInt() ?? 1;
        page++;
      } while (page <= totalPages);
      state = state.copyWith(allUsers: all, usersLoading: false);
    } catch (e) {
      state = state.copyWith(usersLoading: false, usersError: _message(e));
    }
  }

  Future<List<UserModel>> fetchMentorsForPicker({String? search, int page = 1, int pageSize = 20}) async {
    final query = <String, dynamic>{'page': page, 'page_size': pageSize, 'role': 'mentor'};
    if (search != null && search.trim().isNotEmpty) query['search'] = search.trim();
    final res = await _api.get('/api/admin/users', queryParameters: query);
    return _listAt(res, 'users').map(UserModel.fromJson).toList();
  }

  Future<void> createUser(Map<String, dynamic> data) async {
    await _api.post('/api/admin/users', body: data);
  }

  Future<void> updateUser(String id, Map<String, dynamic> data) async {
    await _api.put('/api/admin/users/$id', body: data);
  }

  Future<void> changeUserRole(String id, UserRole role) async {
    await _api.post('/api/admin/users/$id/role', body: {'role': role.toApiValue()});
  }

  /// Add an existing account (e.g. a public sign-up) or a new person to this organization.
  Future<void> addOrganizationMember(Map<String, dynamic> data) async {
    await _api.post('/api/org/members', body: data);
  }

  Future<void> toggleUserActive(String id) async {
    await _api.post('/api/admin/users/$id/toggle');
    state = state.copyWith(
      allUsers: state.allUsers.map((u) => u.id == id ? u.copyWith(isActive: !u.isActive) : u).toList(),
    );
  }

  Future<void> deleteUser(String id) async {
    await _api.delete('/api/admin/users/$id');
    state = state.copyWith(allUsers: state.allUsers.where((u) => u.id != id).toList());
  }

  Future<UserProfileOverview?> fetchUserOverview(String userId) async {
    final res = await _api.get('/api/users/$userId/overview');
    return res is Map<String, dynamic> ? UserProfileOverview.fromJson(res) : null;
  }

  // ---------------------------------------------------------------- invite links

  Future<void> fetchInviteLinks() async {
    state = state.copyWith(invitesLoading: true, clearInvitesError: true);
    try {
      final res = await _api.get('/api/admin/invite-link');
      final reqRes = await _api.get('/api/admin/intern-signup-requests');
      state = state.copyWith(
        inviteLinks: _listAt(res, 'links').map(InviteLinkModel.fromJson).toList(),
        signupRequests: _listAt(reqRes, 'requests').map(SignupRequestModel.fromJson).toList(),
        invitesLoading: false,
      );
    } catch (e) {
      state = state.copyWith(invitesLoading: false, invitesError: _message(e));
    }
  }

  Future<void> createInviteLink({required String label, String? mentorId}) async {
    await _api.post('/api/admin/invite-link', body: {
      'label': label,
      if (mentorId != null && mentorId.isNotEmpty) 'mentor_id': int.tryParse(mentorId) ?? mentorId,
    });
    await fetchInviteLinks();
  }

  Future<void> deleteInviteLink(String id) async {
    await _api.delete('/api/admin/invite-link/$id');
    await fetchInviteLinks();
  }

  /// Replaces this organization's active links with a new one (old URLs stop working).
  Future<void> regenerateInviteLink() async {
    await _api.post('/api/admin/invite-link/regenerate');
    await fetchInviteLinks();
  }

  /// Turns off every active invite link of this organization.
  Future<void> deactivateInviteLinks() async {
    await _api.post('/api/admin/invite-link/deactivate');
    await fetchInviteLinks();
  }

  Future<void> reviewSignupRequest(String userId, {required bool approve}) async {
    await _api.post('/api/admin/intern-signup-requests/$userId/review',
        body: {'decision': approve ? 'approved' : 'rejected'});
    await fetchInviteLinks();
  }

  // ---------------------------------------------------------------- recycle bin (admin)

  Future<void> fetchRecycleBin() async {
    state = state.copyWith(recycleBinLoading: true, clearRecycleBinError: true);
    try {
      final res = await _api.get('/api/admin/bin', queryParameters: {'page_size': 100});
      state = state.copyWith(
        recycleBin: _listAt(res, 'items').map(RecycleBinItem.fromJson).toList(),
        recycleBinLoading: false,
      );
    } catch (e) {
      state = state.copyWith(recycleBinLoading: false, recycleBinError: _message(e));
    }
  }

  Future<void> restoreRecycleItem(String id) async {
    await _api.post('/api/admin/bin/$id/restore');
    state = state.copyWith(recycleBin: state.recycleBin.where((r) => r.id != id).toList());
  }

  Future<void> permanentlyDeleteRecycleItem(String id) async {
    await _api.delete('/api/admin/bin/$id');
    state = state.copyWith(recycleBin: state.recycleBin.where((r) => r.id != id).toList());
  }

  Future<void> clearRecycleBin() async {
    await _api.delete('/api/admin/bin');
    state = state.copyWith(recycleBin: const []);
  }

  /// Platform admins only: wipes application data for every organization.
  Future<void> clearDatabase(String password) async {
    await _api.post('/api/admin/clear-database', body: {'password': password});
    await logout();
  }
}

final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});
