import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
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
          label: 'Late Check-in',
          statusType: StatusType.warning,
          icon: Icons.access_time_rounded,
        );
      case AttendanceStatus.halfDay:
        return const StatusChip(
          label: 'Half Day',
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
          label: 'On Leave',
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
          label: 'Not Joined',
          backgroundColor: AppColors.neutralSoft,
          textColor: AppColors.textTertiary,
        );
      case AttendanceStatus.upcoming:
        return const StatusChip(
          label: 'Upcoming',
          backgroundColor: AppColors.neutralSoft,
          textColor: AppColors.textTertiary,
        );
    }
  }

  factory StatusChip.fromKanban(KanbanStatus status) {
    switch (status) {
      case KanbanStatus.todo:
        return const StatusChip(label: 'To Do', statusType: StatusType.neutral);
      case KanbanStatus.inProgress:
        return const StatusChip(label: 'In Progress', statusType: StatusType.info);
      case KanbanStatus.inReview:
        return const StatusChip(label: 'In Review', statusType: StatusType.warning);
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
      case TaskPriority.urgent:
        return const StatusChip(label: 'Urgent', statusType: StatusType.danger);
    }
  }

  factory StatusChip.fromLeave(LeaveStatus status) {
    switch (status) {
      case LeaveStatus.pending:
        return const StatusChip(
          label: 'Pending Approval',
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

  factory StatusChip.onTrack({String label = 'On Track'}) {
    return StatusChip(label: label, statusType: StatusType.success, icon: Icons.check_circle_rounded);
  }

  factory StatusChip.atRisk({String label = 'At Risk'}) {
    return StatusChip(label: label, statusType: StatusType.danger, icon: Icons.warning_amber_rounded);
  }

  factory StatusChip.pending({String label = 'Pending'}) {
    return StatusChip(label: label, statusType: StatusType.warning, icon: Icons.hourglass_empty_rounded);
  }

  factory StatusChip.completed({String label = 'Completed'}) {
    return StatusChip(label: label, statusType: StatusType.success, icon: Icons.done_all_rounded);
  }

  factory StatusChip.inProgress({String label = 'In Progress'}) {
    return StatusChip(label: label, statusType: StatusType.info, icon: Icons.timelapse_rounded);
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
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(color: text),
            ),
          ),
        ],
      ),
    );
  }
}
