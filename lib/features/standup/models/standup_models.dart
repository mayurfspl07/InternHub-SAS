import 'package:intl/intl.dart';
import '../../../shared/models/user_model.dart';

class StandupLog {
  final int id;
  final int userId;
  final String? userName;
  final String date; // YYYY-MM-DD
  final String did;
  final String plan;
  final String? blockers;
  final String mood; // great | good | okay | tired | stressed, or '' when not recorded
  final String createdAt;
  final String? updatedAt;

  const StandupLog({
    required this.id,
    required this.userId,
    this.userName,
    required this.date,
    required this.did,
    required this.plan,
    this.blockers,
    this.mood = '',
    required this.createdAt,
    this.updatedAt,
  });

  bool get hasBlockers {
    if (blockers == null) return false;
    final b = blockers!.trim().toLowerCase().replaceAll('.', '');
    return b.isNotEmpty && b != 'none' && b != 'no blockers';
  }

  factory StandupLog.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    String parseDate(dynamic v) {
      if (v == null) return DateTime.now().toIso8601String().substring(0, 10);
      final s = v.toString();
      if (s.length >= 10) return s.substring(0, 10);
      return s;
    }

    return StandupLog(
      id: toInt(json['id']),
      userId: toInt(json['user_id'] ?? json['user']?['id']),
      userName: json['user_name']?.toString() ?? json['user']?['name']?.toString() ?? 'Team Member',
      date: parseDate(json['date']),
      did: json['did']?.toString() ?? json['yesterday_work']?.toString() ?? '',
      plan: json['plan']?.toString() ?? json['today_plan']?.toString() ?? '',
      blockers: json['blockers']?.toString(),
      mood: json['mood']?.toString().toLowerCase().trim() ?? '',
      createdAt: json['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      if (userName != null) 'user_name': userName,
      'date': date,
      'did': did,
      'plan': plan,
      'blockers': blockers ?? 'None',
      'mood': mood,
      'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    };
  }
}

class StandupListResponse {
  final List<StandupLog> logs;
  final int page;
  final int totalPages;
  final int total;

  const StandupListResponse({
    required this.logs,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  factory StandupListResponse.fromJson(dynamic raw) {
    int toInt(dynamic v, [int fallback = 0]) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? fallback;
    }

    List rawLogs = [];
    int page = 1;
    int totalPages = 1;
    int total = 0;

    if (raw is List) {
      rawLogs = raw;
      total = raw.length;
    } else if (raw is Map<String, dynamic>) {
      if (raw['logs'] is List) {
        rawLogs = raw['logs'];
      } else if (raw['items'] is List) {
        rawLogs = raw['items'];
      } else if (raw['data'] is List) {
        rawLogs = raw['data'];
      }
      page = toInt(raw['page'], 1);
      totalPages = toInt(raw['total_pages'] ?? raw['totalPages'], 1);
      total = toInt(raw['total'] ?? raw['total_records'], rawLogs.length);
    }

    final logs = rawLogs
        .whereType<Map<String, dynamic>>()
        .map((m) => StandupLog.fromJson(m))
        .toList();

    return StandupListResponse(
      logs: logs,
      page: page,
      totalPages: totalPages,
      total: total,
    );
  }
}

// Mood definition
class StandupMoodOption {
  final String value;
  final String label;
  final String emoji;

  const StandupMoodOption({
    required this.value,
    required this.label,
    required this.emoji,
  });
}

/// The moods the API stores (`MOOD_OPTIONS` in routes/api/standup.py).
const List<StandupMoodOption> standupMoodOptions = [
  StandupMoodOption(value: 'great', label: 'Great', emoji: '🔥'),
  StandupMoodOption(value: 'good', label: 'Good', emoji: '😊'),
  StandupMoodOption(value: 'okay', label: 'Okay', emoji: '😐'),
  StandupMoodOption(value: 'tired', label: 'Tired', emoji: '😴'),
  StandupMoodOption(value: 'stressed', label: 'Stressed', emoji: '😫'),
];

StandupMoodOption? _moodOption(String mood) {
  final key = mood.toLowerCase().trim();
  for (final opt in standupMoodOptions) {
    if (opt.value == key) return opt;
  }
  return null;
}

/// Label for a stored mood; empty when no mood was recorded.
String getMoodLabel(String mood) => _moodOption(mood)?.label ?? '';

String getMoodEmoji(String mood) => _moodOption(mood)?.emoji ?? '';

/// The API lets only the author or an admin edit or delete a standup.
bool canManageLog(int logUserId, UserModel currentUser) {
  if (int.tryParse(currentUser.id) == logUserId || currentUser.id == logUserId.toString()) return true;
  return currentUser.isAdmin;
}

// Date helpers
String formatDisplayDate(String? yyyyMmDd) {
  if (yyyyMmDd == null || yyyyMmDd.isEmpty) return '';
  final parts = yyyyMmDd.split('-');
  if (parts.length == 3) {
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year != null && month != null && day != null) {
      final dt = DateTime(year, month, day);
      return DateFormat('MMM d, yyyy').format(dt);
    }
  }
  return yyyyMmDd;
}

String formatDisplayTime(String? dateTimeStr) {
  if (dateTimeStr == null || dateTimeStr.isEmpty) return '';
  final dt = DateTime.tryParse(dateTimeStr);
  if (dt == null) return '';
  return DateFormat('h:mm a').format(dt.toLocal());
}
