import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/models/assignment_model.dart';
import '../assignments_repository.dart';
import '../../../core/constants/app_colors.dart';

class SubmissionsReviewDialog extends StatefulWidget {
  final AssignmentItem assignment;
  final VoidCallback onDataChanged;

  const SubmissionsReviewDialog({
    super.key,
    required this.assignment,
    required this.onDataChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required AssignmentItem assignment,
    required VoidCallback onDataChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SubmissionsReviewDialog(
        assignment: assignment,
        onDataChanged: onDataChanged,
      ),
    );
  }

  @override
  State<SubmissionsReviewDialog> createState() => _SubmissionsReviewDialogState();
}

class _SubmissionsReviewDialogState extends State<SubmissionsReviewDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  List<AssignmentSubmission> _submissions = [];

  // Track which submission is currently being graded
  int? _gradingSubmissionId;
  String _gradeStatus = 'approved';
  final TextEditingController _scoreController = TextEditingController();
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSavingReview = false;

  @override
  void initState() {
    super.initState();
    _fetchSubmissions();
  }

  @override
  void dispose() {
    _scoreController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _fetchSubmissions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await AssignmentsRepository().getSubmissions(
        widget.assignment.id,
        fallbackTitle: widget.assignment.title,
      );
      if (mounted) {
        setState(() {
          _submissions = res.submissions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _openGradingForm(AssignmentSubmission sub) {
    setState(() {
      _gradingSubmissionId = sub.id;
      _gradeStatus = (sub.status.toLowerCase() == 'submitted' || sub.status.toLowerCase() == 'resubmitted')
          ? 'approved'
          : sub.status.toLowerCase();
      final defaultScore = sub.score ?? widget.assignment.maxScore ?? 100.0;
      _scoreController.text = defaultScore % 1 == 0 ? defaultScore.toInt().toString() : defaultScore.toString();
      _feedbackController.text = sub.feedback ?? '';
    });
  }

  void _cancelGrading() {
    setState(() {
      _gradingSubmissionId = null;
      _scoreController.clear();
      _feedbackController.clear();
    });
  }

  Future<void> _submitReview(int submissionId) async {
    final scoreVal = double.tryParse(_scoreController.text.trim());
    final maxScore = widget.assignment.maxScore ?? 100.0;

    if (scoreVal != null && (scoreVal < 0 || scoreVal > maxScore)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Score must be between 0 and $maxScore')),
      );
      return;
    }

    setState(() => _isSavingReview = true);

    try {
      await AssignmentsRepository().reviewSubmission(
        submissionId,
        status: _gradeStatus,
        score: scoreVal,
        feedback: _feedbackController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Review submitted successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        _cancelGrading();
        await _fetchSubmissions();
        widget.onDataChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit review: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingReview = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $url')),
        );
      }
    }
  }

  Widget _buildStatusChip(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase().trim()) {
      case 'approved':
        bg = AppColors.successSoft;
        fg = AppColors.successInk;
        label = 'Approved';
        break;
      case 'rejected':
        bg = AppColors.dangerSoft;
        fg = AppColors.dangerInk;
        label = 'Rejected';
        break;
      case 'under_review':
        bg = AppColors.lavender;
        fg = AppColors.lavenderInk;
        label = 'Under Review';
        break;
      case 'resubmitted':
      case 'needs_revision':
        bg = AppColors.warningSoft;
        fg = AppColors.warningInk;
        label = 'Needs Revision';
        break;
      case 'submitted':
      default:
        bg = AppColors.infoSoft;
        fg = AppColors.infoInk;
        label = 'Submitted';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Colors.white;
    final cardBg = AppColors.surfaceMuted;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 2),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Header bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.butter,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary, width: 1.2),
                      ),
                      child: const Icon(Icons.assignment_turned_in_rounded, color: AppColors.butterInk, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Submissions (${_submissions.length})',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.assignment.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      color: secondaryTextColor,
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Submissions list or states
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 40),
                                const SizedBox(height: 8),
                                Text('Failed to load submissions', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(_errorMessage!, style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                                const SizedBox(height: 12),
                                ElevatedButton(onPressed: _fetchSubmissions, child: const Text('Retry')),
                              ],
                            ),
                          )
                        : _submissions.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.inbox_outlined, size: 52, color: AppColors.textTertiary),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No submissions yet',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Enrolled interns have not submitted solutions for this assignment yet.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 13, color: secondaryTextColor),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                itemCount: _submissions.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 14),
                                itemBuilder: (context, index) {
                                  final sub = _submissions[index];
                                  final isGradingThis = _gradingSubmissionId == sub.id;

                                  return Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isGradingThis ? AppColors.primary : borderColor,
                                        width: isGradingThis ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Intern Header
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: AppColors.warningSoft,
                                              child: Text(
                                                sub.displayName.isNotEmpty ? sub.displayName[0].toUpperCase() : 'I',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.warningInk),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    sub.displayName,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      color: primaryTextColor,
                                                    ),
                                                  ),
                                                  if (sub.userEmail?.isNotEmpty == true) ...[
                                                    const SizedBox(height: 1),
                                                    Text(
                                                      sub.userEmail!,
                                                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            _buildStatusChip(sub.status),
                                          ],
                                        ),
                                        const SizedBox(height: 10),

                                        // Submitted at & Score
                                        Row(
                                          children: [
                                            Icon(Icons.access_time_rounded, size: 13, color: secondaryTextColor),
                                            const SizedBox(width: 5),
                                            Text(
                                              sub.formattedSubmittedAt,
                                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                            ),
                                            if (sub.score != null) ...[
                                              const SizedBox(width: 12),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.successSoft,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Grade: ${sub.score! % 1 == 0 ? sub.score!.toInt() : sub.score} / ${widget.assignment.maxScore?.toInt() ?? 100}',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.successInk,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),

                                        // Submission Text
                                        if (sub.submissionText?.trim().isNotEmpty == true) ...[
                                          const SizedBox(height: 12),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: borderColor),
                                            ),
                                            child: Text(
                                              sub.submissionText!.trim(),
                                              style: TextStyle(fontSize: 13, color: primaryTextColor, height: 1.4),
                                            ),
                                          ),
                                        ],

                                        // GitHub / File Links
                                        if (sub.githubUrl?.trim().isNotEmpty == true || sub.hasFile) ...[
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: [
                                              if (sub.githubUrl?.trim().isNotEmpty == true)
                                                InkWell(
                                                  onTap: () => _launchUrl(sub.githubUrl!.trim()),
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.surfaceMuted,
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.code_rounded, size: 14, color: AppColors.info),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          'View Repository',
                                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              if (sub.hasFile && sub.fileUrl != null)
                                                InkWell(
                                                  onTap: () => _launchUrl(sub.fileUrl!),
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.surfaceMuted,
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(Icons.attach_file_rounded, size: 14, color: AppColors.success),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          sub.fileName ?? 'Download Solution',
                                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primaryTextColor),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],

                                        // Mentor Feedback (if already provided and not currently grading)
                                        if (!isGradingThis && sub.feedback?.trim().isNotEmpty == true) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: AppColors.warningSoft.withValues(alpha: 0.4),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Icon(Icons.feedback_outlined, size: 15, color: AppColors.warningInk),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    sub.feedback!.trim(),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: AppColors.warningInk,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],

                                        // Inline Grade Form (when toggled)
                                        if (isGradingThis) ...[
                                          const SizedBox(height: 14),
                                          Divider(height: 1, color: borderColor),
                                          const SizedBox(height: 12),
                                          Text(
                                            'GRADE & REVIEW',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              // Decision Dropdown
                                              Expanded(
                                                flex: 5,
                                                child: DropdownButtonFormField<String>(
                                                  key: ValueKey('grade_${sub.id}_$_gradeStatus'),
                                                  initialValue: _gradeStatus,
                                                  style: TextStyle(color: primaryTextColor, fontSize: 13),
                                                  dropdownColor: surfaceColor,
                                                  decoration: InputDecoration(
                                                    labelText: 'Decision',
                                                    labelStyle: TextStyle(fontSize: 12, color: secondaryTextColor),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                                  ),
                                                  items: const [
                                                    DropdownMenuItem(value: 'approved', child: Text('Approved')),
                                                    DropdownMenuItem(value: 'under_review', child: Text('Under Review')),
                                                    DropdownMenuItem(value: 'resubmitted', child: Text('Needs Revision')),
                                                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                                                  ],
                                                  onChanged: (val) {
                                                    if (val != null) setState(() => _gradeStatus = val);
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              // Score input
                                              Expanded(
                                                flex: 4,
                                                child: TextFormField(
                                                  controller: _scoreController,
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,10}(\.\d{0,2})?')),
                                                  ],
                                                  style: TextStyle(color: primaryTextColor, fontSize: 13),
                                                  decoration: InputDecoration(
                                                    labelText: 'Score (Max ${widget.assignment.maxScore?.toInt() ?? 100})',
                                                    labelStyle: TextStyle(fontSize: 12, color: secondaryTextColor),
                                                    filled: true,
                                                    fillColor: Colors.white,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          TextFormField(
                                            controller: _feedbackController,
                                            maxLines: 3,
                                            minLines: 2,
                                            style: TextStyle(color: primaryTextColor, fontSize: 13),
                                            decoration: InputDecoration(
                                              hintText: 'Constructive feedback or revision instructions for intern...',
                                              hintStyle: TextStyle(color: secondaryTextColor, fontSize: 12),
                                              filled: true,
                                              fillColor: Colors.white,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            alignment: WrapAlignment.end,
                                            runSpacing: 8,
                                            children: [
                                              TextButton(
                                                onPressed: _isSavingReview ? null : _cancelGrading,
                                                child: const Text('Cancel'),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton(
                                                onPressed: _isSavingReview ? null : () => _submitReview(sub.id),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.primary,
                                                  foregroundColor: AppColors.ink,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                  elevation: 0,
                                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                ),
                                                child: _isSavingReview
                                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                                                    : const Text('Save Review', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                              ),
                                            ],
                                          ),
                                        ] else ...[
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: OutlinedButton.icon(
                                              onPressed: () => _openGradingForm(sub),
                                              icon: const Icon(Icons.rate_review_outlined, size: 15),
                                              label: Text(
                                                sub.score != null ? 'Edit Grade' : 'Grade Submission',
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: primaryTextColor,
                                                side: BorderSide(color: borderColor),
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        );
      },
    );
  }
}
