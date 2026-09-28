import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/attendance_model.dart';
import '../../shared/models/user_model.dart';
import 'attendance_repository.dart';
import 'widgets/attendance_day_detail_modal.dart';
import 'widgets/staff_attendance_export_dialog.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../core/utils/formatters.dart';

class StudentAttendanceDetailScreen extends ConsumerStatefulWidget {
  final int userId;
  final AdminStudent? initialStudent;

  const StudentAttendanceDetailScreen({
    super.key,
    required this.userId,
    this.initialStudent,
  });

  @override
  ConsumerState<StudentAttendanceDetailScreen> createState() => _StudentAttendanceDetailScreenState();
}

class _StudentAttendanceDetailScreenState extends ConsumerState<StudentAttendanceDetailScreen> {
  final AttendanceRepository _repo = AttendanceRepository();

  bool _isLoading = true;
  AdminStudent? _student;
  List<AttendanceRecord> _records = [];
  List<MonthlySummary> _monthlySummaries = [];
  AttendanceTotals? _totals;

  int _page = 1;
  final int _pageSize = 31;
  int _totalPages = 1;
  int _totalRecords = 0;

  String? _loadError;
  DateTime? _filterFrom;
  DateTime? _filterTo;
  String _filterStatus = 'All';

  @override
  void initState() {
    super.initState();
    _student = widget.initialStudent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRoleGuardAndLoad();
    });
  }

  void _checkRoleGuardAndLoad() {
    final user = ref.read(appStateProvider).currentUser;
    // Role guard: if intern, redirect back to /attendance
    if (user.role == UserRole.intern) {
      Navigator.pop(context);
      return;
    }
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final user = ref.read(appStateProvider).currentUser;
    final isMentor = user.role == UserRole.mentor;

    final fromStr = _filterFrom != null ? DateFormat('yyyy-MM-dd').format(_filterFrom!) : null;
    final toStr = _filterTo != null ? DateFormat('yyyy-MM-dd').format(_filterTo!) : null;

    try {
      final res = await _repo.fetchStudentAttendanceDetail(
        isMentor: isMentor,
        userId: widget.userId,
        page: _page,
        pageSize: _pageSize,
        start: fromStr,
        end: toStr,
        status: _filterStatus != 'All' ? _filterStatus : null,
      );

      if (mounted) {
        setState(() {
          _student = res.student;
          _records = res.records;
          _monthlySummaries = res.monthlySummary;
          _totals = res.totals;
          _totalPages = res.totalPages;
          _totalRecords = res.total;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = apiErrorMessage(e);
        });
      }
    }
  }

  Future<void> _pickFilterDate({required bool isFrom}) async {
    final today = DateTime.now();
    final initial = isFrom ? (_filterFrom ?? _filterTo ?? today) : (_filterTo ?? today);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // From can't be after To and To can't be before From; nothing after today has attendance.
      firstDate: !isFrom && _filterFrom != null ? _filterFrom! : DateTime(2020),
      lastDate: isFrom && _filterTo != null ? _filterTo! : today,
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _filterFrom = picked;
        } else {
          _filterTo = picked;
        }
        _page = 1;
      });
      _fetchData();
    }
  }

  void _clearDateFilter() {
    setState(() {
      _filterFrom = null;
      _filterTo = null;
      _page = 1;
    });
    _fetchData();
  }

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == 'null') return '—';
    try {
      if (timeStr.contains('T')) {
        final dt = DateTime.parse(timeStr);
        return DateFormat('hh:mm a').format(dt);
      }
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final dt = DateTime(2026, 1, 1, h, m);
        return DateFormat('hh:mm a').format(dt);
      }
      return timeStr;
    } catch (_) {
      return timeStr;
    }
  }

  // Admin mutation dialogs
  Future<void> _showManualRecordDialog() => _openRecordDialog(null);

  Future<void> _showEditRecordDialog(AttendanceRecord record) => _openRecordDialog(record);

  /// Add a manual record (record == null) or edit one. Every change is audited with the reason.
  Future<void> _openRecordDialog(AttendanceRecord? record) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AttendanceRecordDialog(
        record: record,
        onSave: ({required date, checkIn, checkOut, clearCheckOut = false, statusOverride, required reason}) {
          if (record == null) {
            return _repo.createManualAttendance(
              userId: widget.userId,
              date: date,
              checkIn: checkIn ?? '',
              checkOut: checkOut,
              statusOverride: statusOverride,
              reason: reason,
            );
          }
          final wasOverridden = record.status == 'on_leave' || record.status == 'excused';
          return _repo.updateAttendanceRecord(
            id: record.id,
            checkIn: checkIn,
            checkOut: clearCheckOut ? 'clear' : checkOut,
            // '' asks the API to drop an existing override.
            statusOverride: statusOverride ?? (wasOverridden ? '' : null),
            reason: reason,
          );
        },
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(record == null ? 'Record added' : 'Record updated')),
      );
      _fetchData();
    }
  }

  Future<void> _showDeleteRecordDialog(AttendanceRecord record) async {
    final reasonController = TextEditingController();
    String? reasonError;
    bool deleting = false;
    final deleted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Delete record for ${formatDate(record.date)}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('The deletion is recorded in the audit log.', style: AppTypography.body),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Reason', errorText: reasonError),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: deleting ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
              onPressed: deleting
                  ? null
                  : () async {
                      if (reasonController.text.trim().isEmpty) {
                        setDlg(() => reasonError = 'Enter a reason for deleting this record');
                        return;
                      }
                      setDlg(() {
                        deleting = true;
                        reasonError = null;
                      });
                      try {
                        await _repo.deleteAttendanceRecord(id: record.id, reason: reasonController.text.trim());
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDlg(() {
                          deleting = false;
                          reasonError = apiErrorMessage(e);
                        });
                      }
                    },
              child: deleting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();
    if (deleted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Record deleted')));
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.read(appStateProvider).currentUser;
    final isMentor = user.role == UserRole.mentor;
    final isAdmin = user.role == UserRole.admin || user.role == UserRole.superadmin;
    final studentName = _student?.name ?? 'Student';

    final dateFormat = DateFormat('dd/MM/yyyy');

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(context, title: studentName),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _fetchData,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadError != null) ...[
                  LoadErrorView(
                    title: "Couldn't load attendance",
                    message: _loadError!,
                    onRetry: _fetchData,
                    compact: true,
                  ),
                  const SizedBox(height: 16),
                ] else ...[

                  // Card 1: Student Information (Clean 2-Column Grid)
                  _buildStudentInfoCard(),
                  const SizedBox(height: 20),

                  // Card 2: Attendance Overview (10 Stat Cards - Balanced 2-Column Grid)
                  Text(
                    'Attendance overview',
                    style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  const SizedBox(height: 10),
                  _buildOverviewGrid(),
                  const SizedBox(height: 20),

                  // Monthly Summary
                  _buildMonthlySummarySection(),

                  // Card 3: Attendance Records Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Attendance records',
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      if (isAdmin)
                        TextButton.icon(
                          onPressed: _showManualRecordDialog,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add record'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Filters Container: Row 1 = From & To; Row 2 = Status & Export
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.r20),
                      boxShadow: AppShadows.soft,
                    ),
                    child: Column(
                      children: [
                        // Row 1: FROM & TO
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'FROM',
                                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () => _pickFilterDate(isFrom: true),
                                    borderRadius: BorderRadius.circular(AppSpacing.r12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(AppSpacing.r12),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _filterFrom != null ? dateFormat.format(_filterFrom!) : 'dd/mm/yyyy',
                                            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: _filterFrom != null
                                                  ? AppColors.ink
                                                  : AppColors.textTertiary),
                                          ),
                                          Icon(
                                            Icons.calendar_today_outlined,
                                            size: 14,
                                            color: AppColors.textSecondary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TO',
                                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () => _pickFilterDate(isFrom: false),
                                    borderRadius: BorderRadius.circular(AppSpacing.r12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(AppSpacing.r12),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _filterTo != null ? dateFormat.format(_filterTo!) : 'dd/mm/yyyy',
                                            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: _filterTo != null
                                                  ? AppColors.ink
                                                  : AppColors.textTertiary),
                                          ),
                                          Icon(
                                            Icons.calendar_today_outlined,
                                            size: 14,
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
                        if (_filterFrom != null || _filterTo != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: _clearDateFilter, child: const Text('Clear dates')),
                          ),
                        const SizedBox(height: 10),

                        // Row 2: STATUS & EXPORT BUTTON
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Status',
                                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    height: 42,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(AppSpacing.r12),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _filterStatus,
                                        isExpanded: true,
                                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                                        dropdownColor: AppColors.surface,
                                        items: const [
                                          DropdownMenuItem(value: 'All', child: Text('All statuses')),
                                          DropdownMenuItem(value: 'present', child: Text('Present')),
                                          DropdownMenuItem(value: 'late', child: Text('Late')),
                                          DropdownMenuItem(value: 'half_day', child: Text('Half day')),
                                          DropdownMenuItem(value: 'absent', child: Text('Absent')),
                                          DropdownMenuItem(value: 'on_leave', child: Text('On leave')),
                                          DropdownMenuItem(value: 'excused', child: Text('Excused')),
                                        ],
                                        onChanged: (v) {
                                          if (v != null) {
                                            setState(() {
                                              _filterStatus = v;
                                              _page = 1;
                                            });
                                            _fetchData();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 42,
                                child: OutlinedButton.icon(
                                  onPressed: () => StaffAttendanceExportDialog.show(
                                    context,
                                    isMentor: isMentor,
                                    userId: widget.userId,
                                    studentName: studentName,
                                  ),
                                  icon: const Icon(Icons.description_outlined, size: 14),
                                  label: Text(
                                    'Export CSV',
                                    style: AppTypography.label.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.ink,
                                    side: BorderSide(
                                      color: AppColors.border,
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.r12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Records Table / List
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_records.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.r20),
                        boxShadow: AppShadows.soft,
                      ),
                      child: Center(
                        child: Text(
                          'No attendance records found.',
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    _buildRecordsList(isAdmin),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStudentInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student Information',
            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 14),
          // Clean 2-column balanced grid filling full width
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoItem('Name', _student?.name ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem('Department', _student?.department ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem('Job title', _student?.jobTitle ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem('Joining date', formatDate(_student?.joiningDate, fallback: '—')),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoItem('Email', _student?.email ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem('Phone', _student?.phone ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem(
                      'Status',
                      _student?.isActive == true ? 'Active' : 'Inactive',
                      isBadge: true,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoItem('Mentor', _student?.mentorName ?? '—'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, {bool isBadge = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5),
        ),
        const SizedBox(height: 3),
        if (isBadge)
          StatusChip.fromString(value)
        else
          Text(
            value,
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _buildOverviewGrid() {
    final totals = _totals;
    final pairs = [
      [('Present', totals?.present.toString() ?? '0'), ('Absent', totals?.absent.toString() ?? '0')],
      [('On leave', totals?.onLeave.toString() ?? '0'), ('Late', totals?.late.toString() ?? '0')],
      [('Half day', totals?.halfDay.toString() ?? '0'), ('Excused', totals?.excused.toString() ?? '0')],
      [('Total days', totals?.totalDays.toString() ?? '0'), ('Attended', totals?.attended.toString() ?? '0')],
      [
        ('Total hours', totals != null ? '${totals.totalHours.toStringAsFixed(2)}h' : '0.00h'),
        ('Attendance rate', totals != null ? '${totals.attendanceRate.toStringAsFixed(0)}%' : '0%'),
      ],
    ];

    return Column(
      children: pairs.map((pair) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: _buildStatCard(pair[0].$1, pair[0].$2)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard(pair[1].$1, pair[1].$2)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlySummarySection() {
    if (_monthlySummaries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly Summary',
          style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 10),
        ..._monthlySummaries.map((m) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              boxShadow: AppShadows.soft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatMonth(m.yearMonth),
                      style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    Text(
                      '${m.totalHours.toStringAsFixed(1)}h  •  ${m.attendanceRate.toStringAsFixed(0)}% rate',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryInk),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusChip.fromString('present', label: '${m.present} present'),
                    StatusChip.fromString('late', label: '${m.late} late'),
                    StatusChip.fromString('half_day', label: '${m.halfDay} half day'),
                    StatusChip.fromString('absent', label: '${m.absent} absent'),
                    StatusChip.fromString('on_leave', label: '${m.onLeave} on leave'),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildRecordsList(bool isAdmin) {
    return Column(
      children: [
        ..._records.map((r) {
          final dt = DateTime.tryParse(r.date) ?? DateTime.now();
          final formattedDate = DateFormat('EEE, d MMM yyyy').format(dt);
          final inStr = _formatTime(r.checkIn);
          final outStr = r.checkoutMissed ? 'Missed' : _formatTime(r.checkOut);
          final hours = r.hoursWorked != null ? '${r.hoursWorked!.toStringAsFixed(1)}h' : '—';

          return InkWell(
            onTap: () {
              AttendanceDayDetailModal.show(
                context,
                date: dt,
                record: r,
                status: r.status,
                actorId: r.userId,
              );
            },
            borderRadius: BorderRadius.circular(AppSpacing.r16),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.r16),
                boxShadow: AppShadows.soft,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formattedDate,
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$inStr - $outStr',
                          style: AppTypography.label.copyWith(color: r.checkoutMissed
                                ? AppColors.dangerInk
                                : AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  StatusChip.fromString(r.status),
                  const SizedBox(width: 10),
                  Text(
                    hours,
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  const SizedBox(width: 4),
                  // Tapping the row opens the day; admins get edit/delete here.
                  if (isAdmin)
                    PopupMenuButton<String>(
                      tooltip: 'Record actions',
                      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                      onSelected: (action) {
                        if (action == 'edit') {
                          _showEditRecordDialog(r);
                        } else if (action == 'delete') {
                          _showDeleteRecordDialog(r);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit record')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete record', style: AppTypography.body.copyWith(color: AppColors.dangerInk)),
                        ),
                      ],
                    )
                  else
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),

        PaginationBar(
          page: _page,
          totalPages: _totalPages,
          totalItems: _totalRecords,
          itemLabel: 'records',
          isLoading: _isLoading,
          onPageChanged: (p) {
            setState(() => _page = p);
            _fetchData();
          },
        ),
      ],
    );
  }
}

typedef _SaveRecord = Future<Object?> Function({
  required String date,
  String? checkIn,
  String? checkOut,
  bool clearCheckOut,
  String? statusOverride,
  required String reason,
});

/// Add or edit one attendance record with date/time pickers (the API takes "HH:MM").
class _AttendanceRecordDialog extends StatefulWidget {
  final AttendanceRecord? record;
  final _SaveRecord onSave;

  const _AttendanceRecordDialog({required this.record, required this.onSave});

  @override
  State<_AttendanceRecordDialog> createState() => _AttendanceRecordDialogState();
}

class _AttendanceRecordDialogState extends State<_AttendanceRecordDialog> {
  late DateTime _date;
  TimeOfDay? _checkIn;
  TimeOfDay? _checkOut;
  bool _clearCheckOut = false;
  String? _statusOverride;
  final _reason = TextEditingController();
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _date = DateTime.tryParse(r?.date ?? '') ?? DateTime.now();
    _checkIn = _parse(r?.checkIn);
    _checkOut = r?.checkoutMissed == true ? null : _parse(r?.checkOut);
    if (r != null && (r.status == 'on_leave' || r.status == 'excused')) _statusOverride = r.status;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  static TimeOfDay? _parse(String? value) {
    final d = parseDateTime(value);
    return d == null ? null : TimeOfDay(hour: d.hour, minute: d.minute);
  }

  static String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime(bool checkIn) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (checkIn ? _checkIn : _checkOut) ?? TimeOfDay(hour: checkIn ? 9 : 18, minute: 0),
    );
    if (picked != null) {
      setState(() {
        if (checkIn) {
          _checkIn = picked;
        } else {
          _checkOut = picked;
          _clearCheckOut = false;
        }
      });
    }
  }

  Future<void> _save() async {
    String? problem;
    if (!_isEdit && _checkIn == null && _statusOverride == null) problem = 'Pick the check-in time';
    if (_checkIn != null && _checkOut != null && !_clearCheckOut) {
      final inMin = _checkIn!.hour * 60 + _checkIn!.minute;
      final outMin = _checkOut!.hour * 60 + _checkOut!.minute;
      if (outMin <= inMin) problem = 'Check-out must be after check-in';
    }
    if (_reason.text.trim().isEmpty) problem ??= 'Enter a reason for this change';
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        date: DateFormat('yyyy-MM-dd').format(_date),
        checkIn: _checkIn == null ? null : _hhmm(_checkIn!),
        checkOut: _checkOut == null || _clearCheckOut ? null : _hhmm(_checkOut!),
        clearCheckOut: _clearCheckOut,
        statusOverride: _statusOverride,
        reason: _reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  Widget _timeRow(String label, TimeOfDay? value, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: AppTypography.body.copyWith(color: AppColors.ink)),
      trailing: OutlinedButton(
        onPressed: _saving ? null : onTap,
        child: Text(value == null ? 'Set' : value.format(context)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(_isEdit ? 'Edit record · ${formatDate(_date)}' : 'Add attendance record'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isEdit)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date', style: AppTypography.body.copyWith(color: AppColors.ink)),
                trailing: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                  child: Text(formatDate(_date)),
                ),
              ),
            _timeRow('Check-in', _checkIn, () => _pickTime(true)),
            _timeRow('Check-out', _clearCheckOut ? null : _checkOut, () => _pickTime(false)),
            if (_isEdit && widget.record?.checkOut != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _clearCheckOut,
                onChanged: _saving ? null : (v) => setState(() => _clearCheckOut = v ?? false),
                title: Text('Clear check-out', style: AppTypography.body.copyWith(color: AppColors.ink)),
              ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String?>(
              initialValue: _statusOverride,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('From check-in times')),
                DropdownMenuItem(value: 'on_leave', child: Text('On leave')),
                DropdownMenuItem(value: 'excused', child: Text('Excused')),
              ],
              onChanged: _saving ? null : (v) => setState(() => _statusOverride = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? 'Save changes' : 'Add record'),
        ),
      ],
    );
  }
}
