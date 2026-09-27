import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../activity_audit/models/activity_models.dart';
import '../../../shared/widgets/load_error_view.dart';

// ==========================================
// 1) SHARED HELPER FUNCTIONS
// ==========================================

String formatShortDate(dynamic dt) {
  if (dt == null) return '';
  DateTime? parsed;
  if (dt is DateTime) {
    parsed = dt;
  } else {
    parsed = DateTime.tryParse(dt.toString());
  }
  if (parsed == null) return dt.toString();
  return DateFormat('MMM d, yyyy').format(parsed);
}

String formatRelativeTime(dynamic dt) {
  if (dt == null) return 'Just now';
  DateTime? parsed;
  if (dt is DateTime) {
    parsed = dt;
  } else {
    parsed = DateTime.tryParse(dt.toString());
  }
  if (parsed == null) return 'Just now';

  final diff = DateTime.now().difference(parsed);
  if (diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(parsed);
}

String getInitials(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'U';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  return trimmed.substring(0, trimmed.length >= 2 ? 2 : 1).toUpperCase();
}

IconData getActivityIcon(String action) {
  final a = action.toLowerCase();
  if (a.startsWith('attendance.checkin')) return Icons.login_rounded;
  if (a.startsWith('attendance.checkout')) return Icons.logout_rounded;
  if (a.startsWith('task.create')) return Icons.add_task_rounded;
  if (a.startsWith('task.status')) return Icons.task_alt_rounded;
  if (a.startsWith('task.comment')) return Icons.chat_bubble_outline_rounded;
  if (a.startsWith('project.create')) return Icons.create_new_folder_outlined;
  if (a.startsWith('project.comment')) return Icons.chat_outlined;
  if (a.startsWith('leave.approved')) return Icons.check_circle_outline_rounded;
  if (a.startsWith('leave.request')) return Icons.calendar_today_rounded;
  if (a.startsWith('review.')) return Icons.rate_review_outlined;
  if (a.startsWith('user.')) return Icons.person_outline_rounded;
  return Icons.notifications_none_rounded;
}

void showPhotoModal(BuildContext context, String? photoUrl, String title) {
  if (photoUrl == null || photoUrl.trim().isEmpty) return;

  showDialog(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: AppColors.surfaceMuted,
                    child: const Center(child: Icon(Icons.broken_image_outlined, size: 40, color: AppColors.textTertiary)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

// ==========================================
// 3) SECTION TITLE WIDGET
// ==========================================
class DashboardSectionTitle extends StatelessWidget {
  final String title;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DashboardSectionTitle({
    super.key,
    required this.title,
    this.count,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = AppColors.ink;

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
            children: [
              Flexible(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.section.copyWith(color: primaryTextColor)),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(44, 32),
              ),
              child: Text(
                actionLabel!.replaceAll(' →', ''),
                style: AppTypography.caption.copyWith(fontSize: 13, color: AppColors.ink),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 4) KPI METRIC CARD
// ==========================================
class DashboardKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color? backgroundColor;

  const DashboardKpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    this.iconColor = AppColors.primary,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = backgroundColor ?? Colors.white;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: iconColor == AppColors.primary ? AppColors.primaryInk : iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryTextColor),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: secondaryTextColor),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ==========================================
// 5) EMPTY STATE WIDGET
// ==========================================
class DashboardEmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DashboardEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final secondaryTextColor = AppColors.textSecondary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: secondaryTextColor),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 6) SHIMMER LOADING SKELETON
// ==========================================
class DashboardLoadingSkeleton extends StatelessWidget {
  const DashboardLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final shimmerBase = AppColors.border;

    Widget buildBox(double height, {double? width, double radius = 16}) {
      return Container(
        height: height,
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          color: shimmerBase,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Skeleton
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildBox(24, width: 180, radius: 6),
                  const SizedBox(height: 8),
                  buildBox(14, width: 240, radius: 4),
                ],
              ),
              buildBox(40, width: 40, radius: 20),
            ],
          ),
          const SizedBox(height: 24),

          // Hero Card Skeleton
          buildBox(160),
          const SizedBox(height: 20),

          // Stat Strip Skeleton
          Row(
            children: [
              Expanded(child: buildBox(88)),
              const SizedBox(width: 12),
              Expanded(child: buildBox(88)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: buildBox(88)),
              const SizedBox(width: 12),
              Expanded(child: buildBox(88)),
            ],
          ),
          const SizedBox(height: 24),

          // Chart Skeleton
          buildBox(220),
          const SizedBox(height: 24),

          // List Items Skeleton
          buildBox(72),
          const SizedBox(height: 12),
          buildBox(72),
        ],
      ),
    );
  }
}

// ==========================================
// 7) QUERY ERROR STATE WITH RETRY
// ==========================================
class DashboardErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const DashboardErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return LoadErrorView(title: 'Unable to load dashboard', message: message, onRetry: onRetry);
  }
}

// ==========================================
// 8) ACTIVITY TIMELINE LIST
// ==========================================
class DashboardActivityTimeline extends StatefulWidget {
  final List<AuditLogEntry> activities;
  final VoidCallback? onViewAll;
  final int initialCount;

  const DashboardActivityTimeline({
    super.key,
    required this.activities,
    this.onViewAll,
    this.initialCount = 6,
  });

  @override
  State<DashboardActivityTimeline> createState() => _DashboardActivityTimelineState();
}

class _DashboardActivityTimelineState extends State<DashboardActivityTimeline> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    if (widget.activities.isEmpty) {
      return DashboardEmptyCard(
        icon: Icons.history_rounded,
        title: 'No recent activity',
        subtitle: 'Recent actions and changes will appear here.',
      );
    }

    final displayList = _expanded
        ? widget.activities
        : widget.activities.take(widget.initialCount).toList();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: borderColor),
            itemBuilder: (context, index) {
              final act = displayList[index];
              final icon = getActivityIcon(act.action);
              final timeAgo = formatRelativeTime(act.createdAt);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 18, color: AppColors.primaryInk),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                color: primaryTextColor,
                              ),
                              children: [
                                TextSpan(
                                  text: act.actorName,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                TextSpan(text: ' ${act.verb} '),
                                TextSpan(
                                  text: act.target,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            timeAgo,
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (widget.activities.length > widget.initialCount) ...[
            Divider(height: 1, color: borderColor),
            InkWell(
              onTap: () {
                setState(() {
                  _expanded = !_expanded;
                });
              },
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Text(
                  _expanded ? 'Show Less' : 'Show ${widget.activities.length - widget.initialCount} More',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryInk,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ==========================================
// KPI GRID
// ==========================================
/// Rows of [columns] KPI cards with equal heights; a lone card on the last
/// row stretches to full width instead of leaving a gap.
class DashboardKpiGrid extends StatelessWidget {
  final List<Widget> items;
  final int columns;
  final double spacing;

  const DashboardKpiGrid({
    super.key,
    required this.items,
    this.columns = 2,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += columns) {
      final rowItems = items.sublist(i, (i + columns).clamp(0, items.length));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int j = 0; j < rowItems.length; j++) ...[
                if (j > 0) SizedBox(width: spacing),
                Expanded(child: rowItems[j]),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        for (int r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: spacing),
          rows[r],
        ],
      ],
    );
  }
}
