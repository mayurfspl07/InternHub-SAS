import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';

class AccessRestrictedView extends StatelessWidget {
  final String title;
  final String message;

  const AccessRestrictedView({
    super.key,
    this.title = 'Admins only',
    this.message = 'Only admins can change these settings. Ask an admin in your organization if something needs updating.',
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
                child: const Icon(Icons.lock_person_outlined, color: AppColors.ink, size: 28),
              ),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: AppTypography.title.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: AppTypography.caption.copyWith(height: 1.4)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                // Works even when this page was opened directly and there's nothing to go back to.
                onPressed: () {
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                  } else {
                    navigator.pushNamedAndRemoveUntil('/dashboard', (_) => false);
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Go back'),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
