import 'dart:io';
import 'package:flutter/material.dart';
import '../../../shared/models/assignment_model.dart';
import '../assignments_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../core/services/document_picker.dart';

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
  String? _formError;
  String? _urlError;

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

  /// Solutions are usually documents or archives, not just photos.
  static const _solutionTypes = ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'zip', 'png', 'jpg', 'jpeg'];

  Future<void> _pickFile() async {
    try {
      final picked = await pickDocument(allowedExtensions: _solutionTypes, maxMb: 2);
      if (picked != null) {
        setState(() {
          _file = picked.file;
          _fileName = picked.name;
          _fileSize = picked.sizeBytes;
          _fileError = null;
          _formError = null;
        });
      }
    } on DocumentPickException catch (e) {
      setState(() => _fileError = e.message);
    } catch (e) {
      setState(() => _fileError = "Couldn't open that file. Try another one.");
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
    // Shown inside the dialog; a snackbar would sit behind it.
    if (textTrimmed.isEmpty && githubTrimmed.isEmpty && _file == null && _fileName == null) {
      setState(() => _formError = 'Add a summary, a link or a file.');
      return;
    }
    final uri = Uri.tryParse(githubTrimmed);
    if (githubTrimmed.isNotEmpty && (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http') || uri.host.isEmpty)) {
      setState(() => _urlError = 'Enter a full link starting with https://');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    try {
      final res = await AssignmentsRepository().submitAssignment(
        widget.assignment.id,
        submissionText: textTrimmed.isNotEmpty ? textTrimmed : null,
        githubUrl: githubTrimmed.isNotEmpty ? githubTrimmed : null,
        file: _file,
      );

      final message = res['message']?.toString() ?? 'Work submitted';

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _formError = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogBg = AppColors.surface;
    final borderColor = AppColors.border;
    final fieldBg = AppColors.surface;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                          isResubmission ? 'Resubmit work' : 'Submit work',
                          style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor, letterSpacing: -0.3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.assignment.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.infoInk),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: secondaryTextColor),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Solution Summary / Notes
              Text('Summary', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                maxLines: 4,
                minLines: 3,
                style: AppTypography.body.copyWith(color: primaryTextColor),
                decoration: InputDecoration(
                  hintText: 'What you built and anything your mentor should know',
                  hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
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
              Text('Link (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _githubController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) {
                  if (_urlError != null || _formError != null) {
                    setState(() {
                      _urlError = null;
                      _formError = null;
                    });
                  }
                },
                style: AppTypography.body.copyWith(color: primaryTextColor),
                decoration: InputDecoration(
                  hintText: 'https://github.com/you/repo',
                  errorText: _urlError,
                  hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
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
              Text('File (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
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
                      onPressed: _isSubmitting ? null : _pickFile,
                      icon: const Icon(Icons.file_upload_outlined, size: 16),
                      label: Text('Choose file', style: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceMuted,
                        foregroundColor: primaryTextColor,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: borderColor),
                        ),
                        minimumSize: const Size(0, 44),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fileName != null
                            ? '$_fileName${_fileSize != null ? " (${(_fileSize! / 1024).round()}KB)" : ""}'
                            : 'PDF, Office, zip or image · up to 2 MB',
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(color: _fileName != null ? primaryTextColor : secondaryTextColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_fileName != null)
                      IconButton(
                        tooltip: 'Remove file',
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: _isSubmitting ? null : _removeFile,
                        color: secondaryTextColor,
                      ),
                  ],
                ),
              ),
              if (_fileError != null) ...[
                const SizedBox(height: 6),
                Text(_fileError!, style: AppTypography.label.copyWith(color: AppColors.dangerInk)),
              ],
              if (_formError != null) ...[
                const SizedBox(height: 12),
                Text(_formError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
              ],

              const SizedBox(height: 28),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryTextColor,
                      side: BorderSide(color: borderColor),
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                          )
                        : Text(isResubmission ? 'Resubmit' : 'Submit'),
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
