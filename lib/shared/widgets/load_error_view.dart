import 'package:flutter/material.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

/// Human-readable message for a failed API call.
String apiErrorMessage(Object error, {String fallback = 'Something went wrong. Please try again.'}) {
  if (error is ApiException) {
    if (error.isNetworkError) return 'Could not reach the server. Check your connection and try again.';
    return error.message;
  }
  return fallback;
}

/// Card shown when a screen's data failed to load, with a retry button.
class LoadErrorView extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final bool compact;

  const LoadErrorView({
    super.key,
    this.title = 'Couldn\'t load this',
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: compact ? 32 : 48, color: AppColors.danger),
          SizedBox(height: compact ? 8 : 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: compact ? 15 : 18, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          SizedBox(height: compact ? 12 : 18),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
    if (compact) return card;
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: card));
  }
}

/// Shows a snackbar with the API error for a failed action.
void showApiError(BuildContext context, Object error, {String? prefix}) {
  final message = apiErrorMessage(error);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(prefix == null ? message : '$prefix: $message'),
      backgroundColor: AppColors.danger,
    ),
  );
}
