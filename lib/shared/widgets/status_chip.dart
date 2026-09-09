import 'package:flutter/material.dart';
import '../../core/constants/app_spacing.dart';
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
        return const Color(0xFFEDE9FE);
      case StatusType.success:
        return const Color(0xFFD1FAE5);
      case StatusType.warning:
        return const Color(0xFFFEF3C7);
      case StatusType.danger:
      case StatusType.error:
        return const Color(0xFFFEE2E2);
      case StatusType.info:
        return const Color(0xFFE0F2FE);
      case StatusType.neutral:
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  static Color _resolveText(StatusType? type) {
    switch (type) {
      case StatusType.primary:
        return const Color(0xFF7B61FF);
      case StatusType.success:
        return const Color(0xFF047857);
      case StatusType.warning:
        return const Color(0xFFB45309);
      case StatusType.danger:
      case StatusType.error:
        return const Color(0xFFB91C1C);
      case StatusType.info:
        return const Color(0xFF0369A1);
      case StatusType.neutral:
      default:
        return const Color(0xFF374151);
    }
  }

  factory StatusChip.fromAttendance(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return const StatusChip(
          label: 'Present',
          backgroundColor: Color(0xFFD1FAE5),
          textColor: Color(0xFF065F46),
          icon: Icons.check_circle_rounded,
        );
      case AttendanceStatus.late:
        return const StatusChip(
          label: 'Late Check-in',
          backgroundColor: Color(0xFFFEF3C7),
          textColor: Color(0xFF92400E),
          icon: Icons.access_time_rounded,
        );
      case AttendanceStatus.halfDay:
        return const StatusChip(
          label: 'Half Day',
          backgroundColor: Color(0xFFFFEDD5),
          textColor: Color(0xFF9A3412),
          icon: Icons.timelapse_rounded,
        );
      case AttendanceStatus.absent:
        return const StatusChip(
          label: 'Absent',
          backgroundColor: Color(0xFFFEE2E2),
          textColor: Color(0xFF991B1B),
          icon: Icons.cancel_rounded,
        );
      case AttendanceStatus.leave:
      case AttendanceStatus.onLeave:
        return const StatusChip(
          label: 'On Leave',
          backgroundColor: Color(0xFFEDE9FE),
          textColor: Color(0xFF5B21B6),
          icon: Icons.beach_access_rounded,
        );
      case AttendanceStatus.excused:
        return const StatusChip(
          label: 'Excused',
          backgroundColor: Color(0xFFE0F2FE),
          textColor: Color(0xFF075985),
          icon: Icons.info_outline_rounded,
        );
      case AttendanceStatus.weekOff:
        return const StatusChip(
          label: 'Off',
          backgroundColor: Color(0xFFF3F4F6),
          textColor: Color(0xFF4B5563),
        );
      case AttendanceStatus.notJoined:
        return const StatusChip(
          label: 'Not Joined',
          backgroundColor: Color(0xFFF3F4F6),
          textColor: Color(0xFF9CA3AF),
        );
      case AttendanceStatus.upcoming:
        return const StatusChip(
          label: 'Upcoming',
          backgroundColor: Color(0xFFF3F4F6),
          textColor: Color(0xFF9CA3AF),
        );
    }
  }

  factory StatusChip.fromKanban(KanbanStatus status) {
    switch (status) {
      case KanbanStatus.todo:
        return const StatusChip(
          label: 'To Do',
          backgroundColor: Color(0xFFF3F4F6),
          textColor: Color(0xFF374151),
        );
      case KanbanStatus.inProgress:
        return const StatusChip(
          label: 'In Progress',
          backgroundColor: Color(0xFFE0F2FE),
          textColor: Color(0xFF0369A1),
        );
      case KanbanStatus.inReview:
        return const StatusChip(
          label: 'In Review',
          backgroundColor: Color(0xFFFEF3C7),
          textColor: Color(0xFFB45309),
        );
      case KanbanStatus.completed:
        return const StatusChip(
          label: 'Completed',
          backgroundColor: Color(0xFFD1FAE5),
          textColor: Color(0xFF047857),
        );
    }
  }

  factory StatusChip.fromPriority(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return const StatusChip(
          label: 'Low',
          backgroundColor: Color(0xFFF3F4F6),
          textColor: Color(0xFF4B5563),
        );
      case TaskPriority.medium:
        return const StatusChip(
          label: 'Medium',
          backgroundColor: Color(0xFFFEF3C7),
          textColor: Color(0xFF92400E),
        );
      case TaskPriority.high:
        return const StatusChip(
          label: 'High',
          backgroundColor: Color(0xFFFFEDD5),
          textColor: Color(0xFFC2410C),
        );
      case TaskPriority.urgent:
        return const StatusChip(
          label: 'Urgent',
          backgroundColor: Color(0xFFFEE2E2),
          textColor: Color(0xFFB91C1C),
        );
    }
  }

  factory StatusChip.fromLeave(LeaveStatus status) {
    switch (status) {
      case LeaveStatus.pending:
        return const StatusChip(
          label: 'Pending Approval',
          backgroundColor: Color(0xFFFEF3C7),
          textColor: Color(0xFFB45309),
          icon: Icons.hourglass_top_rounded,
        );
      case LeaveStatus.approved:
        return const StatusChip(
          label: 'Approved',
          backgroundColor: Color(0xFFD1FAE5),
          textColor: Color(0xFF047857),
          icon: Icons.check_circle_rounded,
        );
      case LeaveStatus.rejected:
        return const StatusChip(
          label: 'Rejected',
          backgroundColor: Color(0xFFFEE2E2),
          textColor: Color(0xFFB91C1C),
          icon: Icons.highlight_off_rounded,
        );
    }
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
