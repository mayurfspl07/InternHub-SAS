import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/leave_model.dart';
import '../leave_repository.dart';

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

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(
      text: widget.isApprove ? 'Approved. Enjoy your time off.' : '',
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handleReview() async {
    setState(() {
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
              widget.isApprove
                  ? '✅ Leave request approved successfully!'
                  : '❌ Leave request rejected.',
            ),
            backgroundColor: widget.isApprove ? AppColors.success : AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _serverError = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final req = widget.request;
    final isApprove = widget.isApprove;

    return Dialog(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
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
                      color: isApprove ? AppColors.cardYellow : AppColors.danger.withValues(alpha: 0.15),
                    ),
                    child: Icon(
                      isApprove ? Icons.check_rounded : Icons.close_rounded,
                      color: isApprove ? Colors.black : AppColors.danger,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isApprove ? 'Approve Leave Request' : 'Reject Leave Request',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Review leave request for ${req.userName}.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Request Summary Container
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSummaryRow(
                      label: 'Duration:',
                      value: '${req.start_date} → ${req.end_date} (${req.days} day(s))',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      label: 'Type:',
                      value: req.typeLabel,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: isDark ? AppColors.borderDark : AppColors.borderLight),
                    const SizedBox(height: 8),
                    Text(
                      'Reason:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '"${req.reason}"',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white : AppColors.textPrimaryLight,
                      ),
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
                    color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Reviewer Comment (Optional)',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _commentController,
                maxLines: 3,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
                decoration: InputDecoration(
                  hintText: isApprove
                      ? 'Add any comments for the intern...'
                      : 'Provide a reason for rejection...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white30 : AppColors.textTertiaryLight,
                  ),
                  filled: true,
                  fillColor: isDark ? AppColors.cardDark : Colors.white,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isApprove ? AppColors.cardYellow : AppColors.danger,
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              if (_serverError != null) ...[
                const SizedBox(height: 10),
                Text(
                  _serverError!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 22),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isApprove ? AppColors.cardYellow : AppColors.danger,
                      foregroundColor: isApprove ? Colors.black : Colors.white,
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
                              color: isApprove ? Colors.black : Colors.white,
                            ),
                          )
                        : Text(
                            isApprove ? 'Confirm Approval' : 'Confirm Rejection',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
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

  Widget _buildSummaryRow({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppColors.textPrimaryLight,
          ),
        ),
      ],
    );
  }
}
