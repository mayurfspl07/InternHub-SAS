import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../widgets/app_avatar.dart';
import '../widgets/global_search_modal.dart';
import '../widgets/user_360_profile_dialog.dart';
import '../../features/profile_settings/change_password_dialog.dart';
import '../../features/profile_settings/profile_screen.dart';
import '../../features/auth/login_screen.dart';

class CustomAppBar extends ConsumerWidget {
  final VoidCallback? onNotificationTap;
  final VoidCallback? onMenuTap;

  const CustomAppBar({
    super.key,
    this.onNotificationTap,
    this.onMenuTap,
  });

  void _showAccountMenu(BuildContext context, WidgetRef ref, UserModel user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppAvatar(url: user.avatarUrl, size: 48, fallbackText: user.name),
              title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text('${user.roleTitle} • ${user.email}'),
              onTap: () {
                Navigator.pop(ctx);
                User360ProfileDialog.show(context, userId: user.id, fallbackUser: user);
              },
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('My Profile'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded),
              title: const Text('Change Password'),
              onTap: () {
                Navigator.pop(ctx);
                ChangePasswordDialog.show(context);
              },
            ),
            ListTile(
              leading: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
              title: Text(isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme'),
              onTap: () {
                ref.read(appStateProvider.notifier).toggleThemeMode();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
              title: const Text('Log Out', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmLogout(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out of InternHub?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(appStateProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unreadCount = state.notifications.where((n) => !n.isRead).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: AppSpacing.p8),
      child: Row(
        children: [
          // Menu button (Opens Navigation Drawer / More Menu)
          if (onMenuTap != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.menu_rounded),
                onPressed: onMenuTap,
              ),
            ),

          // User Avatar & Greeting
          Expanded(
            child: GestureDetector(
              onTap: () => _showAccountMenu(context, ref, user),
              child: Row(
                children: [
                  AppAvatar(
                    url: user.avatarUrl,
                    size: 42,
                    borderColor: AppColors.primary,
                    borderWidth: 2,
                    fallbackText: user.name,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.name.split(' ').first,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('👋', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.roleTitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Global Search Button
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 22),
            onPressed: () => GlobalSearchModal.show(context),
          ),

          // Notification Bell with Badge
          GestureDetector(
            onTap: onNotificationTap,
            child: Stack(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    size: 20,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Center(
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
