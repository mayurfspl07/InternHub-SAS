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

  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.mentor:
        return 'Mentor';
      case UserRole.superadmin:
        return 'Super admin';
      case UserRole.intern:
        return 'Intern';
    }
  }
}

/// A user as returned by `/api/auth/me`, `/api/admin/users` and `/api/profile`.
class UserModel {
  final String id;
  final String name;
  final String email;
  final UserRole role;
  final bool isActive;
  final bool isPlatformAdmin;
  final String? bio;
  final String? department;
  final List<String> skills;
  final String? phone;
  final String? jobTitle;
  final String? joiningDate;
  final String? mentorId;
  final String? mentorName;
  final String? avatarUrl;
  final int? internshipDurationMonths;
  final String? internshipEndDate;
  final bool? isPaid;
  final double? stipendAmount;

  /// Filled from `GET /api/org/current` for the signed-in user (not part of user payloads).
  final String? organizationId;
  final String? organizationName;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.isActive = true,
    this.isPlatformAdmin = false,
    this.bio,
    this.department,
    this.skills = const [],
    this.phone,
    this.jobTitle,
    this.joiningDate,
    this.mentorId,
    this.mentorName,
    this.avatarUrl,
    this.internshipDurationMonths,
    this.internshipEndDate,
    this.isPaid,
    this.stipendAmount,
    this.organizationId,
    this.organizationName,
  });

  /// Org admins and platform admins get the admin experience inside their organization.
  bool get isAdmin => role == UserRole.admin || role == UserRole.superadmin || isPlatformAdmin;

  bool get isMentor => role == UserRole.mentor;

  bool get isIntern => role == UserRole.intern && !isPlatformAdmin;

  /// Role used for navigation and permissions: platform admins act as admins.
  UserRole get effectiveRole => isAdmin ? UserRole.admin : role;

  String get roleTitle {
    final title = jobTitle?.trim() ?? '';
    return title.isNotEmpty ? title : role.label;
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<String> parsedSkills = [];
    if (json['skills'] is List) {
      parsedSkills = (json['skills'] as List).map((e) => e.toString()).toList();
    } else if (json['skills'] is String && json['skills'].toString().isNotEmpty) {
      parsedSkills = json['skills'].toString().split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }

    bool flag(dynamic v) => v == true || v == 1 || v?.toString() == 'true';

    return UserModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: UserRole.fromString(json['role']?.toString()),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      isPlatformAdmin: flag(json['is_platform_admin']) || flag(json['is_superadmin']),
      bio: json['bio']?.toString(),
      department: json['department']?.toString(),
      skills: parsedSkills,
      phone: json['phone']?.toString(),
      jobTitle: json['job_title']?.toString(),
      joiningDate: json['joining_date']?.toString(),
      mentorId: json['mentor_id']?.toString(),
      mentorName: json['mentor_name']?.toString(),
      avatarUrl: (json['avatar_url']?.toString().isNotEmpty ?? false) ? json['avatar_url'].toString() : null,
      internshipDurationMonths: (json['internship_duration_months'] as num?)?.toInt(),
      internshipEndDate: json['internship_end_date']?.toString(),
      isPaid: json['is_paid'] is bool ? json['is_paid'] as bool : null,
      stipendAmount: (json['stipend_amount'] as num?)?.toDouble(),
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
      'avatar_url': avatarUrl,
      'internship_duration_months': internshipDurationMonths,
      'is_paid': isPaid,
      'stipend_amount': stipendAmount,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    UserRole? role,
    bool? isActive,
    bool? isPlatformAdmin,
    String? bio,
    String? department,
    List<String>? skills,
    String? phone,
    String? jobTitle,
    String? joiningDate,
    String? mentorId,
    String? mentorName,
    String? avatarUrl,
    int? internshipDurationMonths,
    String? internshipEndDate,
    bool? isPaid,
    double? stipendAmount,
    String? organizationId,
    String? organizationName,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      isPlatformAdmin: isPlatformAdmin ?? this.isPlatformAdmin,
      bio: bio ?? this.bio,
      department: department ?? this.department,
      skills: skills ?? this.skills,
      phone: phone ?? this.phone,
      jobTitle: jobTitle ?? this.jobTitle,
      joiningDate: joiningDate ?? this.joiningDate,
      mentorId: mentorId ?? this.mentorId,
      mentorName: mentorName ?? this.mentorName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      internshipDurationMonths: internshipDurationMonths ?? this.internshipDurationMonths,
      internshipEndDate: internshipEndDate ?? this.internshipEndDate,
      isPaid: isPaid ?? this.isPaid,
      stipendAmount: stipendAmount ?? this.stipendAmount,
      organizationId: organizationId ?? this.organizationId,
      organizationName: organizationName ?? this.organizationName,
    );
  }
}
