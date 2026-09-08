import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../models/user_model.dart';

class RoleSwitchBanner extends ConsumerWidget {
  const RoleSwitchBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRole = ref.watch(appStateProvider).currentUser.role;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2330) : const Color(0xFFEBEFF8),
        borderRadius: BorderRadius.circular(AppSpacing.rPill),
      ),
      child: Row(
        children: [
          _buildRoleChip(
            context: context,
            ref: ref,
            role: UserRole.intern,
            label: '🎓 Intern',
            isSelected: currentRole == UserRole.intern,
          ),
          _buildRoleChip(
            context: context,
            ref: ref,
            role: UserRole.mentor,
            label: '🧑‍🏫 Mentor',
            isSelected: currentRole == UserRole.mentor,
          ),
          _buildRoleChip(
            context: context,
            ref: ref,
            role: UserRole.admin,
            label: '🛡️ Admin',
            isSelected: currentRole == UserRole.admin,
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChip({
    required BuildContext context,
    required WidgetRef ref,
    required UserRole role,
    required String label,
    required bool isSelected,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          ref.read(appStateProvider.notifier).switchRole(role);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Switched view to $label mode'),
              duration: const Duration(milliseconds: 1200),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppColors.primary : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.rPill),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.white : AppColors.textPrimaryLight)
                    : (isDark ? Colors.white60 : AppColors.textSecondaryLight),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
