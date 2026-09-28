import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../shared/widgets/status_chip.dart';
import '../models/dashboard_models.dart';

/// White rounded card with the soft shadow; tappable when [onTap] is set.
class DashboardTile extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsets padding;

  const DashboardTile({super.key, this.onTap, required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppSpacing.rTile);
    return Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: AppShadows.soft),
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Project name, status, member/task counts and a progress bar.
class DashboardProjectTile extends StatelessWidget {
  final String name;
  final String status;
  final String? subtitle;
  final int membersCount;
  final int completedTasks;
  final int totalTasks;
  final double progress;
  final VoidCallback? onTap;

  const DashboardProjectTile({
    super.key,
    required this.name,
    required this.status,
    this.subtitle,
    required this.membersCount,
    required this.completedTasks,
    required this.totalTasks,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round();
    return DashboardTile(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip.fromString(status),
            ],
          ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!.trim(), style: AppTypography.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${plural(membersCount, 'member')} · $completedTasks/$totalTasks tasks done',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ),
              const SizedBox(width: 8),
              Text('$pct%', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

StatusType priorityStatusType(String priority) {
  final p = priority.toLowerCase();
  if (p == 'high' || p == 'urgent') return StatusType.danger;
  if (p == 'medium') return StatusType.warning;
  return StatusType.neutral;
}

/// Due-date chip: "Due 30 Sep", or red "Overdue · 30 Sep".
Widget dueChip(String? deadline, bool overdue) => StatusChip(
      icon: Icons.access_time_rounded,
      label: overdue
          ? 'Overdue · ${formatDate(deadline, withYear: false)}'
          : 'Due ${formatDate(deadline, withYear: false)}',
      statusType: overdue ? StatusType.danger : StatusType.neutral,
    );

/// A team task: title, project and assignee, priority and due date.
class DashboardTaskTile extends StatelessWidget {
  final MentorDashboardTask task;
  final VoidCallback? onTap;

  const DashboardTaskTile({super.key, required this.task, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = task;
    return DashboardTile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            '${t.projectName ?? 'No project'} · ${t.assignedUserName ?? 'Unassigned'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              StatusChip(label: humanize(t.priority), statusType: priorityStatusType(t.priority)),
              if (t.deadline != null) dueChip(t.deadline, t.isOverdue),
            ],
          ),
        ],
      ),
    );
  }
}

/// A pending leave request with Approve / Reject. Buttons disable while [busy].
class DashboardLeaveReviewCard extends StatelessWidget {
  final MentorDashboardLeaveRequest leave;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const DashboardLeaveReviewCard({
    super.key,
    required this.leave,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l = leave;
    return DashboardTile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(fallbackText: l.userName, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${humanize(l.leaveType)} leave · ${plural(l.days, 'day')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(formatDateRange(l.startDate, l.endDate), style: AppTypography.caption.copyWith(color: AppColors.ink)),
          if (l.reason != null && l.reason!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              l.reason!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onReject,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerInk,
                    side: const BorderSide(color: AppColors.danger),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks why a leave request is being rejected. Returns the reason, or null if cancelled.
Future<String?> askRejectReason(BuildContext context, String name) =>
    showDialog<String>(context: context, builder: (_) => _RejectLeaveDialog(name: name));

class _RejectLeaveDialog extends StatefulWidget {
  final String name;

  const _RejectLeaveDialog({required this.name});

  @override
  State<_RejectLeaveDialog> createState() => _RejectLeaveDialogState();
}

class _RejectLeaveDialogState extends State<_RejectLeaveDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _reason.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Add a reason so ${widget.name} knows why');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Reject leave?'),
      content: TextField(
        controller: _reason,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: 'Reason',
          hintText: 'Shared with ${widget.name}',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
          onPressed: _submit,
          child: const Text('Reject'),
        ),
      ],
    );
  }
}
