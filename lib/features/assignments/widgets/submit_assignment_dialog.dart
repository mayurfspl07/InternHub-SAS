import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/models/assignment_model.dart';
import '../assignments_repository.dart';
import '../../../core/constants/app_colors.dart';

class SubmitAssignmentDialog extends StatefulWidget {
  final AssignmentItem assignment;
  final VoidCallback onSuccess;

  const SubmitAssignmentDialog({
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
      builder: (_) => SubmitAssignmentDialog(
        assignment: assignment,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<SubmitAssignmentDialog> createState() => _SubmitAssignmentDialogState();
}

class _SubmitAssignmentDialogState extends State<SubmitAssignmentDialog> {
  final _textController = TextEditingController();
  final _githubController = TextEditingController();

  File? _file;
  String? _fileName;
  int? _fileSize;
  String? _fileError;

  bool _isSubmitting = false;

  bool get isResubmission => widget.assignment.isSubmitted || widget.assignment.mySubmission != null;

  @override
  void initState() {
    super.initState();
    final prev = widget.assignment.mySubmission;
    if (prev != null) {
      _textController.text = prev.submissionText ?? '';
      _githubController.text = prev.githubUrl ?? '';
      if (prev.hasFile && prev.fileName != null) {
        _fileName = prev.fileName;
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _githubController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMedia();
      if (picked != null) {
        final file = File(picked.path);
        final size = await file.length();

        if (size > 2 * 1024 * 1024) {
          setState(() {
            _fileError = 'File exceeds 2MB limit (${(size / (1024 * 1024)).toStringAsFixed(1)}MB)';
          });
          return;
        }

        setState(() {
          _file = file;
          _fileName = picked.name;
          _fileSize = size;
          _fileError = null;
        });
      }
    } catch (e) {
      setState(() => _fileError = 'Failed to select file: $e');
    }
  }

  void _removeFile() {
    setState(() {
      _file = null;
      _fileName = null;
      _fileSize = null;
      _fileError = null;
    });
  }

  Future<void> _handleSubmit() async {
    final textTrimmed = _textController.text.trim();
    final githubTrimmed = _githubController.text.trim();

    // Requires at least one of: submission_text, github_url, or file
    if (textTrimmed.isEmpty && githubTrimmed.isEmpty && _file == null && _fileName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide at least a summary, GitHub URL, or attachment file.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final res = await AssignmentsRepository().submitAssignment(
        widget.assignment.id,
        submissionText: textTrimmed.isNotEmpty ? textTrimmed : null,
        githubUrl: githubTrimmed.isNotEmpty ? githubTrimmed : null,
        file: _file,
      );

      final message = res['message']?.toString() ?? 'Solution submitted successfully!';

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit assignment: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogBg = Colors.white;
    final borderColor = AppColors.border;
    final fieldBg = Colors.white;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isResubmission ? 'Resubmit Solution' : 'Submit Solution',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.assignment.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Solution Summary / Notes
              Text(
                'SOLUTION SUMMARY & NOTES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                maxLines: 4,
                minLines: 3,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Summarize your solution, key architecture decisions, and deliverables...',
                  hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // GitHub / Demo URL
              Text(
                'GITHUB / DEMO URL (OPTIONAL)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _githubController,
                keyboardType: TextInputType.url,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'https://github.com/your-username/repo-name',
                  hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                  prefixIcon: Icon(Icons.link_rounded, size: 18, color: secondaryTextColor),
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Solution Attachment File (Optional, max 2MB)
              Text(
                'ATTACH SOLUTION FILE (OPTIONAL, MAX 2MB)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: fieldBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: const Text('Choose File', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceMuted,
                        foregroundColor: primaryTextColor,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: borderColor),
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fileName != null
                            ? '$_fileName${_fileSize != null ? " (${(_fileSize! / 1024).round()}KB)" : ""}'
                            : 'No file chosen',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: _fileName != null ? primaryTextColor : secondaryTextColor,
                          fontWeight: _fileName != null ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (_fileName != null)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _removeFile,
                        color: secondaryTextColor,
                      ),
                  ],
                ),
              ),
              if (_fileError != null) ...[
                const SizedBox(height: 6),
                Text(_fileError!, style: const TextStyle(color: AppColors.danger, fontSize: 11)),
              ],

              const SizedBox(height: 28),

              // Actions
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryTextColor,
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.ink,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: AppColors.warning),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                          )
                        : Text(
                            isResubmission ? 'Resubmit Solution' : 'Submit Solution',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
