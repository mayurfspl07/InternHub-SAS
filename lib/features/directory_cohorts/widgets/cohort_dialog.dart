import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/cohort_model.dart';
import '../cohorts_repository.dart';
import '../../../core/constants/app_colors.dart';

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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
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
      setState(() {
        _endDate = picked;
        _validateDates();
      });
    }
  }

  Future<void> _submit() async {
    final nameTrimmed = _nameController.text.trim();
    if (nameTrimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cohort name is required')),
      );
      return;
    }

    if (nameTrimmed.length > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cohort name must be at most 100 characters')),
      );
      return;
    }

    final descTrimmed = _descriptionController.text.trim();
    if (descTrimmed.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description must be at most 1000 characters')),
      );
      return;
    }

    _validateDates();
    if (_dateError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_dateError!)),
      );
      return;
    }

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
          SnackBar(
            content: Text(
              isEdit
                  ? 'Cohort updated successfully'
                  : 'Cohort created successfully',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${isEdit ? "update" : "create"} cohort: $e'),
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

    final isFormValid = _nameController.text.trim().isNotEmpty &&
        _nameController.text.trim().length <= 100 &&
        _descriptionController.text.trim().length <= 1000 &&
        _dateError == null;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                      isEdit ? 'Edit Cohort' : 'Create New Cohort',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                        letterSpacing: -0.3,
                      ),
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
                        size: 20,
                        color: secondaryTextColor,
                      ),
                    ),
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
                    Row(
                      children: [
                        Text(
                          'COHORT NAME',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '*',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.danger,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: primaryTextColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'e.g., Summer 2026 Batch - Engineering',
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

                    // DESCRIPTION
                    Text(
                      'DESCRIPTION',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      minLines: 3,
                      maxLength: 1000,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: primaryTextColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Details on batch focus, track, curriculum, or cohort expectations...',
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

                    // START DATE & END DATE
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 360;

                        final startPickerWidget = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'START DATE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _pickStartDate,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  color: fieldBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _startDate != null
                                            ? DateFormat('dd/MM/yyyy').format(_startDate!)
                                            : 'dd/mm/yyyy',
                                        style: TextStyle(
                                          color: _startDate != null ? primaryTextColor : secondaryTextColor,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (_startDate != null)
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _startDate = null;
                                            _validateDates();
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(Icons.clear_rounded, size: 16, color: secondaryTextColor),
                                        ),
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
                            Text(
                              'END DATE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _pickEndDate,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  color: fieldBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _endDate != null
                                            ? DateFormat('dd/MM/yyyy').format(_endDate!)
                                            : 'dd/mm/yyyy',
                                        style: TextStyle(
                                          color: _endDate != null ? primaryTextColor : secondaryTextColor,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (_endDate != null)
                                      InkWell(
                                        onTap: () {
                                          setState(() {
                                            _endDate = null;
                                            _validateDates();
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.only(right: 6),
                                          child: Icon(Icons.clear_rounded, size: 16, color: secondaryTextColor),
                                        ),
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
                        style: const TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // Actions: Cancel & Create / Save
                    Wrap(
                      alignment: WrapAlignment.end,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: (_isSaving || !isFormValid) ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primarySoft,
                            foregroundColor: AppColors.ink,
                            disabledBackgroundColor: AppColors.surfaceMuted,
                            disabledForegroundColor: AppColors.textTertiary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                              side: BorderSide(
                                color: isFormValid ? AppColors.primary : Colors.transparent,
                              ),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                                )
                              : Text(
                                  isEdit ? 'Save Changes' : 'Create Cohort',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
