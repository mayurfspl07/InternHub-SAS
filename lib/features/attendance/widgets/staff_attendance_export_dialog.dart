import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../attendance_repository.dart';
import '../../../core/constants/app_typography.dart';

class StaffAttendanceExportDialog extends StatefulWidget {
  final bool isMentor;
  final int? userId;
  final String? studentName;

  const StaffAttendanceExportDialog({
    super.key,
    required this.isMentor,
    this.userId,
    this.studentName,
  });

  static Future<void> show(
    BuildContext context, {
    required bool isMentor,
    int? userId,
    String? studentName,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => StaffAttendanceExportDialog(
        isMentor: isMentor,
        userId: userId,
        studentName: studentName,
      ),
    );
  }

  @override
  State<StaffAttendanceExportDialog> createState() => _StaffAttendanceExportDialogState();
}

class _StaffAttendanceExportDialogState extends State<StaffAttendanceExportDialog> {
  late DateTime _fromDate;
  late DateTime _toDate;
  String _selectedStatus = 'All';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _toDate = now;
    _fromDate = now.subtract(const Duration(days: 30));
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
        _errorMessage = null;
      });
    }
  }

  Future<void> _handleExport() async {
    if (_fromDate.isAfter(_toDate)) {
      setState(() {
        _errorMessage = '"From" date must be earlier than or equal to "To" date.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final fromStr = DateFormat('yyyy-MM-dd').format(_fromDate);
    final toStr = DateFormat('yyyy-MM-dd').format(_toDate);

    try {
      final bytes = await AttendanceRepository().exportStaffAttendance(
        isMentor: widget.isMentor,
        fromDate: fromStr,
        toDate: toStr,
        userId: widget.userId,
        status: _selectedStatus != 'All' ? _selectedStatus : null,
      );

      final dir = await getTemporaryDirectory();
      final prefix = widget.studentName != null
          ? 'attendance_${widget.studentName!.replaceAll(' ', '_')}'
          : 'attendance_report';
      final fileName = '${prefix}_${fromStr}_to_$toStr.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        Navigator.pop(context);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Attendance Export ($fromStr to $toStr)',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to export attendance. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        side: BorderSide(
          color: AppColors.border,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Export attendance',
                      style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.studentName != null
                    ? '${widget.studentName} · saved as a CSV file'
                    : 'Saved as a CSV file you can open in Excel or Sheets.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'From',
                          style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _pickDate(isFrom: true),
                          borderRadius: BorderRadius.circular(AppSpacing.r12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppSpacing.r12),
                              border: Border.all(
                                color: AppColors.border,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  dateFormat.format(_fromDate),
                                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                                ),
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
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
                        Text(
                          'To',
                          style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _pickDate(isFrom: false),
                          borderRadius: BorderRadius.circular(AppSpacing.r12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(AppSpacing.r12),
                              border: Border.all(
                                color: AppColors.border,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  dateFormat.format(_toDate),
                                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                                ),
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Status Dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status',
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.r12),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedStatus,
                        isExpanded: true,
                        dropdownColor: AppColors.surface,
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('All statuses')),
                          DropdownMenuItem(value: 'present', child: Text('Present')),
                          DropdownMenuItem(value: 'late', child: Text('Late')),
                          DropdownMenuItem(value: 'half_day', child: Text('Half-Day')),
                          DropdownMenuItem(value: 'absent', child: Text('Absent')),
                          DropdownMenuItem(value: 'on_leave', child: Text('On Leave')),
                          DropdownMenuItem(value: 'excused', child: Text('Excused')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedStatus = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: AppTypography.caption.copyWith(color: AppColors.danger),
                ),
              ],
              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        foregroundColor: AppColors.ink,
                        side: BorderSide(
                          color: AppColors.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.rPill),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleExport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.rPill),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                              ),
                            )
                          : const Text(
                              'Export (CSV)',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
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
