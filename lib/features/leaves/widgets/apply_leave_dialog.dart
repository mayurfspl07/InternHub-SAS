import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/document_picker.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/leave_model.dart';
import '../leave_repository.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

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

  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedType = 'casual'; // casual | sick | earned | comp
  File? _attachmentFile;
  String? _attachmentName;
  int? _attachmentSizeBytes;
  String? _attachmentError;

  bool _isSubmitting = false;
  String? _serverError;
  String? _dateError;

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
      final doc = await pickDocument();
      if (doc == null) return;
      setState(() {
        _attachmentFile = doc.file;
        _attachmentName = doc.name;
        _attachmentSizeBytes = doc.sizeBytes;
      });
    } on DocumentPickException catch (e) {
      setState(() => _attachmentError = e.message);
    } catch (_) {
      setState(() => _attachmentError = "Couldn't open that file. Try another one.");
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
      setState(() => _dateError = 'Pick a start and an end date.');
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _dateError = 'The end date must be on or after the start date.');
      return;
    }
    setState(() => _dateError = null);

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
            content: Text('Leave request sent for approval.'),
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
          _serverError = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remainingQuota = widget.balance.remaining;
    final requested = _requestedDays;

    final overBalance = requested > 0 && requested > remainingQuota;
    final daysLeft = remainingQuota % 1 == 0 ? '${remainingQuota.toInt()}' : '$remainingQuota';

    return Dialog(
      backgroundColor: AppColors.surface,
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
                            style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Submit a leave request for mentor review and approval.',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      tooltip: 'Close',
                      color: AppColors.textSecondary,
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Available Quota Ribbon
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: overBalance ? AppColors.dangerSoft : AppColors.lavender,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        overBalance ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                        size: 18,
                        color: overBalance ? AppColors.dangerInk : AppColors.lavenderInk,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          overBalance
                              ? 'You have $daysLeft days left but are asking for $requested.'
                              : requested > 0
                                  ? '$daysLeft days available · requesting ${plural(requested, 'day')}'
                                  : '$daysLeft days available',
                          style: AppTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: overBalance ? AppColors.dangerInk : AppColors.lavenderInk,
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
                          _buildFieldLabel('Start date'),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _pickStartDate,
                            child: _buildDateDisplayBox(
                              date: _startDate,
                              placeholder: 'dd/mm/yyyy',
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
                          _buildFieldLabel('End date'),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _pickEndDate,
                            child: _buildDateDisplayBox(
                              date: _endDate,
                              placeholder: 'dd/mm/yyyy',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Leave Type Dropdown
                _buildFieldLabel('Leave type'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedType,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
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
                    _buildFieldLabel('Reason'),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _reasonController,
                      builder: (context, value, _) {
                        return Text(
                          '${value.text.length}/300',
                          style: AppTypography.label.copyWith(color: value.text.length > 300
                                ? AppColors.danger
                                : AppColors.textTertiary),
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
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.caption.copyWith(color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Briefly describe why you need the leave',
                    hintStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.border),
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
                _buildFieldLabel('Supporting file (optional)'),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _pickAttachment,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _attachmentError != null
                            ? AppColors.danger
                            : AppColors.border,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: _attachmentFile == null
                        ? Column(
                            children: [
                              Icon(
                                Icons.file_upload_outlined,
                                size: 24,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Tap to attach a supporting file',
                                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'PDF, Word or image, up to 10 MB (e.g. a medical certificate)',
                                style: AppTypography.label.copyWith(color: AppColors.textTertiary),
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
                                child: const Icon(Icons.attach_file_rounded, color: AppColors.primaryInk, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _attachmentName ?? 'Selected File',
                                      style: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (_attachmentSizeBytes != null)
                                      Text(
                                        PickedDocument(file: _attachmentFile!, name: '', sizeBytes: _attachmentSizeBytes!).sizeLabel,
                                        style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20),
                                tooltip: 'Remove file',
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
                    style: AppTypography.label.copyWith(color: AppColors.dangerInk),
                  ),
                ],

                if (_dateError != null) ...[
                  const SizedBox(height: 12),
                  Text(_dateError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
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
                      style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
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
                        side: BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      child: Text('Cancel', style: AppTypography.bodyStrong),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.ink,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: _isSubmitting || overBalance ? null : _handleSubmit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                            )
                          : Text(
                              'Send request',
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyStrong.copyWith(color: AppColors.ink),
                            ),
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

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppColors.textSecondary),
    );
  }

  Widget _buildDateDisplayBox({
    required DateTime? date,
    required String placeholder,
  }) {
    final text = date != null ? DateFormat('dd/MM/yyyy').format(date) : placeholder;
    final isSelected = date != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            text,
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: isSelected
                  ? AppColors.ink
                  : AppColors.textTertiary),
          ),
          Icon(
            Icons.calendar_month_outlined,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
