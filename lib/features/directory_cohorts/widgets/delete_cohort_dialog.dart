import 'package:flutter/material.dart';
import '../../../shared/models/cohort_model.dart';
import '../cohorts_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

class DeleteCohortDialog extends StatefulWidget {
  final Cohort cohort;
  final VoidCallback onSuccess;

  const DeleteCohortDialog({
    super.key,
    required this.cohort,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required Cohort cohort,
    required VoidCallback onSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteCohortDialog(
        cohort: cohort,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<DeleteCohortDialog> createState() => _DeleteCohortDialogState();
}

class _DeleteCohortDialogState extends State<DeleteCohortDialog> {
  bool _isDeleting = false;

  Future<void> _delete() async {
    setState(() => _isDeleting = true);
    try {
      await CohortsRepository().deleteCohort(widget.cohort.id);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${widget.cohort.name}" moved to the recycle bin')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        showApiError(context, e, prefix: "Couldn't delete the cohort");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogBg = AppColors.surface;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return Dialog(
      backgroundColor: dialogBg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.dangerInk,
                  size: 28,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Delete "${widget.cohort.name}"?',
                style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
              ),
              const SizedBox(height: 10),
              Text(
                "Its interns leave the cohort; their accounts aren't affected. You can restore it from the recycle bin.",
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: secondaryTextColor, height: 1.4),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: AppColors.border,
                        ),
                      ),
                      child: Text('Cancel', style: TextStyle(color: primaryTextColor)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isDeleting ? null : _delete,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: AppColors.surface,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isDeleting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                            )
                          : const Text(
                              'Delete',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
