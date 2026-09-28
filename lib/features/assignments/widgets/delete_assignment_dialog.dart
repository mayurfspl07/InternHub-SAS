import 'package:flutter/material.dart';
import '../../../shared/models/assignment_model.dart';
import '../assignments_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

class DeleteAssignmentDialog extends StatefulWidget {
  final AssignmentItem assignment;
  final VoidCallback onSuccess;

  const DeleteAssignmentDialog({
    super.key,
    required this.assignment,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required AssignmentItem assignment,
    required VoidCallback onSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteAssignmentDialog(
        assignment: assignment,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<DeleteAssignmentDialog> createState() => _DeleteAssignmentDialogState();
}

class _DeleteAssignmentDialogState extends State<DeleteAssignmentDialog> {
  bool _isDeleting = false;

  Future<void> _delete() async {
    setState(() => _isDeleting = true);
    try {
      await AssignmentsRepository().deleteAssignment(widget.assignment.id);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${widget.assignment.title}" deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        showApiError(context, e, prefix: "Couldn't delete the assignment");
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
                'Delete "${widget.assignment.title}"?',
                style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
              ),
              const SizedBox(height: 10),
              Text(
                'Interns will no longer see it, and its submissions and grades go with it.',
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: AppColors.border),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _isDeleting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                          : const Text('Delete', style: TextStyle(fontWeight: FontWeight.w700)),
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
