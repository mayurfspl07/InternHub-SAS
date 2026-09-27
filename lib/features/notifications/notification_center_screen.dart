import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/cohort_model.dart';
import '../../shared/widgets/load_error_view.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  String _selectedFilter = 'All';

  Widget _buildSegmentedTab(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  String _formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return m <= 1 ? 'just now' : '${m}m ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    return DateFormat('MMM d').format(dt);
  }

  /// Route inside the app for a notification's `link` (null when the app has no screen for it).
  String? _routeFor(String? link) {
    if (link == null || link.isEmpty) return null;
    if (link == '/') return '/dashboard';
    if (link.startsWith('/assignments')) return '/intern-assignments';
    const known = ['/projects', '/leave', '/invite-links', '/reviews', '/cohorts', '/announcements', '/attendance', '/standup'];
    return known.any((r) => link == r || link.startsWith('$r/')) ? link : null;
  }

  (IconData, Color, Color) _style(String kind) {
    switch (kind) {
      case 'leave':
        return (Icons.event_note_rounded, AppColors.peachInk, AppColors.peach);
      case 'task':
        return (Icons.task_alt_rounded, AppColors.info, AppColors.infoSoft);
      case 'assignment':
        return (Icons.assignment_outlined, AppColors.info, AppColors.infoSoft);
      case 'review':
        return (Icons.star_rounded, AppColors.warningInk, AppColors.warningSoft);
      case 'signup':
        return (Icons.person_add_rounded, AppColors.successInk, AppColors.successSoft);
      case 'cohort':
        return (Icons.groups_outlined, AppColors.lavenderInk, AppColors.lavender);
      default:
        return (Icons.notifications_rounded, AppColors.textSecondary, AppColors.surfaceMuted);
    }
  }

  Future<void> _markAllRead() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider.notifier).markAllNotificationsRead();
      messenger.showSnackBar(const SnackBar(content: Text('All notifications marked as read')));
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: 'Could not mark notifications as read');
    }
  }

  Future<void> _delete(NotificationItem notif) async {
    try {
      await ref.read(appStateProvider.notifier).deleteNotification(notif.id);
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: 'Could not delete the notification');
      await ref.read(appStateProvider.notifier).fetchNotifications();
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appStateProvider.notifier).fetchNotifications());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final notifications = state.notifications;
    final filtered = _selectedFilter == 'Unread' ? notifications.where((n) => !n.isRead).toList() : notifications;

    Widget body;
    if (state.notificationsLoading && notifications.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.notificationsError != null && notifications.isEmpty) {
      body = LoadErrorView(
        title: 'Couldn\'t load notifications',
        message: state.notificationsError!,
        onRetry: () => ref.read(appStateProvider.notifier).fetchNotifications(),
      );
    } else if (filtered.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.22),
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_none_rounded, size: 48, color: AppColors.textSecondary),
                SizedBox(height: 16),
                Text('All caught up!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.ink)),
                SizedBox(height: 6),
                Text('No notifications to show here.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      );
    } else {
      body = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final notif = filtered[index];
          final (icon, iconColor, iconBg) = _style(notif.kind);
          final route = _routeFor(notif.link);
          return Dismissible(
            key: Key(notif.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            onDismissed: (_) => _delete(notif),
            child: GestureDetector(
              onTap: route == null ? null : () => Navigator.of(context).pushNamed(route),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppShadows.soft,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Icon(icon, color: iconColor, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        notif.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          fontWeight: notif.isRead ? FontWeight.w500 : FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatRelative(notif.createdAt),
                          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                        if (!notif.isRead) ...[
                          const SizedBox(height: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Notifications',
                    padding: EdgeInsets.zero,
                    actions: [
                      if (state.unreadCount > 0)
                        HeaderAction(icon: Icons.done_all_rounded, tooltip: 'Mark all read', onTap: _markAllRead),
                      HeaderAction(
                        icon: Icons.refresh_rounded,
                        tooltip: 'Refresh',
                        onTap: () => ref.read(appStateProvider.notifier).fetchNotifications(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildSegmentedTab('All', 'All'),
                        _buildSegmentedTab(state.unreadCount > 0 ? 'Unread (${state.unreadCount})' : 'Unread', 'Unread'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(appStateProvider.notifier).fetchNotifications(),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
