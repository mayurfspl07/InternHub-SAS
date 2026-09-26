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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
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
            color: isSelected ? AppColors.primary : Colors.transparent,
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
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? AppColors.ink
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
