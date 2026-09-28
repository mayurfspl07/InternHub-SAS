import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/performance_review_model.dart';
import '../performance_repository.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

class DeleteReviewDialog extends StatefulWidget {
  final PerformanceReview review;

  const DeleteReviewDialog({super.key, required this.review});

  static Future<bool?> show(BuildContext context, PerformanceReview review) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => DeleteReviewDialog(review: review),
    );
  }

  @override
  State<DeleteReviewDialog> createState() => _DeleteReviewDialogState();
}

class _DeleteReviewDialogState extends State<DeleteReviewDialog> {
  bool _isDeleting = false;

  Future<void> _handleDelete() async {
    setState(() => _isDeleting = true);
    try {
      await PerformanceRepository().deleteReview(widget.review.id);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(e)),
            backgroundColor: AppColors.dangerInk,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.dangerInk, size: 24),
          ),
          const SizedBox(width: 12),
          Text(
            'Delete Review',
            style: AppTypography.section.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: Text(
        'Are you sure you want to delete the performance review for "${widget.review.internDisplayName}"? This action cannot be undone.',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.ink),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: _isDeleting ? null : _handleDelete,
          child: _isDeleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
}
