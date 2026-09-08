import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/horizontal_date_strip.dart';
import '../../shared/widgets/status_chip.dart';
import 'checkin_checkout_screen.dart';
import 'attendance_details_modal.dart';
import 'admin_attendance_override_modal.dart';

class AttendanceHomeScreen extends ConsumerStatefulWidget {
  const AttendanceHomeScreen({super.key});

  @override
  ConsumerState<AttendanceHomeScreen> createState() => _AttendanceHomeScreenState();
}

class _AttendanceHomeScreenState extends ConsumerState<AttendanceHomeScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isExporting = false;

  Future<void> _exportCsv(UserRole role) async {
    setState(() => _isExporting = true);
    try {
      String endpoint;
      String fileName;
      if (role == UserRole.mentor) {
        endpoint = '/api/mentor/attendance/export.csv';
        fileName = 'mentor_attendance_report.csv';
      } else if (role == UserRole.admin || role == UserRole.superadmin) {
        endpoint = '/api/admin/attendance/export.csv';
        fileName = 'admin_attendance_report.csv';
      } else {
        endpoint = '/api/attendance/export/my.csv';
        fileName = 'my_attendance.csv';
      }
      await FileExportService.downloadAndShare(endpoint: endpoint, defaultFileName: fileName);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to download CSV export. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final records = state.attendanceRecords;
    final user = state.currentUser;
    final isStaff = user.role == UserRole.admin || user.role == UserRole.mentor;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchAttendance(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isStaff ? 'Staff Attendance 🛡️' : 'My Attendance 📍',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isStaff ? 'Team attendance & audit records' : 'Biometric verification & history',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (_isExporting)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.file_download_outlined, color: AppColors.primary),
                              tooltip: 'Export CSV',
                              onPressed: () => _exportCsv(user.role),
                            ),
                          if (!isStaff)
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const CheckinCheckoutScreen()),
                                );
                              },
                              icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                              label: Text(state.todayAttendance != null ? 'Check Out' : 'Check In'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rPill)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                            )
                          else if (user.role == UserRole.admin)
                            ElevatedButton.icon(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                                  ),
                                  builder: (_) => const AdminAttendanceOverrideModal(),
                                );
                              },
                              icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                              label: const Text('Add / Edit'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rPill)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Calendar Strip
                HorizontalDateStrip(
                  selectedDate: _selectedDate,
                  onDateSelected: (date) {
                    setState(() => _selectedDate = date);
                  },
                ),
                const SizedBox(height: 16),

                // Metric Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('🔥 Streak', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 6),
                              Text(
                                '${user.attendanceStreak} Days',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('⏱️ Total Records', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 6),
                              Text(
                                '${records.length} Logs',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Attendance List Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                  child: Text(
                    'Attendance Logs (${DateFormat('MMM d, yyyy').format(_selectedDate)})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                records.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            children: [
                              const Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey),
                              const SizedBox(height: 10),
                              Text(
                                'No attendance records logged',
                                style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final record = records[index];
                          return GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                                ),
                                builder: (_) => AttendanceDetailsModal(record: record),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.fingerprint_rounded, color: AppColors.primary, size: 24),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isStaff ? record.userName : record.locationAddress,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'In: ${DateFormat('hh:mm a').format(record.checkInTime)}${record.checkOutTime != null ? ' • Out: ${DateFormat('hh:mm a').format(record.checkOutTime!)}' : ''}',
                                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : AppColors.textSecondaryLight),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusChip(
                                    label: record.status.toApiValue().toUpperCase(),
                                    statusType: record.status.name == 'present' ? StatusType.success : StatusType.warning,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
