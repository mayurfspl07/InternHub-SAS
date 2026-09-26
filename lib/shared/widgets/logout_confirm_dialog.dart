import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/app_state_provider.dart';

/// Asks for confirmation, logs out and returns to the login screen.
Future<void> showLogoutConfirmDialog(BuildContext context, WidgetRef ref) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Log out?', style: AppTypography.section),
      content: Text(
        'You will be logged out from your account and returned to the login screen.',
        style: AppTypography.body,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 44),
          ),
          onPressed: () async {
            Navigator.pop(ctx);
            await ref.read(appStateProvider.notifier).logout();
            if (context.mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
            }
          },
          child: const Text('Log out'),
        ),
      ],
    ),
  );
}
