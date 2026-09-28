import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/assignment_model.dart';
import '../assignments_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/services/document_picker.dart';

class AssignmentFormDialog extends StatefulWidget {
  final AssignmentItem? assignment; // If null, create; else edit
  final VoidCallback onSuccess;

  const AssignmentFormDialog({
    super.key,
    this.assignment,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    AssignmentItem? assignment,
    required VoidCallback onSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AssignmentFormDialog(
        assignment: assignment,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<AssignmentFormDialog> createState() => _AssignmentFormDialogState();
}

class _AssignmentFormDialogState extends State<AssignmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _maxScoreController = TextEditingController(text: '100');

  int? _selectedProjectId;
  int? _selectedCohortId;
  DateTime? _dueDate;
  String _selectedStatus = 'active';

  File? _briefFile;
  String? _briefFileName;
  int? _briefFileSize;
  String? _briefError;

  bool _isSaving = false;
  // Set once a new assignment exists, so a retry after a failed brief upload
  // uploads again instead of creating a second copy.
  AssignmentItem? _created;
  String? _titleError;
  String? _scoreError;
  String? _dueError;
  String? _saveError;
  DateTime? _originalDueDate;
  List<AssignmentPickerOption> _projectOptions = [];
  List<AssignmentPickerOption> _cohortOptions = [];

  bool get isEdit => widget.assignment != null;

  @override
  void initState() {
    super.initState();
    if (widget.assignment != null) {
      final a = widget.assignment!;
      _titleController.text = a.title;
      _descriptionController.text = a.description ?? '';
      _maxScoreController.text = a.maxScore != null
          ? (a.maxScore! % 1 == 0 ? a.maxScore!.toInt().toString() : a.maxScore!.toString())
          : '100';
      _selectedProjectId = a.projectId;
      _selectedCohortId = a.cohortId;
      _selectedStatus = a.status.toLowerCase();
      if (a.dueDate != null && a.dueDate!.isNotEmpty) {
        _dueDate = DateTime.tryParse(a.dueDate!);
        _originalDueDate = _dueDate;
      }
      if (a.hasAttachment && a.attachmentName != null) {
        _briefFileName = a.attachmentName;
      }
    }
    _loadPickers();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _maxScoreController.dispose();
    super.dispose();
  }

  Future<void> _loadPickers() async {
    try {
      final projs = await AssignmentsRepository().getProjectOptions();
      final cohorts = await AssignmentsRepository().getCohortOptions();
      if (mounted) {
        setState(() {
          _projectOptions = projs;
          _cohortOptions = cohorts;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _saveError = "Couldn't load projects and cohorts. You can still save without them.");
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // An overdue assignment keeps its old date pickable so it can still be edited.
    final first = (_originalDueDate != null && _originalDueDate!.isBefore(today)) ? _originalDueDate! : today;
    final initial = (_dueDate != null && !_dueDate!.isBefore(first)) ? _dueDate! : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime(today.year + 5),
    );

    if (picked != null) {
      setState(() {
        _dueDate = picked;
        _dueError = null;
      });
    }
  }

  /// Briefs are documents, not just images: PDF, Office files, text, zip or images, up to 2 MB.
  static const _briefTypes = ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'zip', 'png', 'jpg', 'jpeg'];

  Future<void> _pickBriefFile() async {
    try {
      final picked = await pickDocument(allowedExtensions: _briefTypes, maxMb: 2);
      if (picked != null) {
        setState(() {
          _briefFile = picked.file;
          _briefFileName = picked.name;
          _briefFileSize = picked.sizeBytes;
          _briefError = null;
        });
      }
    } on DocumentPickException catch (e) {
      setState(() => _briefError = e.message);
    } catch (e) {
      setState(() => _briefError = "Couldn't open that file. Try another one.");
    }
  }

  void _removeBriefFile() {
    setState(() {
      _briefFile = null;
      _briefFileName = null;
      _briefFileSize = null;
      _briefError = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final titleTrimmed = _titleController.text.trim();
    final descTrimmed = _descriptionController.text.trim();
    final maxScore = double.tryParse(_maxScoreController.text.trim());
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // A past date is only a problem if it was changed; overdue work stays editable.
    final dueChanged = _dueDate != _originalDueDate;

    // Errors show under their fields; a snackbar would sit behind this dialog.
    setState(() {
      _titleError = titleTrimmed.isEmpty ? 'Enter a title' : null;
      _scoreError = (maxScore == null || maxScore <= 0) ? 'Enter a score above 0' : null;
      _dueError = (_dueDate != null && dueChanged && _dueDate!.isBefore(today)) ? "Due date can't be in the past" : null;
      _saveError = null;
    });
    if (_titleError != null || _scoreError != null || _dueError != null) return;

    setState(() => _isSaving = true);

    try {
      final dueStr = _dueDate != null ? DateFormat('yyyy-MM-dd').format(_dueDate!) : null;

      AssignmentItem result;
      if (isEdit) {
        result = await AssignmentsRepository().updateAssignment(
          widget.assignment!.id,
          title: titleTrimmed,
          description: descTrimmed.isEmpty ? null : descTrimmed,
          projectId: _selectedProjectId,
          cohortId: _selectedCohortId,
          dueDate: dueStr,
          maxScore: maxScore!,
          status: _selectedStatus,
        );
      } else {
        result = _created ??
            await AssignmentsRepository().createAssignment(
              title: titleTrimmed,
              description: descTrimmed.isEmpty ? null : descTrimmed,
              projectId: _selectedProjectId,
              cohortId: _selectedCohortId,
              dueDate: dueStr,
              maxScore: maxScore!,
              status: _selectedStatus,
            );
        _created = result;
      }

      if (_briefFile != null) {
        try {
          await AssignmentsRepository().uploadAttachment(result.id, _briefFile!);
        } catch (e) {
          // The assignment is saved; only the file failed. Keep the dialog so they can retry the upload.
          widget.onSuccess();
          if (mounted) {
            setState(() {
              _isSaving = false;
              _saveError = "Assignment saved, but the brief didn't upload: ${apiErrorMessage(e)} Tap Save to try the file again.";
            });
          }
          return;
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'Assignment updated' : 'Assignment created')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveError = apiErrorMessage(e);
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
        constraints: const BoxConstraints(maxWidth: 580),
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
                          isEdit ? 'Edit assignment' : 'New assignment',
                          style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor, letterSpacing: -0.3),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Give interns a brief, a due date and a score to aim for.',
                          style: AppTypography.caption.copyWith(color: secondaryTextColor, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: secondaryTextColor),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ASSIGNMENT TITLE *
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Title', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                        Text(
                          '${_titleController.text.length} / 100',
                          style: AppTypography.label.copyWith(color: secondaryTextColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleController,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() => _titleError = null),
                      style: AppTypography.body.copyWith(color: primaryTextColor),
                      decoration: InputDecoration(
                        hintText: 'e.g. Build a REST API with tests',
                        errorText: _titleError,
                        hintStyle: AppTypography.body.copyWith(color: secondaryTextColor),
                        filled: true,
                        fillColor: fieldBg,
                        counterText: '',
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
                    const SizedBox(height: 20),

                    // INSTRUCTIONS & OBJECTIVES
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Instructions (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                        Text(
                          '${_descriptionController.text.length} / 5000',
                          style: AppTypography.label.copyWith(color: secondaryTextColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      minLines: 3,
                      maxLength: 5000,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      style: AppTypography.body.copyWith(color: primaryTextColor),
                      decoration: InputDecoration(
                        hintText: 'What to build, what to hand in, how it is graded',
                        hintStyle: AppTypography.body.copyWith(color: secondaryTextColor),
                        filled: true,
                        fillColor: fieldBg,
                        counterText: '',
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
                    const SizedBox(height: 20),

                    // LINKED PROJECT & TARGET COHORT
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 380;

                        final projectDropdown = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Project (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int?>(
                              initialValue: _selectedProjectId,
                              isExpanded: true,
                              style: AppTypography.body.copyWith(color: primaryTextColor),
                              dropdownColor: dialogBg,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.folder_outlined, size: 18, color: secondaryTextColor),
                                filled: true,
                                fillColor: fieldBg,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('None / General', overflow: TextOverflow.ellipsis),
                                ),
                                ..._projectOptions.map(
                                  (p) => DropdownMenuItem<int?>(
                                    value: p.id,
                                    child: Text(p.name, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedProjectId = val),
                            ),
                          ],
                        );

                        final cohortDropdown = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cohort (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int?>(
                              initialValue: _selectedCohortId,
                              isExpanded: true,
                              style: AppTypography.body.copyWith(color: primaryTextColor),
                              dropdownColor: dialogBg,
                              decoration: InputDecoration(
                                prefixIcon: Icon(Icons.groups_outlined, size: 18, color: secondaryTextColor),
                                filled: true,
                                fillColor: fieldBg,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('None / All Interns', overflow: TextOverflow.ellipsis),
                                ),
                                ..._cohortOptions.map(
                                  (c) => DropdownMenuItem<int?>(
                                    value: c.id,
                                    child: Text(c.name, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                              onChanged: (val) => setState(() => _selectedCohortId = val),
                            ),
                          ],
                        );

                        if (isWide) {
                          return Row(
                            children: [
                              Expanded(child: projectDropdown),
                              const SizedBox(width: 14),
                              Expanded(child: cohortDropdown),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              projectDropdown,
                              const SizedBox(height: 16),
                              cohortDropdown,
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // DUE DATE, MAX SCORE, STATUS
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 420;

                        final dueDateField = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Due date (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _pickDueDate,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 50),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: fieldBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _dueError != null ? AppColors.danger : borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _dueDate != null ? formatDate(_dueDate) : 'No due date',
                                        style: AppTypography.caption.copyWith(color: _dueDate != null ? primaryTextColor : secondaryTextColor),
                                      ),
                                    ),
                                    if (_dueDate != null)
                                      IconButton(
                                        tooltip: 'Clear date',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => setState(() {
                                          _dueDate = null;
                                          _dueError = null;
                                        }),
                                        icon: Icon(Icons.clear_rounded, size: 16, color: secondaryTextColor),
                                      ),
                                    Icon(Icons.calendar_today_outlined, size: 16, color: secondaryTextColor),
                                  ],
                                ),
                              ),
                            ),
                            if (_dueError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(_dueError!, style: AppTypography.label.copyWith(color: AppColors.dangerInk)),
                              ),
                          ],
                        );

                        final maxScoreField = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Max score', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _maxScoreController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,10}(\.\d{0,2})?')),
                              ],
                              style: AppTypography.caption.copyWith(color: primaryTextColor),
                              onChanged: (_) {
                                if (_scoreError != null) setState(() => _scoreError = null);
                              },
                              decoration: InputDecoration(
                                errorText: _scoreError,
                                hintText: '100',
                                hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                                filled: true,
                                fillColor: fieldBg,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                            ),
                          ],
                        );

                        final statusField = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Status', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedStatus,
                              isExpanded: true,
                              style: AppTypography.caption.copyWith(color: primaryTextColor),
                              dropdownColor: dialogBg,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: fieldBg,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(color: borderColor),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'active', child: Text('Active')),
                                DropdownMenuItem(value: 'draft', child: Text('Draft')),
                                DropdownMenuItem(value: 'closed', child: Text('Closed')),
                                DropdownMenuItem(value: 'archived', child: Text('Archived')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedStatus = val);
                              },
                            ),
                          ],
                        );

                        if (isWide) {
                          return Row(
                            children: [
                              Expanded(flex: 4, child: dueDateField),
                              const SizedBox(width: 12),
                              Expanded(flex: 3, child: maxScoreField),
                              const SizedBox(width: 12),
                              Expanded(flex: 3, child: statusField),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              dueDateField,
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(child: maxScoreField),
                                  const SizedBox(width: 12),
                                  Expanded(child: statusField),
                                ],
                              ),
                            ],
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // PROJECT BRIEF ATTACHMENT
                    Text('Brief file (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
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
                            onPressed: _isSaving ? null : _pickBriefFile,
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
                              _briefFileName != null
                                  ? '$_briefFileName${_briefFileSize != null ? " (${(_briefFileSize! / 1024).round()}KB)" : ""}'
                                  : 'PDF, Office, text, zip or image · up to 2 MB',
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(color: _briefFileName != null ? primaryTextColor : secondaryTextColor, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (_briefFileName != null)
                            IconButton(
                              tooltip: 'Remove file',
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              onPressed: _isSaving ? null : _removeBriefFile,
                              color: secondaryTextColor,
                            ),
                        ],
                      ),
                    ),
                    if (_briefError != null) ...[
                      const SizedBox(height: 6),
                      Text(_briefError!, style: AppTypography.label.copyWith(color: AppColors.dangerInk)),
                    ],
                    if (_saveError != null) ...[
                      const SizedBox(height: 12),
                      Text(_saveError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
                    ],

                    const SizedBox(height: 28),

                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
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
                          onPressed: _isSaving ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            elevation: 0,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                                )
                              : Text(isEdit || _created != null ? 'Save' : 'Create assignment'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
