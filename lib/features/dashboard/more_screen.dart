import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/logout_confirm_dialog.dart';
import '../../shared/widgets/page_header.dart';
import '../profile_settings/change_password_dialog.dart';

class _MoreItem {
  final IconData icon;
  final String label;
  final String? route;
  final VoidCallback? onTap;
  final int badge;
  final bool destructive;

  const _MoreItem(this.icon, this.label, {this.route, this.onTap, this.badge = 0, this.destructive = false});
}

/// "More" tab: every screen that isn't a bottom-nav tab, grouped by role.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  Map<String, List<_MoreItem>> _sections(BuildContext context, UserModel user, int unread) {
    final account = [
      _MoreItem(Icons.notifications_outlined, 'Notifications', route: '/notifications', badge: unread),
      const _MoreItem(Icons.person_outline_rounded, 'My profile', route: '/profile'),
      _MoreItem(Icons.lock_outline_rounded, 'Change password', onTap: () => ChangePasswordDialog.show(context)),
    ];

    if (user.isIntern) {
      return {
        'Work': const [
          _MoreItem(Icons.chat_bubble_outline_rounded, 'Standup', route: '/standup'),
          _MoreItem(Icons.assignment_outlined, 'Assignments', route: '/intern-assignments'),
        ],
        'Updates': const [
          _MoreItem(Icons.campaign_outlined, 'Announcements', route: '/announcements'),
          _MoreItem(Icons.article_outlined, 'Blogs', route: '/blogs'),
        ],
        'Account': account,
      };
    }

    final admin = user.isAdmin;
    return {
      'People': [
        _MoreItem(Icons.people_outline_rounded, admin ? 'Users' : 'My interns', route: '/admin'),
        if (admin) const _MoreItem(Icons.group_outlined, 'Team directory', route: '/team'),
        _MoreItem(Icons.link_rounded, admin ? 'Invite links & sign-ups' : 'Invite links', route: '/invite-links'),
        const _MoreItem(Icons.hub_outlined, 'Cohorts', route: '/cohorts'),
      ],
      'Work': [
        const _MoreItem(Icons.assignment_outlined, 'Intern assignments', route: '/intern-assignments'),
        const _MoreItem(Icons.chat_bubble_outline_rounded, 'Standup', route: '/standup'),
        _MoreItem(Icons.stars_outlined, admin ? 'Performance reviews' : 'Reviews', route: '/reviews'),
      ],
      'Updates': const [
        _MoreItem(Icons.campaign_outlined, 'Announcements', route: '/announcements'),
        _MoreItem(Icons.article_outlined, 'Blogs', route: '/blogs'),
        _MoreItem(Icons.insights_rounded, 'Activity', route: '/activity'),
      ],
      if (admin)
        'Organization': [
          const _MoreItem(Icons.business_rounded, 'Organization settings', route: '/org-settings'),
          const _MoreItem(Icons.mark_email_read_outlined, 'Mail configuration', route: '/admin/settings/mail'),
          const _MoreItem(Icons.checklist_rounded, 'Task statuses', route: '/task-statuses'),
          const _MoreItem(Icons.layers_outlined, 'Project statuses', route: '/project-statuses'),
          const _MoreItem(Icons.access_time_rounded, 'Internship durations', route: '/internship-durations'),
          const _MoreItem(Icons.delete_outline_rounded, 'Recycle bin', route: '/bin'),
          if (user.isPlatformAdmin)
            const _MoreItem(Icons.dangerous_outlined, 'Danger zone', route: '/data', destructive: true),
        ],
      'Account': account,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final sections = _sections(context, user, state.unreadCount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 32),
      children: [
        const PageHeader(title: 'More', padding: EdgeInsets.zero),
        const SizedBox(height: 16),
        _ProfileCard(user: user),
        for (final entry in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
            child: Text(entry.key.toUpperCase(),
                style: AppTypography.label.copyWith(letterSpacing: 1.2)),
          ),
          _Group(items: entry.value),
        ],
        const SizedBox(height: 22),
        _Group(items: [
          _MoreItem(Icons.logout_rounded, 'Log out',
              onTap: () => showLogoutConfirmDialog(context, ref), destructive: true),
        ]),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final UserModel user;
  const _ProfileCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final org = user.organizationName ?? '';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.r24),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        onTap: () => Navigator.of(context).pushNamed('/profile'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppSpacing.r24), boxShadow: AppShadows.soft),
          child: Row(
            children: [
              AppAvatar(url: user.avatarUrl, size: 52, fallbackText: user.name),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.cardTitle),
                    const SizedBox(height: 2),
                    Text(
                      org.isEmpty ? user.roleTitle : '${user.roleTitle} · $org',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<_MoreItem> items;
  const _Group({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 64, color: AppColors.divider),
            _Row(item: item),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final _MoreItem item;
  const _Row({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = item.destructive ? AppColors.danger : AppColors.ink;
    return InkWell(
      onTap: item.onTap ?? () => Navigator.of(context).pushNamed(item.route!),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: item.destructive ? AppColors.dangerSoft : AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, size: 18, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(item.label, style: AppTypography.bodyStrong.copyWith(color: color))),
            if (item.badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppSpacing.rPill)),
                child: Text(item.badge > 99 ? '99+' : '${item.badge}',
                    style: AppTypography.label.copyWith(color: AppColors.onPrimary)),
              ),
            if (!item.destructive) const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
