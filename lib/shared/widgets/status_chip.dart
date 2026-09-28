import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../models/attendance_model.dart';
import '../models/project_model.dart';
import '../models/leave_model.dart';

enum StatusType {
  primary,
  success,
  warning,
  danger,
  error,
  info,
  neutral;
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final StatusType? statusType;

  const StatusChip({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.statusType,
    this.icon,
  });

  static Color _resolveBg(StatusType? type) {
    switch (type) {
      case StatusType.primary:
        return AppColors.primarySoft;
      case StatusType.success:
        return AppColors.successSoft;
      case StatusType.warning:
        return AppColors.warningSoft;
      case StatusType.danger:
      case StatusType.error:
        return AppColors.dangerSoft;
      case StatusType.info:
        return AppColors.infoSoft;
      case StatusType.neutral:
      default:
        return AppColors.neutralSoft;
    }
  }

  static Color _resolveText(StatusType? type) {
    switch (type) {
      case StatusType.primary:
        return AppColors.primaryInk;
      case StatusType.success:
        return AppColors.successInk;
      case StatusType.warning:
        return AppColors.warningInk;
      case StatusType.danger:
      case StatusType.error:
        return AppColors.dangerInk;
      case StatusType.info:
        return AppColors.infoInk;
      case StatusType.neutral:
      default:
        return AppColors.neutralInk;
    }
  }

