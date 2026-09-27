import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_client.dart';
import '../../core/api/auth_storage.dart';
import '../../shared/models/profile_overview_model.dart';
import '../../shared/models/user_model.dart';

class ProfileRepository {
  static final ProfileRepository _instance = ProfileRepository._internal();
  factory ProfileRepository() => _instance;
  ProfileRepository._internal();

  final ApiClient _client = ApiClient();

  /// GET /api/profile — fetch fresh profile
  Future<UserModel> getProfile() async {
    final res = await _client.get('/api/profile');
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic>
          ? res['data'] as Map<String, dynamic>
          : (res['user'] is Map<String, dynamic> ? res['user'] as Map<String, dynamic> : res);
      return UserModel.fromJson(data);
    }
    throw Exception('Failed to load user profile');
  }

  /// PUT /api/profile — update bio, phone, skills only
  Future<UserModel> updateProfile({
    String? bio,
    String? phone,
    String? skills,
  }) async {
    final payload = <String, dynamic>{
      'bio': (bio != null && bio.trim().isNotEmpty) ? bio.trim() : null,
      'phone': normalizePhoneForSubmit(phone),
      'skills': (skills != null && skills.trim().isNotEmpty) ? skills.trim() : null,
    };

    final res = await _client.put('/api/profile', body: payload);
    if (res is Map<String, dynamic>) {
      final data = res['data'] is Map<String, dynamic>
          ? res['data'] as Map<String, dynamic>
          : (res['user'] is Map<String, dynamic> ? res['user'] as Map<String, dynamic> : res);
      return UserModel.fromJson(data);
    }
    throw Exception('Failed to update profile');
  }

  /// GET /api/users/{userId}/overview — intern sections + export 360
  Future<UserProfileOverview> getUserOverview(String userId) async {
    final res = await _client.get('/api/users/$userId/overview');
    if (res is Map<String, dynamic>) {
      return UserProfileOverview.fromJson(res);
    }
    throw Exception('Failed to load user overview');
  }

  /// POST /api/profile/change-password
  Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final payload = {
      'current_password': currentPassword,
      'new_password': newPassword,
      'confirm_password': confirmPassword,
    };
    final res = await _client.post('/api/profile/change-password', body: payload);
    // Changing the password signs out every old session; keep this one with the new token.
    final token = res is Map ? res['token']?.toString() : null;
    if (token != null && token.isNotEmpty) await AuthStorage.updateToken(token);
    return res is Map<String, dynamic> ? res : const {'ok': true};
  }

  /// Export Profile 360° Data (all roles)
  /// Builds CSV / text report matching web excel export
  Future<void> exportProfile360(UserModel user, {UserProfileOverview? overview}) async {
    final StringBuffer csv = StringBuffer();
    final role = user.role.toApiValue().toLowerCase();

    // 1. Common Summary Section
    csv.writeln('=== PROFILE SUMMARY ===');
    csv.writeln('Field,Value');
    csv.writeln('Member ID,"#${user.id}"');
    csv.writeln('Name,"${user.name}"');
    csv.writeln('Email,"${user.email}"');
    csv.writeln('Role,"${user.role.name.toUpperCase()}"');
    csv.writeln('Status,"${user.isActive ? "Active" : "Inactive"}"');
    csv.writeln('Phone,"${user.phone ?? "Not configured"}"');
    csv.writeln('Department,"${user.department ?? "Not assigned"}"');
    csv.writeln('Job Title,"${user.jobTitle ?? "Not specified"}"');
    csv.writeln('Joining Date,"${user.joiningDate ?? "Not set"}"');
    if (role == 'intern') {
      csv.writeln('Assigned Mentor,"${user.mentorName ?? "Not assigned"}"');
    }
    csv.writeln('Organization,"${user.organizationName ?? "InternHub"}"');
    csv.writeln('Bio,"${(user.bio ?? "").replaceAll('"', '""')}"');
    csv.writeln('Skills,"${user.skills.join(", ")}"');
    csv.writeln('');

    if (overview != null) {
      if (role == 'intern') {
        // Intern Metrics Summary
        final attSummary = overview.resolvedAttendanceSummary;
        final leaveSummary = overview.resolvedLeaveSummary;

        csv.writeln('=== QUICK METRICS ===');
        csv.writeln('Metric,Value');
        csv.writeln('Assigned Projects,${overview.totalProjectsCount}');
        csv.writeln('Active Tasks,${overview.activeTasksCount}');
        csv.writeln('Completed Tasks,${overview.completedTasksCount}');
        csv.writeln('Present (30d),${attSummary.present} days');
        csv.writeln('Late (30d),${attSummary.late} days');
        csv.writeln('Half-Day (30d),${attSummary.halfDay} days');
        csv.writeln('Absent / Leave (30d),${attSummary.absentIncludingLeave} days');
        csv.writeln('Leave Total Applied,${leaveSummary.total}');
        csv.writeln('Leave Approved,${leaveSummary.approved}');
        csv.writeln('Leave Pending,${leaveSummary.pending}');
        csv.writeln('Leave Rejected,${leaveSummary.rejected}');
        csv.writeln('Leave Days Taken,${leaveSummary.daysTaken}');
        if (overview.leaveBalance != null) {
          csv.writeln('Leave Quota,${overview.leaveBalance!.quota}');
          csv.writeln('Leave Remaining,${overview.leaveBalance!.remaining}');
        }
        csv.writeln('');

        // Projects Table
        csv.writeln('=== PROJECTS ===');
        csv.writeln('ID,Name,Status,Progress %,Start Date,End Date');
        for (final p in overview.projects) {
          csv.writeln('${p.id},"${p.name}","${p.status}",${p.progress},"${p.startDate ?? ""}","${p.endDate ?? ""}"');
        }
        csv.writeln('');

        // Tasks Table
        csv.writeln('=== TASKS ===');
        csv.writeln('ID,Title,Project,Status,Priority,Due Date');
        for (final t in overview.tasks) {
          csv.writeln('${t.id},"${t.title}","${t.projectName ?? t.projectId}","${t.status}","${t.priority}","${t.dueDate ?? ""}"');
        }
        csv.writeln('');

        // Attendance Table
        csv.writeln('=== ATTENDANCE (LAST 30 DAYS) ===');
        csv.writeln('Date,Status,Check In,Check Out,Hours');
        for (final a in overview.attendance) {
          csv.writeln('"${a.date}","${a.status}","${a.checkIn ?? ""}","${a.checkOut ?? ""}",${a.hours ?? 0}');
        }
        csv.writeln('');

        // Leave Requests Table
        csv.writeln('=== LEAVE REQUESTS ===');
        csv.writeln('ID,Type,Start Date,End Date,Days,Status,Reason');
        for (final l in overview.leaveRequests) {
          csv.writeln('${l.id},"${l.typeLabel}","${l.start_date}","${l.end_date}",${l.days},"${l.status}","${l.reason.replaceAll('"', '""')}"');
        }
      } else if (role == 'mentor') {
        // Mentor Projects & Interns
        csv.writeln('=== PROJECTS SUPERVISED ===');
        csv.writeln('ID,Name,Status,Progress %');
        for (final p in overview.projects) {
          csv.writeln('${p.id},"${p.name}","${p.status}",${p.progress}');
        }
        csv.writeln('');

        csv.writeln('=== INTERNS SUPERVISED ===');
        csv.writeln('ID,Name,Email,Status,Department');
        for (final i in overview.interns) {
          csv.writeln('${i.id},"${i.name}","${i.email}","${i.isActive ? "Active" : "Inactive"}","${i.department ?? ""}"');
        }
      }
    }

    final sanitizedName = user.name.toLowerCase().replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final fileName = 'profile_${sanitizedName}_360.csv';

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(csv.toString());

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Profile 360° Data for ${user.name}',
      subject: 'Profile 360° - ${user.name}',
    );
  }
}
