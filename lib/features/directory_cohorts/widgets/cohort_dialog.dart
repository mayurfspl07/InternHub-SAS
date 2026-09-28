import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/cohort_model.dart';
import '../cohorts_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../core/utils/formatters.dart';

class CohortDialog extends StatefulWidget {
  final Cohort? cohort; // If null, Create mode; else Edit mode
  final VoidCallback onSuccess;

  const CohortDialog({
    super.key,
    this.cohort,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    Cohort? cohort,
    required VoidCallback onSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CohortDialog(
        cohort: cohort,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<CohortDialog> createState() => _CohortDialogState();
}

class _CohortDialogState extends State<CohortDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSaving = false;
  String? _dateError;
  String? _nameError;
  String? _saveError;

  bool get isEdit => widget.cohort != null;

  @override
  void initState() {
    super.initState();
    if (widget.cohort != null) {
      _nameController.text = widget.cohort!.name;
      _descriptionController.text = widget.cohort!.description ?? '';
      if (widget.cohort!.startDate != null && widget.cohort!.startDate!.isNotEmpty) {
        _startDate = DateTime.tryParse(widget.cohort!.startDate!);
      }
      if (widget.cohort!.endDate != null && widget.cohort!.endDate!.isNotEmpty) {
        _endDate = DateTime.tryParse(widget.cohort!.endDate!);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _validateDates() {
    setState(() {
      if (_startDate != null && _endDate != null) {
        if (_endDate!.isBefore(_startDate!)) {
          _dateError = 'End date must be on or after start date';
        } else {
          _dateError = null;
        }
      } else {
        _dateError = null;
      }
    });
  }

  Future<void> _pickStartDate() async {
    final initialDate = _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        _validateDates();
      });
    }
  }

  Future<void> _pickEndDate() async {
    final initialDate = _endDate ?? _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
    );

    if (picked != null) {
      setState(() {
        _endDate = picked;
        _validateDates();
      });
    }
  }

  Future<void> _submit() async {
    final nameTrimmed = _nameController.text.trim();
    // Errors show next to the field; a snackbar would sit behind this dialog.
    setState(() {
      _nameError = nameTrimmed.isEmpty ? 'Enter a cohort name' : null;
      _saveError = null;
      _validateDates();
    });
    if (_nameError != null || _dateError != null) return;
    final descTrimmed = _descriptionController.text.trim();

    setState(() => _isSaving = true);

    try {
      final startStr = _startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : null;
      final endStr = _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null;

      if (isEdit) {
        await CohortsRepository().updateCohort(
          widget.cohort!.id,
          name: nameTrimmed,
          description: descTrimmed.isEmpty ? null : descTrimmed,
          startDate: startStr,
          endDate: endStr,
        );
      } else {
        await CohortsRepository().createCohort(
          name: nameTrimmed,
          description: descTrimmed.isEmpty ? null : descTrimmed,
          startDate: startStr,
          endDate: endStr,
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEdit ? 'Cohort updated' : 'Cohort created')),
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

    // An empty name is reported inline on Save, so it doesn't disable the button.
    final isFormValid = _nameController.text.trim().length <= 100 &&
        _descriptionController.text.trim().length <= 1000 &&
        _dateError == null;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Title & Close Icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit cohort' : 'New cohort',
                      style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor, letterSpacing: -0.3),
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

              // Form
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // COHORT NAME *
                    Text('Name', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() => _nameError = null),
                      style: AppTypography.body.copyWith(color: primaryTextColor),
                      decoration: InputDecoration(
                        errorText: _nameError,
                        hintText: 'e.g. Summer 2026 engineering',
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

                    // DESCRIPTION
                    Text('Description (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      minLines: 3,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (_) => setState(() {}),
                      style: AppTypography.body.copyWith(color: primaryTextColor),
                      decoration: InputDecoration(
                        hintText: 'Focus, track or what this group works on',
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

                    // START DATE & END DATE
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 360;

                        final startPickerWidget = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start date (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _pickStartDate,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 50),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  color: fieldBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _startDate != null ? formatDate(_startDate) : 'Not set',
                                        style: AppTypography.body.copyWith(color: _startDate != null ? primaryTextColor : secondaryTextColor),
                                      ),
                                    ),
                                    if (_startDate != null)
                                      IconButton(
                                        tooltip: 'Clear date',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => setState(() {
                                          _startDate = null;
                                          _validateDates();
                                        }),
                                        icon: Icon(Icons.clear_rounded, size: 16, color: secondaryTextColor),
                                      ),
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18,
                                      color: secondaryTextColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );

                        final endPickerWidget = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('End date (optional)', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _pickEndDate,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 50),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  color: fieldBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _endDate != null ? formatDate(_endDate) : 'Not set',
                                        style: AppTypography.body.copyWith(color: _endDate != null ? primaryTextColor : secondaryTextColor),
                                      ),
                                    ),
                                    if (_endDate != null)
                                      IconButton(
                                        tooltip: 'Clear date',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => setState(() {
                                          _endDate = null;
                                          _validateDates();
                                        }),
                                        icon: Icon(Icons.clear_rounded, size: 16, color: secondaryTextColor),
                                      ),
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18,
                                      color: secondaryTextColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );

                        if (isWide) {
                          return Row(
                            children: [
                              Expanded(child: startPickerWidget),
                              const SizedBox(width: 16),
                              Expanded(child: endPickerWidget),
                            ],
                          );
                        } else {
                          return Column(
                            children: [
                              startPickerWidget,
                              const SizedBox(height: 16),
                              endPickerWidget,
                            ],
                          );
                        }
                      },
                    ),

                    if (_dateError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _dateError!,
                        style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
                      ),
                    ],
                    if (_saveError != null) ...[
                      const SizedBox(height: 12),
                      Text(_saveError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
                    ],

                    const SizedBox(height: 28),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            minimumSize: const Size(0, 44),
                            shape: const StadiumBorder(),
                          ),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: (_isSaving || !isFormValid) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            elevation: 0,
                            minimumSize: const Size(0, 44),
                            shape: const StadiumBorder(),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                                )
                              : Text(isEdit ? 'Save' : 'Create cohort'),
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