  factory StatusChip.fromAttendance(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return const StatusChip(
          label: 'Present',
          statusType: StatusType.success,
          icon: Icons.check_circle_rounded,
        );
      case AttendanceStatus.late:
        return const StatusChip(
          label: 'Late',
          statusType: StatusType.warning,
          icon: Icons.access_time_rounded,
        );
      case AttendanceStatus.halfDay:
        return const StatusChip(
          label: 'Half day',
          backgroundColor: AppColors.peach,
          textColor: AppColors.peachInk,
          icon: Icons.timelapse_rounded,
        );
      case AttendanceStatus.absent:
        return const StatusChip(
          label: 'Absent',
          statusType: StatusType.danger,
          icon: Icons.cancel_rounded,
        );
      case AttendanceStatus.leave:
      case AttendanceStatus.onLeave:
        return const StatusChip(
          label: 'On leave',
          backgroundColor: AppColors.lavender,
          textColor: AppColors.lavenderInk,
          icon: Icons.beach_access_rounded,
        );
      case AttendanceStatus.excused:
        return const StatusChip(
          label: 'Excused',
          statusType: StatusType.info,
          icon: Icons.info_outline_rounded,
        );
      case AttendanceStatus.weekOff:
        return const StatusChip(label: 'Off', statusType: StatusType.neutral);
      case AttendanceStatus.notJoined:
        return const StatusChip(
          label: 'Not joined',
          backgroundColor: AppColors.neutralSoft,
          textColor: AppColors.textSecondary,
        );
      case AttendanceStatus.upcoming:
        return const StatusChip(
          label: 'Upcoming',
          backgroundColor: AppColors.neutralSoft,
          textColor: AppColors.textSecondary,
        );
    }
  }

  factory StatusChip.fromKanban(KanbanStatus status) {
    switch (status) {
      case KanbanStatus.todo:
        return const StatusChip(label: 'To do', statusType: StatusType.neutral);
      case KanbanStatus.inProgress:
        return const StatusChip(label: 'In progress', statusType: StatusType.info);
      case KanbanStatus.inReview:
        return const StatusChip(label: 'In review', statusType: StatusType.warning);
      case KanbanStatus.completed:
        return const StatusChip(label: 'Completed', statusType: StatusType.success);
    }
  }

  factory StatusChip.fromPriority(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return const StatusChip(label: 'Low', statusType: StatusType.neutral);
      case TaskPriority.medium:
        return const StatusChip(
          label: 'Medium',
          backgroundColor: AppColors.butter,
          textColor: AppColors.butterInk,
        );
      case TaskPriority.high:
        return const StatusChip(
          label: 'High',
          backgroundColor: AppColors.peach,
          textColor: AppColors.peachInk,
        );
    }
  }

  factory StatusChip.fromLeave(LeaveStatus status) {
    switch (status) {
      case LeaveStatus.pending:
        return const StatusChip(
          label: 'Pending',
          statusType: StatusType.warning,
          icon: Icons.hourglass_top_rounded,
        );
      case LeaveStatus.approved:
        return const StatusChip(
          label: 'Approved',
          statusType: StatusType.success,
          icon: Icons.check_circle_rounded,
        );
      case LeaveStatus.rejected:
        return const StatusChip(
          label: 'Rejected',
          statusType: StatusType.danger,
          icon: Icons.highlight_off_rounded,
        );
    }
  }

  factory StatusChip.onTrack({String label = 'On track'}) {
    return StatusChip(label: label, statusType: StatusType.success, icon: Icons.check_circle_rounded);
  }

  factory StatusChip.atRisk({String label = 'At risk'}) {
    return StatusChip(label: label, statusType: StatusType.danger, icon: Icons.warning_amber_rounded);
  }

  factory StatusChip.pending({String label = 'Pending'}) {
    return StatusChip(label: label, statusType: StatusType.warning, icon: Icons.hourglass_empty_rounded);
  }

  factory StatusChip.completed({String label = 'Completed'}) {
    return StatusChip(label: label, statusType: StatusType.success, icon: Icons.done_all_rounded);
  }

  factory StatusChip.inProgress({String label = 'In progress'}) {
    return StatusChip(label: label, statusType: StatusType.info, icon: Icons.timelapse_rounded);
  }

  /// Any status string from the API (task, project, leave, attendance, assignment, submission, user, mail log):
  /// "in_progress" → "In progress" in the matching color. [label] overrides the text.
  factory StatusChip.fromString(String? raw, {String? label, IconData? icon}) {
    final key = (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
    final text = label ?? _statusLabels[key] ?? humanize(raw);
    if (const {'on_leave', 'leave'}.contains(key)) {
      return StatusChip(
        label: text,
        backgroundColor: AppColors.lavender,
        textColor: AppColors.lavenderInk,
        icon: icon,
      );
    }
    return StatusChip(label: text.isEmpty ? 'Unknown' : text, statusType: statusTypeFor(key), icon: icon);
  }

  static const Map<String, String> _statusLabels = {
    'todo': 'To do',
    'in_progress': 'In progress',
    'in_review': 'In review',
    'review': 'In review',
    'testing': 'In review',
    'done': 'Done',
    'on_hold': 'On hold',
    'half_day': 'Half day',
    'on_leave': 'On leave',
    'needs_revision': 'Needs revision',
    'not_checked_in': 'Not checked in',
  };

  /// Color family for a status key (see [StatusChip.fromString]).
  static StatusType statusTypeFor(String key) {
    const success = {'done', 'completed', 'complete', 'approved', 'present', 'active', 'sent', 'reviewed', 'graded', 'published', 'delivered', 'success'};
    const info = {'in_progress', 'doing', 'ongoing', 'submitted', 'open', 'scheduled'};
    const warning = {'review', 'in_review', 'testing', 'pending', 'late', 'on_hold', 'resubmitted', 'needs_revision', 'half_day', 'planning', 'simulated', 'queued'};
    const danger = {'rejected', 'absent', 'failed', 'overdue', 'inactive', 'cancelled', 'canceled', 'error', 'bounced', 'expired'};
    if (success.contains(key)) return StatusType.success;
    if (info.contains(key)) return StatusType.info;
    if (warning.contains(key)) return StatusType.warning;
    if (danger.contains(key)) return StatusType.danger;
    return StatusType.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? _resolveBg(statusType);
    final text = textColor ?? _resolveText(statusType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: text),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(color: text),
            ),
          ),
        ],
      ),
    );
  }
}
