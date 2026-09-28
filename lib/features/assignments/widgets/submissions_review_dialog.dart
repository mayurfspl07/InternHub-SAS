import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/models/assignment_model.dart';
import '../assignments_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

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
  // No decision until the reviewer picks one; nothing is pre-approved.
  String? _gradeStatus;
  String? _gradeError;
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
          _errorMessage = apiErrorMessage(e);
        });
      }
    }
  }

  void _openGradingForm(AssignmentSubmission sub) {
    setState(() {
      _gradingSubmissionId = sub.id;
      final current = sub.status.toLowerCase();
      // Keep an earlier decision; a fresh (re)submission starts undecided.
      _gradeStatus = const ['approved', 'under_review', 'rejected'].contains(current) ? current : null;
      _gradeError = null;
      final score = sub.score;
      _scoreController.text = score == null ? '' : (score % 1 == 0 ? score.toInt().toString() : score.toString());
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

    // Problems show in the form; a snackbar would be hidden behind this sheet.
    String? problem;
    if (_gradeStatus == null) {
      problem = 'Choose a decision';
    } else if (scoreVal != null && (scoreVal < 0 || scoreVal > maxScore)) {
      problem = 'Score must be between 0 and ${maxScore % 1 == 0 ? maxScore.toInt() : maxScore}';
    }
    if (problem != null) {
      setState(() => _gradeError = problem);
      return;
    }

    setState(() {
      _isSavingReview = true;
      _gradeError = null;
    });

    try {
      await AssignmentsRepository().reviewSubmission(
        submissionId,
        status: _gradeStatus!,
        score: scoreVal,
        feedback: _feedbackController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Review saved')));
        _cancelGrading();
        await _fetchSubmissions();
        widget.onDataChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _gradeError = apiErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingReview = false);
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    try {
      opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open $url")));
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
        label = 'Under review';
        break;
      case 'resubmitted':
        bg = AppColors.warningSoft;
        fg = AppColors.warningInk;
        label = 'Resubmitted';
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
        style: AppTypography.label.copyWith(color: fg, fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = AppColors.surface;
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
              BoxShadow(color: Color(0x14000000), blurRadius: 20, spreadRadius: 2),
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
                            style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.assignment.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(color: secondaryTextColor),
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
                                Text(_errorMessage!, style: AppTypography.caption.copyWith(color: secondaryTextColor)),
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
                                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Enrolled interns have not submitted solutions for this assignment yet.',
                                        textAlign: TextAlign.center,
                                        style: AppTypography.caption.copyWith(color: secondaryTextColor),
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
                                                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.warningInk),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    sub.displayName,
                                                    style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                                                  ),
                                                  if (sub.userEmail?.isNotEmpty == true) ...[
                                                    const SizedBox(height: 1),
                                                    Text(
                                                      sub.userEmail!,
                                                      style: AppTypography.caption.copyWith(color: secondaryTextColor),
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
                                              style: AppTypography.caption.copyWith(color: secondaryTextColor),
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
                                                  'Score ${sub.score! % 1 == 0 ? sub.score!.toInt() : sub.score} / ${widget.assignment.maxScore?.toInt() ?? 100}',
                                                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.successInk),
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
                                              color: AppColors.surface,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: borderColor),
                                            ),
                                            child: Text(
                                              sub.submissionText!.trim(),
                                              style: AppTypography.caption.copyWith(color: primaryTextColor, height: 1.4),
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
                                                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: primaryTextColor),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              if (sub.hasFile && sub.fileUrl != null)
                                                InkWell(
                                                  // Authenticated download (the URL is an API path, not a public link).
                                                  onTap: () => FileExportService.downloadAndShare(
                                                    endpoint: sub.fileUrl!,
                                                    defaultFileName: sub.fileName ?? 'submission',
                                                  ),
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
                                                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: primaryTextColor),
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
                                                    style: AppTypography.caption.copyWith(color: AppColors.warningInk, height: 1.35),
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
                                          Text('Your review', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              // Decision Dropdown
                                              Expanded(
                                                flex: 5,
                                                child: DropdownButtonFormField<String>(
                                                  key: ValueKey('grade_${sub.id}_$_gradeStatus'),
                                                  initialValue: _gradeStatus,
                                                  isExpanded: true,
                                                  hint: const Text('Choose'),
                                                  style: AppTypography.caption.copyWith(color: primaryTextColor),
                                                  dropdownColor: surfaceColor,
                                                  decoration: InputDecoration(
                                                    labelText: 'Decision',
                                                    labelStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                                                    filled: true,
                                                    fillColor: AppColors.surface,
                                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                                  ),
                                                  // "resubmitted" is set by the server when the intern hands in again, so it isn't a reviewer choice.
                                                  items: const [
                                                    DropdownMenuItem(value: 'approved', child: Text('Approve')),
                                                    DropdownMenuItem(value: 'under_review', child: Text('Still reviewing')),
                                                    DropdownMenuItem(value: 'rejected', child: Text('Reject (ask to redo)')),
                                                  ],
                                                  onChanged: (val) {
                                                    if (val != null) {
                                                      setState(() {
                                                        _gradeStatus = val;
                                                        _gradeError = null;
                                                      });
                                                    }
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
                                                  style: AppTypography.caption.copyWith(color: primaryTextColor),
                                                  decoration: InputDecoration(
                                                    labelText: 'Score / ${widget.assignment.maxScore?.toInt() ?? 100}',
                                                    hintText: 'Optional',
                                                    labelStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                                                    filled: true,
                                                    fillColor: AppColors.surface,
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
                                            style: AppTypography.caption.copyWith(color: primaryTextColor),
                                            decoration: InputDecoration(
                                              hintText: 'Feedback for the intern (what to keep, what to change)',
                                              hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                                              filled: true,
                                              fillColor: AppColors.surface,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                            ),
                                          ),
                                          if (_gradeError != null) ...[
                                            const SizedBox(height: 8),
                                            Text(_gradeError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
                                          ],
                                          const SizedBox(height: 12),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
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
                                                  foregroundColor: AppColors.onPrimary,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                  elevation: 0,
                                                  minimumSize: const Size(0, 44),
                                                ),
                                                child: _isSavingReview
                                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                                                    : const Text('Save review'),
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
                                                sub.score != null || const ['approved', 'rejected', 'under_review'].contains(sub.status.toLowerCase()) ? 'Change review' : 'Review',
                                                style: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: primaryTextColor,
                                                side: BorderSide(color: borderColor),
                                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                minimumSize: const Size(0, 44),
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
