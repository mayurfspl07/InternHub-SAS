enum UserRole {
  intern,
  mentor,
  admin,
  superadmin;

  static UserRole fromString(String? val) {
    if (val == null) return UserRole.intern;
    switch (val.toLowerCase().trim()) {
      case 'admin':
        return UserRole.admin;
      case 'mentor':
        return UserRole.mentor;
      case 'superadmin':
        return UserRole.superadmin;
      case 'intern':
      default:
        return UserRole.intern;
    }
  }

  String toApiValue() {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.mentor:
        return 'mentor';
      case UserRole.superadmin:
        return 'superadmin';
      case UserRole.intern:
        return 'intern';
    }
  }
}

class UserModel {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final bool isActive;
  final String? bio;
  final String? department;
  final List<String> skills;
  final String? phone;
  final String? jobTitle;
  final String? joiningDate;
  final String? mentorId;
  final String? mentorName;
  final String? organizationId;
  final String? organizationName;
  final String? avatarUrl;

  // Visual / UI metrics (from user overview or fallback)
  final double performanceRating;
  final int attendanceStreak;
  final int completedTasks;
  final int streakCoins;
  final String? cohortName;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.isActive = true,
    this.bio,
    this.department,
    this.skills = const [],
    this.phone,
    this.jobTitle,
    this.joiningDate,
    this.mentorId,
    this.mentorName,
    this.organizationId,
    this.organizationName,
    this.avatarUrl,
    this.performanceRating = 4.8,
    this.attendanceStreak = 0,
    this.completedTasks = 0,
    this.streakCoins = 0,
    this.cohortName,
  });

  String get roleTitle {
    if (jobTitle != null && jobTitle!.trim().isNotEmpty) {
      return jobTitle!;
    }
    switch (role) {
      case UserRole.admin:
        return 'Administrator';
      case UserRole.mentor:
        return 'Technical Mentor';
      case UserRole.superadmin:
        return 'Super Administrator';
      case UserRole.intern:
        return 'Engineering Intern';
    }
  }

  String get location => 'Remote / Office';
  bool get isBiometricEnabled => false;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<String> parsedSkills = [];
    if (json['skills'] is List) {
      parsedSkills = (json['skills'] as List).map((e) => e.toString()).toList();
    } else if (json['skills'] is String && json['skills'].toString().isNotEmpty) {
      parsedSkills = json['skills'].toString().split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      email: json['email']?.toString() ?? '',
      role: UserRole.fromString(json['role']?.toString()),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      bio: json['bio']?.toString(),
      department: json['department']?.toString(),
      skills: parsedSkills,
      phone: json['phone']?.toString(),
      jobTitle: json['job_title']?.toString(),
      joiningDate: json['joining_date']?.toString(),
      mentorId: json['mentor_id']?.toString(),
      mentorName: json['mentor_name']?.toString(),
      organizationId: json['organization_id']?.toString(),
      organizationName: json['organization_name']?.toString(),
      avatarUrl: json['avatar_url']?.toString() ?? json['avatar']?.toString(),
      performanceRating: (json['performance_rating'] as num?)?.toDouble() ?? 4.8,
      attendanceStreak: (json['attendance_streak'] as num?)?.toInt() ?? 0,
      completedTasks: (json['completed_tasks'] as num?)?.toInt() ?? 0,
      streakCoins: (json['streak_coins'] as num?)?.toInt() ?? 0,
      cohortName: json['cohort_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role.toApiValue(),
      'is_active': isActive,
      'bio': bio,
      'department': department,
      'skills': skills.join(', '),
      'phone': phone,
      'job_title': jobTitle,
      'joining_date': joiningDate,
      'mentor_id': mentorId,
      'mentor_name': mentorName,
      'organization_id': organizationId,
      'organization_name': organizationName,
      'avatar_url': avatarUrl,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    bool? isActive,
    String? bio,
    String? department,
    List<String>? skills,
    String? phone,
    String? jobTitle,
    String? joiningDate,
    String? mentorId,
    String? mentorName,
    String? organizationId,
    String? organizationName,
    String? avatarUrl,
    double? performanceRating,
    int? attendanceStreak,
    int? completedTasks,
    int? streakCoins,
    String? cohortName,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      bio: bio ?? this.bio,
      department: department ?? this.department,
      skills: skills ?? this.skills,
      phone: phone ?? this.phone,
      jobTitle: jobTitle ?? this.jobTitle,
      joiningDate: joiningDate ?? this.joiningDate,
      mentorId: mentorId ?? this.mentorId,
      mentorName: mentorName ?? this.mentorName,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      performanceRating: performanceRating ?? this.performanceRating,
      attendanceStreak: attendanceStreak ?? this.attendanceStreak,
      completedTasks: completedTasks ?? this.completedTasks,
      streakCoins: streakCoins ?? this.streakCoins,
      cohortName: cohortName ?? this.cohortName,
    );
  }
}
