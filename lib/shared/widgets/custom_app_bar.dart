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

/// Two modes:
/// - dashboard (no [title]): menu, "Hi, {name}" greeting, search, bell, avatar
/// - sub-page ([title] set): back/menu circle, centered title, trailing or bell
class CustomAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback? onNotificationTap;
  final VoidCallback? onMenuTap;
  final String? title;
  final String? subtitle;
  final bool showBackButton;
  final VoidCallback? onBackTap;
  final Widget? trailing;

  const CustomAppBar({
    super.key,
    this.onNotificationTap,
    this.onMenuTap,
    this.title,
    this.subtitle,
    this.showBackButton = false,
    this.onBackTap,
    this.trailing,
  });

  @override
  Size get preferredSize => Size.fromHeight(title != null ? 68 : 76);

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
                        Text(user.name, style: AppTypography.section),
                        const SizedBox(height: 3),
                        Text(user.email, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                    child: Text(user.roleTitle, style: AppTypography.label.copyWith(color: AppColors.primaryInk)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _accountTile(
                icon: Icons.person_outline_rounded,
                title: 'View profile',
                subtitle: 'Account settings & activity',
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
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Log out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.dangerSoft, width: 1.5),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    showLogoutConfirmDialog(context, ref);
                  },
                ),
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
    required VoidCallback onTap,
  }) {
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
            decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: AppColors.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyStrong),
                if (subtitle != null) Text(subtitle, style: AppTypography.caption),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final unreadCount = state.unreadCount; // from the API, not just the loaded page

    if (title != null) {
      final leading = (showBackButton || onBackTap != null)
          ? CircularIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              iconSize: 18,
              onTap: onBackTap ?? () => Navigator.maybePop(context),
            )
          : onMenuTap != null
              ? CircularIconButton(icon: Icons.menu_rounded, onTap: onMenuTap)
              : const SizedBox(width: 42);

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: AppSpacing.p12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.cardTitle.copyWith(fontSize: 17),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing ?? _buildNotificationBadge(context, unreadCount),
          ],
        ),
      );
    }

    final firstName = user.name.trim().isEmpty ? 'there' : user.name.trim().split(' ').first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.p20, AppSpacing.p12, AppSpacing.p20, AppSpacing.p8),
      child: Row(
        children: [
          if (onMenuTap != null) ...[
            CircularIconButton(icon: Icons.menu_rounded, size: 40, onTap: onMenuTap),
            const SizedBox(width: 12),
          ],
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
            size: 40,
            onTap: () => GlobalSearchModal.show(context),
          ),
          const SizedBox(width: 8),
          _buildNotificationBadge(context, unreadCount),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showAccountMenu(context, ref, user),
            child: AppAvatar(url: user.avatarUrl, size: 42, fallbackText: user.name),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBadge(BuildContext context, int unreadCount) {
    return Container(
      width: 40,
      height: 40,
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
              textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              child: const Icon(Icons.notifications_none_rounded, size: 20, color: AppColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}
