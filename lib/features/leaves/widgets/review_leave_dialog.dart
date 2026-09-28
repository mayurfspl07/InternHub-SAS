import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/leave_model.dart';
import '../leave_repository.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../core/utils/formatters.dart';

class ReviewLeaveDialog extends StatefulWidget {
  final LeaveRequest request;
  final bool isApprove; // true: Approve, false: Reject
  final VoidCallback onSuccess;

  const ReviewLeaveDialog({
    super.key,
    required this.request,
    required this.isApprove,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required LeaveRequest request,
    required bool isApprove,
    required VoidCallback onSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReviewLeaveDialog(
        request: request,
        isApprove: isApprove,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<ReviewLeaveDialog> createState() => _ReviewLeaveDialogState();
}

class _ReviewLeaveDialogState extends State<ReviewLeaveDialog> {
  late TextEditingController _commentController;
  bool _isSubmitting = false;
  String? _serverError;
  String? _commentError;

  @override
  void initState() {
    super.initState();
    // Starts empty: an unedited canned comment would be sent to the intern as the reviewer's words.
    _commentController = TextEditingController();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handleReview() async {
    // A rejection needs a reason the intern can act on.
    if (!widget.isApprove && _commentController.text.trim().isEmpty) {
      setState(() => _commentError = 'Tell the intern why this is rejected');
      return;
    }
    setState(() {
      _commentError = null;
      _isSubmitting = true;
      _serverError = null;
    });

    try {
      final decision = widget.isApprove ? 'approved' : 'rejected';
      final comment = _commentController.text.trim();

      await LeaveRepository().review(
        id: widget.request.id,
        decision: decision,
        comment: comment.isEmpty ? null : comment,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isApprove ? 'Leave approved.' : 'Leave rejected.',
            ),
            backgroundColor: widget.isApprove ? AppColors.success : AppColors.ink,
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _serverError = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final isApprove = widget.isApprove;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isApprove ? AppColors.primary : AppColors.danger.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      isApprove ? Icons.check_rounded : Icons.close_rounded,
                      color: isApprove ? AppColors.ink : AppColors.danger,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isApprove ? 'Approve leave' : 'Reject leave',
                          style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Review leave request for ${req.userName}.',
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    tooltip: 'Close',
                    color: AppColors.textSecondary,
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Request Summary Container
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryRow(
                      label: 'Dates',
                      value: '${formatDateRange(req.start_date, req.end_date)} · ${plural(req.days, 'day')}',
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      label: 'Type',
                      value: req.typeLabel,
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 8),
                    Text(
                      'Reason',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '"${req.reason}"',
                      style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Reviewer Comment Field
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isApprove ? 'Comment for the intern (optional)' : 'Reason for rejecting',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _commentController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                style: AppTypography.caption.copyWith(color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: isApprove ? 'e.g. Approved, enjoy your time off' : 'e.g. We have a client demo that week',
                  errorText: _commentError,
                  hintStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isApprove ? AppColors.primary : AppColors.danger,
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              if (_serverError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _serverError!,
                  style: AppTypography.caption.copyWith(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: 22),

              // Action Buttons
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: AppTypography.bodyStrong),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isApprove ? AppColors.primary : AppColors.danger,
                      foregroundColor: isApprove ? AppColors.ink : AppColors.surface,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _isSubmitting ? null : _handleReview,
                    child: _isSubmitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isApprove ? AppColors.ink : AppColors.surface,
                            ),
                          )
                        : Text(
                            isApprove ? 'Approve' : 'Reject',
                            style: AppTypography.bodyStrong.copyWith(color: isApprove ? AppColors.ink : AppColors.surface),
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

  Widget _buildSummaryRow({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label),
        const SizedBox(height: 2),
        Text(value, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
      ],
    );
  }
}
