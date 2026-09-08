class SubmissionModel {
  final String id;
  final String assignmentId;
  final String userId;
  final String userName;
  final String? submissionText;
  final String? githubUrl;
  final String? fileUrl;
  final String status; // 'submitted', 'reviewed', 'resubmit'
  final double? score;
  final String? feedback;
  final DateTime submittedAt;

  const SubmissionModel({
    required this.id,
    required this.assignmentId,
    required this.userId,
    required this.userName,
    this.submissionText,
    this.githubUrl,
    this.fileUrl,
    this.status = 'submitted',
    this.score,
    this.feedback,
    required this.submittedAt,
  });

  factory SubmissionModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return SubmissionModel(
      id: json['id']?.toString() ?? '',
      assignmentId: json['assignment_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['user']?['id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? json['user']?['name']?.toString() ?? 'Intern',
      submissionText: json['submission_text']?.toString(),
      githubUrl: json['github_url']?.toString(),
      fileUrl: json['file_url']?.toString(),
      status: json['status']?.toString() ?? 'submitted',
      score: (json['score'] ?? json['grade'] as num?)?.toDouble(),
      feedback: json['feedback']?.toString() ?? json['review_feedback']?.toString(),
      submittedAt: parseDate(json['submitted_at'] ?? json['created_at']),
    );
  }
}

class AssignmentModel {
  final String id;
  final String title;
  final String description;
  final DateTime? dueDate;
  final String? cohortId;
  final String? projectId;
  final String? createdBy;
  final String status;
  final List<SubmissionModel> submissions;
  final DateTime createdAt;

  const AssignmentModel({
    required this.id,
    required this.title,
    required this.description,
    this.dueDate,
    this.cohortId,
    this.projectId,
    this.createdBy,
    this.status = 'active',
    this.submissions = const [],
    required this.createdAt,
  });

  factory AssignmentModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    DateTime? parseNullableDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    List<SubmissionModel> subs = [];
    if (json['submissions'] is List) {
      subs = (json['submissions'] as List)
          .whereType<Map<String, dynamic>>()
          .map((s) => SubmissionModel.fromJson(s))
          .toList();
    }

    return AssignmentModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Assignment',
      description: json['description']?.toString() ?? '',
      dueDate: parseNullableDate(json['due_date'] ?? json['deadline']),
      cohortId: json['cohort_id']?.toString(),
      projectId: json['project_id']?.toString(),
      createdBy: json['created_by']?.toString(),
      status: json['status']?.toString() ?? 'active',
      submissions: subs,
      createdAt: parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'due_date': dueDate?.toIso8601String(),
      'cohort_id': cohortId,
      'project_id': projectId,
    };
  }
}
