enum StandupMood {
  crushingIt, // 🔥
  productive, // 😊
  neutral,    // 😐
  blocked,    // 😫
  exhausted;  // 😴

  static StandupMood fromString(String? val) {
    if (val == null) return StandupMood.productive;
    switch (val.toLowerCase().trim()) {
      case 'crushing_it':
      case 'crushingit':
      case 'fire':
      case '🔥':
        return StandupMood.crushingIt;
      case 'neutral':
      case '😐':
        return StandupMood.neutral;
      case 'blocked':
      case 'struggling':
      case '😫':
        return StandupMood.blocked;
      case 'exhausted':
      case 'tired':
      case '😴':
        return StandupMood.exhausted;
      case 'productive':
      case '😊':
      default:
        return StandupMood.productive;
    }
  }

  String toApiValue() {
    switch (this) {
      case StandupMood.crushingIt:
        return 'crushing_it';
      case StandupMood.neutral:
        return 'neutral';
      case StandupMood.blocked:
        return 'blocked';
      case StandupMood.exhausted:
        return 'exhausted';
      case StandupMood.productive:
        return 'productive';
    }
  }

  String get emoji {
    switch (this) {
      case StandupMood.crushingIt:
        return '🔥';
      case StandupMood.neutral:
        return '😐';
      case StandupMood.blocked:
        return '😫';
      case StandupMood.exhausted:
        return '😴';
      case StandupMood.productive:
        return '😊';
    }
  }
}

class StandupModel {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final DateTime date;
  final String yesterdayWork;
  final String todayPlan;
  final String blockers;
  final StandupMood mood;
  final List<String> mentorFeedback;
  final int cheerCount;

  const StandupModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.date,
    required this.yesterdayWork,
    required this.todayPlan,
    required this.blockers,
    this.mood = StandupMood.productive,
    this.mentorFeedback = const [],
    this.cheerCount = 4,
  });

  factory StandupModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return StandupModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['user']?['id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? json['user']?['name']?.toString() ?? 'Intern',
      userAvatar: json['user_avatar']?.toString() ?? json['user']?['avatar_url']?.toString() ?? '',
      date: parseDate(json['date'] ?? json['created_at']),
      yesterdayWork: json['did']?.toString() ?? json['yesterday_work']?.toString() ?? '',
      todayPlan: json['plan']?.toString() ?? json['today_plan']?.toString() ?? '',
      blockers: json['blockers']?.toString() ?? '',
      mood: StandupMood.fromString(json['mood']?.toString()),
      cheerCount: (json['cheer_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String().substring(0, 10),
      'did': yesterdayWork,
      'plan': todayPlan,
      'blockers': blockers,
      'mood': mood.toApiValue(),
    };
  }

  StandupModel copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatar,
    DateTime? date,
    String? yesterdayWork,
    String? todayPlan,
    String? blockers,
    StandupMood? mood,
    List<String>? mentorFeedback,
    int? cheerCount,
  }) {
    return StandupModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatar: userAvatar ?? this.userAvatar,
      date: date ?? this.date,
      yesterdayWork: yesterdayWork ?? this.yesterdayWork,
      todayPlan: todayPlan ?? this.todayPlan,
      blockers: blockers ?? this.blockers,
      mood: mood ?? this.mood,
      mentorFeedback: mentorFeedback ?? this.mentorFeedback,
      cheerCount: cheerCount ?? this.cheerCount,
    );
  }
}
