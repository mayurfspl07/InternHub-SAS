import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/attendance_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';

class AdminAttendanceOverrideModal extends ConsumerStatefulWidget {
  const AdminAttendanceOverrideModal({super.key});

  @override
  ConsumerState<AdminAttendanceOverrideModal> createState() => _AdminAttendanceOverrideModalState();
}

class _AdminAttendanceOverrideModalState extends ConsumerState<AdminAttendanceOverrideModal> {
  String? _selectedUserId;
  AttendanceStatus _overrideStatus = AttendanceStatus.present;
  final _reasonController = TextEditingController(text: 'Medical excuse submitted and approved.');
  bool _isLoading = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_selectedUserId == null || _reasonController.text.trim().isEmpty) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      await ApiClient().post('/api/attendance/manual', body: {
        'user_id': _selectedUserId,
        'date': now.toIso8601String().substring(0, 10),
        'check_in': DateTime(now.year, now.month, now.day, 9, 0).toIso8601String(),
        'check_out': DateTime(now.year, now.month, now.day, 17, 0).toIso8601String(),
        'status_override': _overrideStatus.toApiValue(),
        'reason': _reasonController.text.trim(),
      });

      if (mounted) {
        Navigator.pop(context);
        ref.read(appStateProvider.notifier).fetchAttendance();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance override recorded successfully!'), backgroundColor: AppColors.success),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(appStateProvider);
    final interns = state.allUsers.where((u) => u.role == UserRole.intern).toList();

    if (_selectedUserId == null && interns.isNotEmpty) {
      _selectedUserId = interns.first.id;
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Admin Attendance Manual Record 🛡️',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Manually adjust or excuse an attendance check-in for an intern.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 20),

          // Intern Dropdown
          Text(
            'Select Intern',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedUserId,
                isExpanded: true,
                dropdownColor: isDark ? AppColors.surfaceDark : Colors.white,
                items: interns
                    .map((i) => DropdownMenuItem(
                          value: i.id,
                          child: Text(
                            '${i.name} (${i.department ?? 'Engineering'})',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedUserId = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Status Dropdown
          Text(
            'Status Override',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AttendanceStatus>(
                value: _overrideStatus,
                isExpanded: true,
                dropdownColor: isDark ? AppColors.surfaceDark : Colors.white,
                items: AttendanceStatus.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s.toApiValue().toUpperCase(),
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                        ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _overrideStatus = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Reason Field
          CustomTextField(
            label: 'Audit Justification / Reason',
            controller: _reasonController,
            maxLines: 2,
          ),
          const SizedBox(height: 24),

          CustomButton(
            text: 'Save Attendance Override',
            isLoading: _isLoading,
            onPressed: _handleSave,
          ),
        ],
      ),
    );
  }
}
