class SkillRating {
  final String skillName;
  final double score; // 0.0 - 5.0

  const SkillRating({
    required this.skillName,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
    'skill_name': skillName,
    'score': score,
  };
}

class ReviewModel {
  final String id;
  final String internId;
  final String internName;
  final String internAvatar;
  final String mentorName;
  final String mentorAvatar;
  final DateTime reviewDate;
  final double overallRating;
  final double technicalRating;
  final double communicationRating;
  final double initiativeRating;
  final List<SkillRating> skills;
  final String strengths;
  final String areasForImprovement;
  final String generalFeedback;
  final String quarterLabel;

  const ReviewModel({
    required this.id,
    required this.internId,
    required this.internName,
    required this.internAvatar,
    required this.mentorName,
    required this.mentorAvatar,
    required this.reviewDate,
    required this.overallRating,
    this.technicalRating = 4.5,
    this.communicationRating = 4.5,
    this.initiativeRating = 4.5,
    this.skills = const [],
    required this.strengths,
    required this.areasForImprovement,
    required this.generalFeedback,
    this.quarterLabel = 'Q3 2026 Milestone',
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    final tech = (json['technical_rating'] as num?)?.toDouble() ?? 4.5;
    final comm = (json['communication_rating'] as num?)?.toDouble() ?? 4.5;
    final init = (json['initiative_rating'] as num?)?.toDouble() ?? 4.5;
    final overall = (json['rating'] as num?)?.toDouble() ?? (json['overall_rating'] as num?)?.toDouble() ?? ((tech + comm + init) / 3.0);

    return ReviewModel(
      id: json['id']?.toString() ?? '',
      internId: json['intern_id']?.toString() ?? json['user_id']?.toString() ?? '',
      internName: json['intern_name']?.toString() ?? json['user_name']?.toString() ?? 'Intern',
      internAvatar: json['intern_avatar']?.toString() ?? '',
      mentorName: json['reviewer_name']?.toString() ?? json['mentor_name']?.toString() ?? 'Mentor',
      mentorAvatar: json['reviewer_avatar']?.toString() ?? '',
      reviewDate: parseDate(json['created_at'] ?? json['review_date']),
      overallRating: overall,
      technicalRating: tech,
      communicationRating: comm,
      initiativeRating: init,
      skills: [
        SkillRating(skillName: 'Technical Proficiency', score: tech),
        SkillRating(skillName: 'Communication & Collaboration', score: comm),
        SkillRating(skillName: 'Initiative & Ownership', score: init),
      ],
      strengths: json['strengths']?.toString() ?? '',
      areasForImprovement: json['improvements']?.toString() ?? json['areas_for_improvement']?.toString() ?? '',
      generalFeedback: json['feedback']?.toString() ?? json['general_feedback']?.toString() ?? '',
      quarterLabel: json['evaluation_period']?.toString() ?? json['quarter_label']?.toString() ?? 'Current Period',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'intern_id': internId,
      'overall_rating': overallRating,
      'technical_rating': technicalRating,
      'communication_rating': communicationRating,
      'initiative_rating': initiativeRating,
      'feedback': generalFeedback,
      'strengths': strengths,
      'improvements': areasForImprovement,
      'evaluation_period': quarterLabel,
    };
  }

  ReviewModel copyWith({
    String? id,
    String? internId,
    String? internName,
    String? internAvatar,
    String? mentorName,
    String? mentorAvatar,
    DateTime? reviewDate,
    double? overallRating,
    double? technicalRating,
    double? communicationRating,
    double? initiativeRating,
    List<SkillRating>? skills,
    String? strengths,
    String? areasForImprovement,
    String? generalFeedback,
    String? quarterLabel,
  }) {
    return ReviewModel(
      id: id ?? this.id,
      internId: internId ?? this.internId,
      internName: internName ?? this.internName,
      internAvatar: internAvatar ?? this.internAvatar,
      mentorName: mentorName ?? this.mentorName,
      mentorAvatar: mentorAvatar ?? this.mentorAvatar,
      reviewDate: reviewDate ?? this.reviewDate,
      overallRating: overallRating ?? this.overallRating,
      technicalRating: technicalRating ?? this.technicalRating,
      communicationRating: communicationRating ?? this.communicationRating,
      initiativeRating: initiativeRating ?? this.initiativeRating,
      skills: skills ?? this.skills,
      strengths: strengths ?? this.strengths,
      areasForImprovement: areasForImprovement ?? this.areasForImprovement,
      generalFeedback: generalFeedback ?? this.generalFeedback,
      quarterLabel: quarterLabel ?? this.quarterLabel,
    );
  }
}
