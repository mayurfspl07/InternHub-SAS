import 'package:intl/intl.dart';

/// One place for how dates, times and API status keys read in the app.
/// Inputs may be a DateTime, an ISO string ("2026-09-27", "2026-09-27T09:05:32Z") or a bare time ("09:05:32").

DateTime? parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value.isUtc ? value.toLocal() : value;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed != null) return parsed.isUtc ? parsed.toLocal() : parsed;
  final time = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(text);
  if (time != null) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, int.parse(time.group(1)!), int.parse(time.group(2)!));
  }
  return null;
}

/// "27 Sep 2026" (or "27 Sep" when [withYear] is false). Empty string when missing.
String formatDate(dynamic value, {bool withYear = true, String fallback = ''}) {
  final d = parseDateTime(value);
  if (d == null) return value == null || value.toString().isEmpty ? fallback : value.toString();
  return DateFormat(withYear ? 'd MMM yyyy' : 'd MMM').format(d);
}

/// "9:05 AM". Empty string (or [fallback]) when missing.
String formatTime(dynamic value, {String fallback = ''}) {
  final d = parseDateTime(value);
  if (d == null) return fallback;
  return DateFormat('h:mm a').format(d);
}

/// "27 Sep 2026, 9:05 AM".
String formatDateTime(dynamic value, {String fallback = ''}) {
  final d = parseDateTime(value);
  if (d == null) return fallback;
  return DateFormat('d MMM yyyy, h:mm a').format(d);
}

/// "27–30 Sep 2026", "28 Sep – 2 Oct 2026", or a single date when both ends match.
String formatDateRange(dynamic start, dynamic end) {
  final a = parseDateTime(start);
  final b = parseDateTime(end);
  if (a == null) return formatDate(end);
  if (b == null || _sameDay(a, b)) return formatDate(a);
  if (a.year == b.year && a.month == b.month) return '${a.day}–${DateFormat('d MMM yyyy').format(b)}';
  if (a.year == b.year) return '${DateFormat('d MMM').format(a)} – ${DateFormat('d MMM yyyy').format(b)}';
  return '${formatDate(a)} – ${formatDate(b)}';
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "Just now", "5m ago", "3h ago", "2d ago", then "27 Sep".
String formatRelative(dynamic value) {
  final d = parseDateTime(value);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(d, withYear: d.year != DateTime.now().year);
}

/// "September 2026" from a DateTime or "2026-09".
String formatMonth(dynamic value) {
  if (value is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(value)) value = '$value-01';
  final d = parseDateTime(value);
  return d == null ? (value?.toString() ?? '') : DateFormat('MMMM yyyy').format(d);
}

/// Hours as "7.5h" / "8h".
String formatHours(num? hours) {
  if (hours == null) return '0h';
  return hours == hours.roundToDouble() ? '${hours.toInt()}h' : '${hours.toStringAsFixed(1)}h';
}

/// "1 member" / "3 members".
String plural(int count, String singular, [String? pluralForm]) =>
    '$count ${count == 1 ? singular : (pluralForm ?? '${singular}s')}';

/// API keys and enum values in sentence case: "in_progress" → "In progress", "HALF_DAY" → "Half day".
String humanize(String? raw) {
  final text = (raw ?? '').trim().replaceAll(RegExp(r'[_\-]+'), ' ').toLowerCase();
  if (text.isEmpty) return '';
  return text[0].toUpperCase() + text.substring(1);
}
