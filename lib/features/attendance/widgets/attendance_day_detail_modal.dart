import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/attendance_model.dart';
import '../attendance_repository.dart';
import 'authed_attendance_image.dart';

class AttendanceDayDetailModal extends StatefulWidget {
  final DateTime date;
  final AttendanceRecord? record;
  final String status;
  final int? actorId;

  const AttendanceDayDetailModal({
    super.key,
    required this.date,
    this.record,
    required this.status,
    this.actorId,
  });

  static Future<void> show(
    BuildContext context, {
    required DateTime date,
    AttendanceRecord? record,
    required String status,
    int? actorId,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AttendanceDayDetailModal(
        date: date,
        record: record,
        status: status,
        actorId: actorId,
      ),
    );
  }

  @override
  State<AttendanceDayDetailModal> createState() => _AttendanceDayDetailModalState();
}

class _AttendanceDayDetailModalState extends State<AttendanceDayDetailModal> {
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoadingTasks = false;

  @override
  void initState() {
    super.initState();
    _loadAudits();
  }

  Future<void> _loadAudits() async {
    final actorId = widget.actorId ?? widget.record?.userId;
    if (actorId == null) return;

    setState(() => _isLoadingTasks = true);
    final dateStr = DateFormat('yyyy-MM-dd').format(widget.date);
    try {
      final logs = await AttendanceRepository().fetchDayTaskAudits(
        actorId: actorId,
        date: dateStr,
      );
      if (mounted) {
        setState(() {
          _tasks = logs;
          _isLoadingTasks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTasks = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return AppColors.success;
      case 'late':
        return AppColors.warning; // Amber/Yellow
      case 'half_day':
      case 'halfday':
        return AppColors.info; // Sky Blue
      case 'absent':
        return AppColors.danger; // Red
      case 'on_leave':
      case 'leave':
        return AppColors.lavenderInk; // Purple
      case 'excused':
        return AppColors.success; // Teal
      case 'week_off':
      case 'off':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == 'null') return '—';
    try {
      if (timeStr.contains('T')) {
        final dt = DateTime.parse(timeStr);
        return DateFormat('hh:mm a').format(dt);
      }
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final dt = DateTime(2026, 1, 1, h, m);
        return DateFormat('hh:mm a').format(dt);
      }
      return timeStr;
    } catch (_) {
      return timeStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateTitle = DateFormat('EEEE, MMMM d, yyyy').format(widget.date);
    final statusColor = _getStatusColor(widget.status);
    final displayStatus = widget.status.replaceAll('_', ' ').toUpperCase();

    final loginStr = _formatTime(widget.record?.checkIn);
    final logoutStr = _formatTime(widget.record?.checkOut);
    final hoursStr = widget.record?.hoursWorked != null
        ? '${widget.record!.hoursWorked!.toStringAsFixed(1)}h'
        : '0.0h';

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        side: BorderSide(
          color: AppColors.border,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          dateTitle,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                          ),
                          child: Text(
                            displayStatus,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Detailed shift verification, selfie photos, GPS coordinates, and task audit trail.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Login / Logout / Hours boxes
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildMetricBox(
                              context: context,
                              title: 'LOGIN',
                              value: loginStr,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricBox(
                              context: context,
                              title: 'LOGOUT',
                              value: logoutStr,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricBox(
                              context: context,
                              title: 'HOURS',
                              value: hoursStr,
                              isYellow: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Check-in & Check-out Photo Cards
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CHECK-IN PHOTO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              AspectRatio(
                                aspectRatio: 1.0,
                                child: AuthedAttendanceImage(
                                  attendanceId: widget.record?.id,
                                  photoType: 'checkin',
                                  photoUrl: widget.record?.checkInPhotoUrl,
                                  fallbackLabel: 'No check-in photo',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CHECK-OUT PHOTO',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              AspectRatio(
                                aspectRatio: 1.0,
                                child: AuthedAttendanceImage(
                                  attendanceId: widget.record?.id,
                                  photoType: 'checkout',
                                  photoUrl: widget.record?.checkOutPhotoUrl,
                                  fallbackLabel: 'No check-out photo',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Location Cards
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildLocationCard(
                              title: 'Check-in Location',
                              location: widget.record?.checkInLocation,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildLocationCard(
                              title: 'Check-out Location',
                              location: widget.record?.checkOutLocation,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Tasks Completed / Modified on this Day
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppSpacing.r16),
                        border: Border.all(
                          color: AppColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.format_list_bulleted_rounded,
                                size: 18,
                                color: AppColors.warning, // Orange list icon
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tasks Completed / Modified on this Day',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_isLoadingTasks)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          else if (_tasks.isEmpty)
                            Text(
                              'No task activity recorded on this date.',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: AppColors.textTertiary,
                              ),
                            )
                          else
                            ..._tasks.map((t) {
                              final taskTitle = t['task_title'] ?? t['title'] ?? t['name'] ?? 'Updated Task';
                              final changeType = t['action'] ?? t['type'] ?? 'modified';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$taskTitle ($changeType)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Modal Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: BorderSide(
                      color: AppColors.border,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox({
    required BuildContext context,
    required String title,
    required String value,
    bool isYellow = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: isYellow
            ? AppColors.primary
            : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        border: Border.all(
          color: isYellow
              ? Colors.transparent
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isYellow
                  ? AppColors.warningInk
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isYellow
                  ? AppColors.ink
                  : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCard({
    required String title,
    required AttendanceLocation? location,
  }) {
    final hasLoc = location != null && (location.lat != 0.0 || location.lng != 0.0);
    final address = location?.address ??
        (hasLoc ? '${location.lat.toStringAsFixed(4)}, ${location.lng.toStringAsFixed(4)}' : 'No location logged');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.location_on_outlined,
            size: 20,
            color: AppColors.danger, // Red pin
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  address,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
