import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/cohort_model.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../core/constants/app_typography.dart';
import '../../core/utils/formatters.dart';

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
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(AppSpacing.rPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 40),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: isSelected
                ? AppColors.onPrimary
                : AppColors.textSecondary),
        ),
      ),
      ),
    );
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
        return (Icons.task_alt_rounded, AppColors.infoInk, AppColors.infoSoft);
      case 'assignment':
        return (Icons.assignment_outlined, AppColors.infoInk, AppColors.infoSoft);
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
      messenger.showSnackBar(const SnackBar(content: Text('All marked as read')));
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't mark notifications as read");
    }
  }

  /// Swipe-to-delete: the item leaves the list at once (Dismissible requires it), and the
  /// server delete runs only if the Undo snackbar closes without Undo being tapped.
  void _delete(NotificationItem notif) {
    final notifier = ref.read(appStateProvider.notifier);
    final index = ref.read(appStateProvider).notifications.indexWhere((n) => n.id == notif.id);
    notifier.hideNotification(notif.id);

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('Notification deleted'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Undo', onPressed: () => notifier.restoreNotification(notif, index)),
      ),
    );
    controller.closed.then((reason) async {
      if (reason == SnackBarClosedReason.action) return;
      try {
        await notifier.deleteNotification(notif.id);
      } catch (e) {
        notifier.restoreNotification(notif, index);
        messenger.showSnackBar(SnackBar(content: Text("Couldn't delete the notification. ${apiErrorMessage(e)}")));
      }
    });
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
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_none_rounded, size: 48, color: AppColors.textSecondary),
                SizedBox(height: 16),
                Text(
                  _selectedFilter == 'Unread' ? 'All caught up' : 'No notifications yet',
                  style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                SizedBox(height: 6),
                Text(
                  _selectedFilter == 'Unread' ? "You've read everything." : 'Updates about your work will appear here.',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                ),
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
              child: const Icon(Icons.delete_outline, color: AppColors.surface),
            ),
            onDismissed: (_) => _delete(notif),
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.soft),
              child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: route == null ? null : () => Navigator.of(context).pushNamed(route),
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                        style: AppTypography.caption.copyWith(height: 1.35, color: AppColors.ink),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRelative(notif.createdAt),
                          style: AppTypography.label.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                        if (!notif.isRead) ...[
                          const SizedBox(height: 6),
                          Semantics(
                            label: 'Unread',
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Chevron only on notifications that open a screen.
                    if (route != null) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
                    ],
                  ],
                ),
              ),
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
