import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/leave_model.dart';
import '../leave_repository.dart';

class ApplyLeaveDialog extends StatefulWidget {
  final LeaveBalance balance;
  final VoidCallback onSuccess;

  const ApplyLeaveDialog({
    super.key,
    required this.balance,
    required this.onSuccess,
  });

  static Future<void> show(BuildContext context, {required LeaveBalance balance, required VoidCallback onSuccess}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApplyLeaveDialog(balance: balance, onSuccess: onSuccess),
    );
  }

  @override
  State<ApplyLeaveDialog> createState() => _ApplyLeaveDialogState();
}

class _ApplyLeaveDialogState extends State<ApplyLeaveDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  final _imagePicker = ImagePicker();

  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedType = 'casual'; // casual | sick | earned | comp
  File? _attachmentFile;
  String? _attachmentName;
  int? _attachmentSizeBytes;
  String? _attachmentError;

  bool _isSubmitting = false;
  String? _serverError;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  int get _requestedDays {
    if (_startDate == null || _endDate == null) return 0;
    if (_endDate!.isBefore(_startDate!)) return 0;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _startDate ?? today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = _startDate ?? today;
    final initial = _endDate ?? first;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: today.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  Future<void> _pickAttachment() async {
    setState(() => _attachmentError = null);
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (photo != null) {
        final file = File(photo.path);
        final size = await file.length();
        if (size > 2 * 1024 * 1024) {
          setState(() {
            _attachmentError = 'File size exceeds 2MB limit (selected: ${(size / (1024 * 1024)).toStringAsFixed(1)}MB)';
            _attachmentFile = null;
            _attachmentName = null;
            _attachmentSizeBytes = null;
          });
          return;
        }

        setState(() {
          _attachmentFile = file;
          _attachmentName = photo.name;
          _attachmentSizeBytes = size;
          _attachmentError = null;
        });
      }
    } catch (e) {
      setState(() {
        _attachmentError = 'Failed to select attachment: $e';
      });
    }
  }

  void _removeAttachment() {
    setState(() {
      _attachmentFile = null;
      _attachmentName = null;
      _attachmentSizeBytes = null;
      _attachmentError = null;
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both start and end dates.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date must be on or after start date.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _serverError = null;
    });

    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate!);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate!);
      final reasonStr = _reasonController.text.trim();

      await LeaveRepository().createRequest(
        startDate: startStr,
        endDate: endStr,
        reason: reasonStr,
        leaveType: _selectedType,
        attachment: _attachmentFile,
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Leave request submitted successfully!'),
            backgroundColor: AppColors.success,
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
    final remainingQuota = widget.balance.remaining;
    final requested = _requestedDays;

    return Dialog(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Apply for Leave',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Submit a leave request for mentor review and approval.',
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
                const SizedBox(height: 16),

                // Available Quota Ribbon
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF28233A) : const Color(0xFFEDE9FE),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? AppColors.primary.withValues(alpha: 0.3) : const Color(0xFFDDD6FE),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          requested > 0
                              ? 'Available Quota: $remainingQuota days • Requesting $requested day(s)'
                              : 'Available Quota: $remainingQuota days',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF4C1D95),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Dates: Start Date & End Date Row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('START DATE *', isDark),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _pickStartDate,
                            child: _buildDateDisplayBox(
                              date: _startDate,
                              placeholder: 'dd/mm/yyyy',
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('END DATE *', isDark),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _pickEndDate,
                            child: _buildDateDisplayBox(
                              date: _endDate,
                              placeholder: 'dd/mm/yyyy',
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Leave Type Dropdown
                _buildFieldLabel('LEAVE TYPE *', isDark),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.cardDark : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedType,
                      isExpanded: true,
                      dropdownColor: isDark ? AppColors.surfaceDark : Colors.white,
                      items: const [
                        DropdownMenuItem(value: 'casual', child: Text('Casual')),
                        DropdownMenuItem(value: 'sick', child: Text('Sick')),
                        DropdownMenuItem(value: 'earned', child: Text('Earned')),
                        DropdownMenuItem(value: 'comp', child: Text('Comp Off')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedType = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Reason for Leave Textarea
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildFieldLabel('REASON FOR LEAVE *', isDark),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _reasonController,
                      builder: (context, value, _) {
                        return Text(
                          '${value.text.length}/300',
                          style: TextStyle(
                            fontSize: 11,
                            color: value.text.length > 300
                                ? AppColors.danger
                                : (isDark ? Colors.white38 : AppColors.textTertiaryLight),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 3,
                  maxLength: 300,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Briefly describe why you are requesting leave...',
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
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please provide a reason for your leave';
                    }
                    if (val.trim().length > 300) {
                      return 'Reason cannot exceed 300 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Supporting Attachment
                _buildFieldLabel('SUPPORTING ATTACHMENT (OPTIONAL — MAX 2MB)', isDark),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickAttachment,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.cardDark : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _attachmentError != null
                            ? AppColors.danger
                            : (isDark ? AppColors.borderDark : const Color(0xFFD1D5DB)),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: _attachmentFile == null
                        ? Column(
                            children: [
                              Icon(
                                Icons.file_upload_outlined,
                                size: 24,
                                color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Click to upload supporting file',
                                style: GoogleFonts.outfit(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'PDF, PNG, JPG, or DOC up to 2MB (e.g. medical certificate)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? Colors.white38 : AppColors.textTertiaryLight,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.attach_file_rounded, color: AppColors.primary, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _attachmentName ?? 'Selected File',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (_attachmentSizeBytes != null)
                                      Text(
                                        '${(_attachmentSizeBytes! / 1024).toStringAsFixed(1)} KB',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20),
                                onPressed: _removeAttachment,
                              ),
                            ],
                          ),
                  ),
                ),
                if (_attachmentError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _attachmentError!,
                    style: const TextStyle(color: AppColors.danger, fontSize: 11.5),
                  ),
                ],

                // Server error if any
                if (_serverError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _serverError!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Bottom Buttons (Cancel & Submit)
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
                        backgroundColor: AppColors.cardYellow,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _isSubmitting ? null : _handleSubmit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Row(
                              children: [
                                const Icon(Icons.add_rounded, size: 18, color: Colors.black),
                                const SizedBox(width: 4),
                                Text(
                                  'Submit Leave Request',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, bool isDark) {
    return Text(
      label,
      style: GoogleFonts.outfit(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: isDark ? Colors.white70 : const Color(0xFF4B5563),
      ),
    );
  }

  Widget _buildDateDisplayBox({
    required DateTime? date,
    required String placeholder,
    required bool isDark,
  }) {
    final text = date != null ? DateFormat('dd/MM/yyyy').format(date) : placeholder;
    final isSelected = date != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? (isDark ? Colors.white : AppColors.textPrimaryLight)
                  : (isDark ? Colors.white30 : AppColors.textTertiaryLight),
            ),
          ),
          Icon(
            Icons.calendar_month_outlined,
            size: 18,
            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
          ),
        ],
      ),
    );
  }
}
