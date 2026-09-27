import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/logout_confirm_dialog.dart';
import '../../shared/widgets/reference_components.dart';
import '../profile_settings/change_password_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appStateProvider).currentUser;
    final isAdmin = user.isAdmin;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 12, AppSpacing.p20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Settings',
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),

              if (isAdmin) ...[
                _buildSettingsNavCard(
                  icon: Icons.business_rounded,
                  tint: AppColors.lavender,
                  iconColor: AppColors.lavenderInk,
                  title: 'Organization',
                  subtitle: 'Name, logo, working hours, leave and attendance rules',
                  onTap: () => Navigator.pushNamed(context, '/org-settings'),
                ),
                const SizedBox(height: 12),
                _buildSettingsNavCard(
                  icon: Icons.mark_email_read_outlined,
                  tint: AppColors.butter,
                  iconColor: AppColors.butterInk,
                  title: 'Mail Configuration',
                  subtitle: 'Configure SMTP & mail settings',
                  onTap: () => Navigator.pushNamed(context, '/admin/settings/mail'),
                ),
                const SizedBox(height: 12),
              ],

              _buildSettingsNavCard(
                icon: Icons.notifications_outlined,
                tint: AppColors.peach,
                iconColor: AppColors.peachInk,
                title: 'Notifications',
                subtitle: 'See and clear your notifications',
                onTap: () => Navigator.pushNamed(context, '/notifications'),
              ),
              const SizedBox(height: 12),

              _buildSettingsNavCard(
                icon: Icons.lock_outline_rounded,
                tint: AppColors.sage,
                iconColor: AppColors.sageInk,
                title: 'Change password',
                subtitle: 'Signs you out on your other devices',
                onTap: () => ChangePasswordDialog.show(context),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () => showLogoutConfirmDialog(context, ref),
                  icon: const Icon(Icons.logout_rounded, size: 20),
                  label: const Text('Log out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsNavCard({
    required IconData icon,
    required Color tint,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ReferenceCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.cardTitle),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.caption),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}
