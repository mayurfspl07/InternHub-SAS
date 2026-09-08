import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifications = state.notifications;

    final filtered = notifications.where((n) {
      if (_selectedFilter == 'Unread') return !n.isRead;
      if (_selectedFilter == 'Tasks') return n.category.toLowerCase().contains('task');
      if (_selectedFilter == 'Leaves') return n.category.toLowerCase().contains('leave');
      if (_selectedFilter == 'Standup') return n.category.toLowerCase().contains('standup');
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications 🔔', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark All Read',
            onPressed: () async {
              await ref.read(appStateProvider.notifier).markAllNotificationsRead();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All notifications marked as read')),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.read(appStateProvider.notifier).fetchNotifications(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
              child: Row(
                children: ['All', 'Unread', 'Tasks', 'Leaves', 'Standup'].map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedFilter = filter),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.actionCircleDark : (isDark ? AppColors.surfaceDark : Colors.white),
                        borderRadius: BorderRadius.circular(AppSpacing.rPill),
                        border: Border.all(
                          color: isSelected ? AppColors.actionCircleDark : (isDark ? AppColors.borderDark : AppColors.borderLight),
                        ),
                      ),
                      child: Text(
                        filter,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppColors.textSecondaryLight),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),

            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(appStateProvider.notifier).fetchNotifications(),
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_none_rounded, size: 64, color: isDark ? Colors.white38 : AppColors.textSecondaryLight),
                                const SizedBox(height: 16),
                                Text(
                                  'All caught up!',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No notifications to show under this filter.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpacing.p20),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final notif = filtered[index];
                          final timeStr = DateFormat('MMM d, hh:mm a').format(notif.time);

                          return Dismissible(
                            key: Key(notif.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(22),
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
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: notif.isRead
                                      ? (isDark ? AppColors.surfaceDark : Colors.white)
                                      : (isDark ? const Color(0xFF222634) : const Color(0xFFEDE9FE)),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: notif.isRead ? Colors.grey.withValues(alpha: 0.15) : AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        notif.isRead ? Icons.notifications_none_rounded : Icons.notifications_active_rounded,
                                        color: notif.isRead ? Colors.grey : AppColors.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  notif.title,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w800,
                                                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                timeStr,
                                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            notif.body,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                                            ),
                                          ),
                                        ],
                                      ),
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
