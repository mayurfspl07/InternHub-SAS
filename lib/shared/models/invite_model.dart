/// An intern invite link from `GET /api/admin/invite-link` (`links[]`).
class InviteLinkModel {
  final String id;
  final String token;
  final String url;
  final String label;
  final String? mentorId;
  final String? mentorName;
  final String? createdById;
  final String? createdByName;
  final int usageCount;
  final bool isActive;
  final DateTime createdAt;

  const InviteLinkModel({
    required this.id,
    required this.token,
    required this.url,
    required this.label,
    this.mentorId,
    this.mentorName,
    this.createdById,
    this.createdByName,
    this.usageCount = 0,
    this.isActive = true,
    required this.createdAt,
  });

  factory InviteLinkModel.fromJson(Map<String, dynamic> json) {
    return InviteLinkModel(
      id: json['id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      mentorId: json['mentor_id']?.toString(),
      mentorName: json['mentor_name']?.toString(),
      createdById: json['created_by_id']?.toString(),
      createdByName: json['created_by_name']?.toString(),
      usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}

/// A pending intern sign-up from `GET /api/admin/intern-signup-requests` (`requests[]`).
class SignupRequestModel {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? department;
  final String? jobTitle;
  final String? inviteLabel;
  final String? mentorName;
  final String? linkCreatorName;
  final DateTime createdAt;

  const SignupRequestModel({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.department,
    this.jobTitle,
    this.inviteLabel,
    this.mentorName,
    this.linkCreatorName,
    required this.createdAt,
  });

  factory SignupRequestModel.fromJson(Map<String, dynamic> json) {
    String? str(String key) {
      final v = json[key]?.toString();
      return (v == null || v.isEmpty) ? null : v;
    }

    return SignupRequestModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: str('phone'),
      department: str('department'),
      jobTitle: str('job_title'),
      inviteLabel: str('invite_label'),
      mentorName: str('mentor_name'),
      linkCreatorName: str('link_creator_name'),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}
