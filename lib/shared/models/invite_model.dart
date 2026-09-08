class InviteLinkModel {
  final String id;
  final String token;
  final String label;
  final String? mentorId;
  final String? mentorName;
  final int usageCount;
  final int? maxUses;
  final bool isActive;
  final DateTime createdAt;

  const InviteLinkModel({
    required this.id,
    required this.token,
    required this.label,
    this.mentorId,
    this.mentorName,
    this.usageCount = 0,
    this.maxUses,
    this.isActive = true,
    required this.createdAt,
  });

  String get inviteUrl => 'https://internhub.io/join/$token';

  factory InviteLinkModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return InviteLinkModel(
      id: json['id']?.toString() ?? '',
      token: json['token']?.toString() ?? json['invite_code']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Intern Onboarding Link',
      mentorId: json['mentor_id']?.toString(),
      mentorName: json['mentor_name']?.toString() ?? json['mentor']?['name']?.toString(),
      usageCount: (json['usage_count'] ?? json['uses'] as num?)?.toInt() ?? 0,
      maxUses: (json['max_uses'] as num?)?.toInt(),
      isActive: json['is_active'] is bool ? json['is_active'] as bool : true,
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'token': token,
      'label': label,
      'mentor_id': mentorId,
    };
  }
}

class SignupRequestModel {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? department;
  final String? jobTitle;
  final String? joiningDate;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime createdAt;

  const SignupRequestModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.department,
    this.jobTitle,
    this.joiningDate,
    this.status = 'pending',
    required this.createdAt,
  });

  factory SignupRequestModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return SignupRequestModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Applicant',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      department: json['department']?.toString(),
      jobTitle: json['job_title']?.toString(),
      joiningDate: json['joining_date']?.toString(),
      status: json['status']?.toString() ?? 'pending',
      createdAt: parseDate(json['created_at']),
    );
  }
}
