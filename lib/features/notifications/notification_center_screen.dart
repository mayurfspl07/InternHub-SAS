import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final notifications = state.notifications;

    final filtered = notifications.where((n) {
      if (_selectedFilter == 'Unread') return !n.isRead;
      if (_selectedFilter == 'Mentions') return n.category.toLowerCase().contains('mention') || n.title.toLowerCase().contains('intern') || n.body.toLowerCase().contains('@');
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top Header: Back Button & Title & Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PageHeader(
                    title: 'Notifications',
                    padding: EdgeInsets.zero,
                    actions: [
                      HeaderAction(icon: Icons.done_all_rounded, tooltip: 'Mark All Read', onTap: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await ref.read(appStateProvider.notifier).markAllNotificationsRead();
                          messenger.showSnackBar(
                            const SnackBar(content: Text('All notifications marked as read')),
                          );
                        }),
                      HeaderAction(icon: Icons.refresh_rounded, tooltip: 'Refresh', onTap: () => ref.read(appStateProvider.notifier).fetchNotifications()),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Segmented Tabs [All] [Mentions] [Unread]
                  Row(
                    children: [
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
                            _buildSegmentedTab('Mentions', 'Mentions'),
                            _buildSegmentedTab('Unread', 'Unread'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Notifications List
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(appStateProvider.notifier).fetchNotifications(),
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.notifications_none_rounded, size: 48, color: secondaryTextColor),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'All caught up!',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTextColor,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No notifications to show under this filter.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final notif = filtered[index];
                          final timeStr = _formatRelative(notif.time);

                          final cat = notif.category.toLowerCase();
                          Color iconBg;
                          Color iconColor;
                          IconData iconData;

                          if (cat.contains('intern') || notif.title.toLowerCase().contains('intern')) {
                            iconBg = AppColors.info.withValues(alpha: 0.15);
                            iconColor = AppColors.info;
                            iconData = Icons.person_add_rounded;
                          } else if (cat.contains('task') || notif.title.toLowerCase().contains('task')) {
                            iconBg = AppColors.info.withValues(alpha: 0.15);
                            iconColor = AppColors.info;
                            iconData = Icons.task_alt_rounded;
                          } else if (cat.contains('review') || notif.title.toLowerCase().contains('review')) {
                            iconBg = AppColors.primary.withValues(alpha: 0.2);
                            iconColor = AppColors.warning;
                            iconData = Icons.star_rounded;
                          } else if (cat.contains('leave') || notif.title.toLowerCase().contains('leave')) {
                            iconBg = AppColors.peachInk.withValues(alpha: 0.15);
                            iconColor = AppColors.peachInk;
                            iconData = Icons.event_note_rounded;
                          } else {
                            iconBg = AppColors.success.withValues(alpha: 0.15);
                            iconColor = AppColors.success;
                            iconData = Icons.notifications_rounded;
                          }

                          return Dismissible(
                            key: Key(notif.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            onDismissed: (_) {
                              ref.read(appStateProvider.notifier).deleteNotification(notif.id);
                            },
                            child: GestureDetector(
                              onTap: () {
                                if (!notif.isRead) {
                                  ref.read(appStateProvider.notifier).markNotificationRead(notif.id);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Circular Icon Avatar
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: iconBg,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(iconData, color: iconColor, size: 20),
                                    ),
                                    const SizedBox(width: 14),

                                    // Content: Title & Body
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            notif.title,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: primaryTextColor,
                                            ),
                                          ),
                                          if (notif.body.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              notif.body,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: secondaryTextColor,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    // Right: Timestamp & Unread Dot
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: secondaryTextColor,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (!notif.isRead) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
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
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
