import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/assignment_model.dart';
import '../assignments_repository.dart';
import '../../../core/constants/app_colors.dart';

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
    } catch (_) {}
  }

  // Strip forbidden characters: < > _ + - =
  String _sanitizeTitle(String value) {
    return value.replaceAll(RegExp(r'[<>_\+\-=]'), '');
  }

  // Strip forbidden characters: < > _ + -
  String _sanitizeDescription(String value) {
    return value.replaceAll(RegExp(r'[<>_\+\-]'), '');
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = (_dueDate != null && !_dueDate!.isBefore(today)) ? _dueDate! : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today, // Must be >= today
      lastDate: DateTime(2040),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: AppColors.ink,
              surface: Colors.white,
              onSurface: AppColors.ink,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pickBriefFile() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMedia();
      if (picked != null) {
        final file = File(picked.path);
        final size = await file.length();

        if (size > 2 * 1024 * 1024) {
          setState(() {
            _briefError = 'Brief file exceeds 2MB limit (${(size / (1024 * 1024)).toStringAsFixed(1)}MB)';
          });
          return;
        }

        setState(() {
          _briefFile = file;
          _briefFileName = picked.name;
          _briefFileSize = size;
          _briefError = null;
        });
      }
    } catch (e) {
      setState(() => _briefError = 'Failed to select file: $e');
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

    final titleTrimmed = _sanitizeTitle(_titleController.text.trim());
    if (titleTrimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assignment title is required')),
      );
      return;
    }

    if (titleTrimmed.length > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assignment title cannot exceed 100 characters')),
      );
      return;
    }

    final descTrimmed = _sanitizeDescription(_descriptionController.text.trim());
    if (descTrimmed.length > 5000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description cannot exceed 5000 characters')),
      );
      return;
    }

    final maxScore = double.tryParse(_maxScoreController.text.trim());
    if (maxScore == null || maxScore <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max score must be a valid positive number')),
      );
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_dueDate != null && _dueDate!.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Due date must be today or in the future')),
      );
      return;
    }

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
          maxScore: maxScore,
          status: _selectedStatus,
        );

        if (_briefFile != null) {
          await AssignmentsRepository().uploadAttachment(result.id, _briefFile!);
        }
      } else {
        result = await AssignmentsRepository().createAssignment(
          title: titleTrimmed,
          description: descTrimmed.isEmpty ? null : descTrimmed,
          projectId: _selectedProjectId,
          cohortId: _selectedCohortId,
          dueDate: dueStr,
          maxScore: maxScore,
          status: _selectedStatus,
        );

        if (_briefFile != null) {
          await AssignmentsRepository().uploadAttachment(result.id, _briefFile!);
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Assignment updated successfully' : 'Assignment created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${isEdit ? "update" : "create"} assignment: $e'),
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
        constraints: const BoxConstraints(maxWidth: 580),
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
                          isEdit ? 'Edit Assignment' : 'Create New Assignment',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Assign tasks, specify guidelines, attach project briefs, and define grading criteria.',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                            height: 1.3,
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
                        Row(
                          children: [
                            Text(
                              'ASSIGNMENT TITLE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('*', style: TextStyle(fontSize: 14, color: AppColors.danger)),
                          ],
                        ),
                        Text(
                          '${_titleController.text.length} / 100',
                          style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _titleController,
                      maxLength: 100,
                      onChanged: (val) {
                        final clean = _sanitizeTitle(val);
                        if (clean != val) {
                          _titleController.value = TextEditingValue(
                            text: clean,
                            selection: TextSelection.collapsed(offset: clean.length),
                          );
                        }
                        setState(() {});
                      },
                      style: TextStyle(color: primaryTextColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'e.g. Build REST API Module with Tests',
                        hintStyle: TextStyle(color: secondaryTextColor, fontSize: 14),
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
                        Text(
                          'INSTRUCTIONS & OBJECTIVES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: primaryTextColor,
                          ),
                        ),
                        Text(
                          '${_descriptionController.text.length} / 5000',
                          style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      minLines: 3,
                      maxLength: 5000,
                      onChanged: (val) {
                        final clean = _sanitizeDescription(val);
                        if (clean != val) {
                          _descriptionController.value = TextEditingValue(
                            text: clean,
                            selection: TextSelection.collapsed(offset: clean.length),
                          );
                        }
                        setState(() {});
                      },
                      style: TextStyle(color: primaryTextColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Detail what interns need to complete, submission requirements, deliverables, etc.',
                        hintStyle: TextStyle(color: secondaryTextColor, fontSize: 14),
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
                            Text(
                              'LINKED PROJECT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int?>(
                              initialValue: _selectedProjectId,
                              isExpanded: true,
                              style: TextStyle(color: primaryTextColor, fontSize: 14),
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
                            Text(
                              'TARGET COHORT',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int?>(
                              initialValue: _selectedCohortId,
                              isExpanded: true,
                              style: TextStyle(color: primaryTextColor, fontSize: 14),
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
                            Text(
                              'DUE DATE',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _pickDueDate,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                decoration: BoxDecoration(
                                  color: fieldBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _dueDate != null ? DateFormat('dd/MM/yyyy').format(_dueDate!) : 'dd/mm/yyyy',
                                        style: TextStyle(
                                          color: _dueDate != null ? primaryTextColor : secondaryTextColor,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (_dueDate != null)
                                      InkWell(
                                        onTap: () => setState(() => _dueDate = null),
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(Icons.clear_rounded, size: 16, color: secondaryTextColor),
                                        ),
                                      ),
                                    Icon(Icons.calendar_today_outlined, size: 16, color: secondaryTextColor),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );

                        final maxScoreField = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MAX SCORE',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _maxScoreController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,10}(\.\d{0,2})?')),
                              ],
                              style: TextStyle(color: primaryTextColor, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '100',
                                hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
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
                            Text(
                              'STATUS',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedStatus,
                              isExpanded: true,
                              style: TextStyle(color: primaryTextColor, fontSize: 13),
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
                    Text(
                      'PROJECT BRIEF ATTACHMENT',
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
                            onPressed: _pickBriefFile,
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
                              _briefFileName != null
                                  ? '$_briefFileName${_briefFileSize != null ? " (${(_briefFileSize! / 1024).round()}KB)" : ""}'
                                  : 'Max 2MB',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: _briefFileName != null ? primaryTextColor : secondaryTextColor,
                                fontWeight: _briefFileName != null ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (_briefFileName != null)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _removeBriefFile,
                              color: secondaryTextColor,
                            ),
                        ],
                      ),
                    ),
                    if (_briefError != null) ...[
                      const SizedBox(height: 6),
                      Text(_briefError!, style: const TextStyle(color: AppColors.danger, fontSize: 11)),
                    ],

                    const SizedBox(height: 28),

                    // Actions
                    Wrap(
                      alignment: WrapAlignment.end,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
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
                          onPressed: _isSaving ? null : _submit,
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
                          child: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                                )
                              : Text(
                                  isEdit ? 'Save Changes' : 'Create Assignment',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
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
