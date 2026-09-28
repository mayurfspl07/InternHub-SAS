import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../widgets/app_avatar.dart';
import '../widgets/global_search_modal.dart';
import '../widgets/logout_confirm_dialog.dart';
import '../widgets/reference_components.dart';
import '../../features/profile_settings/change_password_dialog.dart';

/// Home header: "Hi, {name}" greeting and date, then search, notifications and the account menu.
/// Other tabs use their own PageHeader; pushed pages use pageAppBar.
class CustomAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback? onNotificationTap;

  const CustomAppBar({super.key, this.onNotificationTap});

  @override
  Size get preferredSize => const Size.fromHeight(76);

  void _showAccountMenu(BuildContext context, WidgetRef ref, UserModel user) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppAvatar(url: user.avatarUrl, size: 54, fallbackText: user.name),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.section),
                        const SizedBox(height: 3),
                        Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                    child: Text(user.role.label, style: AppTypography.label.copyWith(color: AppColors.primaryInk)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _accountTile(
                icon: Icons.person_outline_rounded,
                title: 'My profile',
                subtitle: 'Your details, skills and photo',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(context, '/profile');
                },
              ),
              const SizedBox(height: 10),
              _accountTile(
                icon: Icons.lock_outline_rounded,
                title: 'Change password',
                onTap: () {
                  Navigator.pop(ctx);
                  ChangePasswordDialog.show(context);
                },
              ),
              const SizedBox(height: 10),
              _accountTile(
                icon: Icons.logout_rounded,
                title: 'Log out',
                destructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  showLogoutConfirmDialog(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountTile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool destructive = false,
    required VoidCallback onTap,
  }) {
    final color = destructive ? AppColors.danger : AppColors.ink;
    return ReferenceCard(
      backgroundColor: AppColors.surfaceMuted,
      borderRadius: AppSpacing.rTile,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: destructive ? AppColors.dangerSoft : AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyStrong.copyWith(color: color)),
                if (subtitle != null) Text(subtitle, style: AppTypography.caption),
              ],
            ),
          ),
          if (!destructive) const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final unreadCount = state.unreadCount; // from the API, not just the loaded page
    final firstName = user.name.trim().isEmpty ? 'there' : user.name.trim().split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.p20, AppSpacing.p12, AppSpacing.p20, AppSpacing.p8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Hi, $firstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headline.copyWith(fontSize: 24),
                ),
                Text(DateFormat('EEEE, d MMMM').format(DateTime.now()), style: AppTypography.caption),
              ],
            ),
          ),
          CircularIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Search',
            onTap: () => GlobalSearchModal.show(context),
          ),
          const SizedBox(width: 8),
          _buildNotificationBadge(context, unreadCount),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Account menu',
            excludeSemantics: true,
            child: Tooltip(
              message: 'Account',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _showAccountMenu(context, ref, user),
                child: AppAvatar(url: user.avatarUrl, size: 44, fallbackText: user.name),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBadge(BuildContext context, int unreadCount) {
    final label = unreadCount > 0 ? 'Notifications, $unreadCount unread' : 'Notifications';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Notifications',
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onNotificationTap ?? () => Navigator.pushNamed(context, '/notifications'),
              child: Center(
                child: Badge.count(
                  count: unreadCount,
                  isLabelVisible: unreadCount > 0,
                  backgroundColor: AppColors.danger,
                  textColor: AppColors.surface,
                  textStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w700),
                  child: const Icon(Icons.notifications_none_rounded, size: 20, color: AppColors.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
