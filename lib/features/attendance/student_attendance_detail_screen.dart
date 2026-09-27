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
    setState(() => _isLoading = true);
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
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFilterDate({required bool isFrom}) async {
    final initial = isFrom ? (_filterFrom ?? DateTime.now()) : (_filterTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
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

  Color _getStatusBg(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return AppColors.successSoft;
      case 'late':
        return AppColors.warningSoft;
      case 'half_day':
      case 'halfday':
        return AppColors.infoSoft;
      case 'absent':
        return AppColors.dangerSoft;
      case 'on_leave':
      case 'leave':
        return AppColors.lavender;
      case 'excused':
        return AppColors.successSoft;
      default:
        return AppColors.surfaceMuted;
    }
  }

  Color _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return AppColors.successInk;
      case 'late':
        return AppColors.warningInk;
      case 'half_day':
      case 'halfday':
        return AppColors.infoInk;
      case 'absent':
        return AppColors.dangerInk;
      case 'on_leave':
      case 'leave':
        return AppColors.lavenderInk;
      case 'excused':
        return AppColors.successInk;
      default:
        return AppColors.textSecondary;
    }
  }

  // Admin mutation dialogs
  Future<void> _showManualRecordDialog() async {
    final dateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    // Times start empty: the admin enters what actually happened (HH:MM).
    final checkInController = TextEditingController();
    final checkOutController = TextEditingController();
    final reasonController = TextEditingController();
    String? statusOverride;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r24)),
            title: const Text('Add Manual Attendance Record', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: dateController,
                    decoration: const InputDecoration(labelText: 'Date (YYYY-MM-DD)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: checkInController,
                    decoration: const InputDecoration(labelText: 'Check In (HH:MM or ISO)'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: checkOutController,
                    decoration: const InputDecoration(labelText: 'Check Out (optional)'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: statusOverride,
                    decoration: const InputDecoration(labelText: 'Status Override (optional)'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Auto / Normal')),
                      DropdownMenuItem(value: 'on_leave', child: Text('On Leave')),
                      DropdownMenuItem(value: 'excused', child: Text('Excused')),
                    ],
                    onChanged: (v) => setDlgState(() => statusOverride = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(labelText: 'Reason (Required)*'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (reasonController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Reason is required.')),
                    );
                    return;
                  }
                  try {
                    await _repo.createManualAttendance(
                      userId: widget.userId,
                      date: dateController.text.trim(),
                      checkIn: checkInController.text.trim(),
                      checkOut: checkOutController.text.trim().isNotEmpty ? checkOutController.text.trim() : null,
                      statusOverride: statusOverride,
                      reason: reasonController.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    _fetchData();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: const Text('Add Record'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditRecordDialog(AttendanceRecord record) async {
    final checkInController = TextEditingController(text: record.checkIn ?? '');
    final checkOutController = TextEditingController(text: record.checkOut ?? '');
    final reasonController = TextEditingController();
    String? statusOverride = (record.status == 'on_leave' || record.status == 'excused') ? record.status : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r24)),
            title: Text('Edit Record (${record.date})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: checkInController,
                    decoration: const InputDecoration(labelText: 'Check In Time'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: checkOutController,
                    decoration: const InputDecoration(labelText: 'Check Out Time ("clear" to remove)'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: statusOverride,
                    decoration: const InputDecoration(labelText: 'Status Override'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('None / Auto')),
                      DropdownMenuItem(value: 'on_leave', child: Text('On Leave')),
                      DropdownMenuItem(value: 'excused', child: Text('Excused')),
                    ],
                    onChanged: (v) => setDlgState(() => statusOverride = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(labelText: 'Reason for Edit (Required)*'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (reasonController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Reason is required.')),
                    );
                    return;
                  }
                  try {
                    await _repo.updateAttendanceRecord(
                      id: record.id,
                      checkIn: checkInController.text.trim().isNotEmpty ? checkInController.text.trim() : null,
                      checkOut: checkOutController.text.trim().isNotEmpty ? checkOutController.text.trim() : null,
                      statusOverride: statusOverride,
                      reason: reasonController.text.trim(),
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    _fetchData();
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDeleteRecordDialog(AttendanceRecord record) async {
    final reasonController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Record (${record.date})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to delete this attendance record? This action will be audited.'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason for deletion (Required)*'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Reason is required.')),
                );
                return;
              }
              try {
                await _repo.deleteAttendanceRecord(id: record.id, reason: reasonController.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                _fetchData();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchData,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeader(
                  title: studentName,
                  subtitle: 'Attendance summary and records',
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),

                // Card 1: Student Information (Clean 2-Column Grid)
                _buildStudentInfoCard(),
                const SizedBox(height: 20),

                // Card 2: Attendance Overview (10 Stat Cards - Balanced 2-Column Grid)
                Text(
                  'Attendance Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
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
                      'Attendance Records',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (isAdmin)
                      TextButton.icon(
                        onPressed: _showManualRecordDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add Manual', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Filters Container: Row 1 = From & To; Row 2 = Status & Export
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
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
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _filterFrom != null
                                                ? AppColors.ink
                                                : AppColors.textTertiary,
                                          ),
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
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
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: _filterTo != null
                                                ? AppColors.ink
                                                : AppColors.textTertiary,
                                          ),
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
                                  'STATUS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 0.5,
                                  ),
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
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                      dropdownColor: Colors.white,
                                      items: const [
                                        DropdownMenuItem(value: 'All', child: Text('All statuses')),
                                        DropdownMenuItem(value: 'present', child: Text('Present')),
                                        DropdownMenuItem(value: 'late', child: Text('Late')),
                                        DropdownMenuItem(value: 'half_day', child: Text('Half-Day')),
                                        DropdownMenuItem(value: 'absent', child: Text('Absent')),
                                        DropdownMenuItem(value: 'on_leave', child: Text('On Leave')),
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
                                label: const Text(
                                  'Export (XLSX)',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppSpacing.r20),
                      boxShadow: AppShadows.soft,
                    ),
                    child: Center(
                      child: Text(
                        'No attendance records found.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  _buildRecordsList(isAdmin),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student Information',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
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
                    _buildInfoItem('NAME', _student?.name ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem('DEPARTMENT', _student?.department ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem('JOB TITLE', _student?.jobTitle ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem('JOINING DATE', _student?.joiningDate ?? '—'),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoItem('EMAIL', _student?.email ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem('PHONE', _student?.phone ?? '—'),
                    const SizedBox(height: 12),
                    _buildInfoItem(
                      'STATUS',
                      _student?.isActive == true ? 'Active' : 'Inactive',
                      isBadge: true,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoItem('MENTOR', _student?.mentorName ?? '—'),
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
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        if (isBadge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.successSoft,
              borderRadius: BorderRadius.circular(AppSpacing.rPill),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.successInk,
              ),
            ),
          )
        else
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _buildOverviewGrid() {
    final totals = _totals;
    final pairs = [
      [('PRESENT', totals?.present.toString() ?? '0'), ('ABSENT', totals?.absent.toString() ?? '0')],
      [('ON LEAVE', totals?.onLeave.toString() ?? '0'), ('LATE', totals?.late.toString() ?? '0')],
      [('HALF DAY', totals?.halfDay.toString() ?? '0'), ('EXCUSED', totals?.excused.toString() ?? '0')],
      [('TOTAL DAYS', totals?.totalDays.toString() ?? '0'), ('ATTENDED', totals?.attended.toString() ?? '0')],
      [
        ('TOTAL HOURS', totals != null ? '${totals.totalHours.toStringAsFixed(2)}h' : '0.00h'),
        ('ATTENDANCE RATE', totals != null ? '${totals.attendanceRate.toStringAsFixed(0)}%' : '0%'),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
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
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        ..._monthlySummaries.map((m) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
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
                      m.yearMonth,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      '${m.totalHours.toStringAsFixed(1)}h  •  ${m.attendanceRate.toStringAsFixed(0)}% rate',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildMiniBadge('Present', m.present, AppColors.success),
                    _buildMiniBadge('Late', m.late, AppColors.warning),
                    _buildMiniBadge('Half-Day', m.halfDay, AppColors.info),
                    _buildMiniBadge('Absent', m.absent, AppColors.danger),
                    _buildMiniBadge('Leave', m.onLeave, AppColors.lavenderInk),
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

  Widget _buildMiniBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildRecordsList(bool isAdmin) {
    return Column(
      children: [
        ..._records.map((r) {
          final dt = DateTime.tryParse(r.date) ?? DateTime.now();
          final formattedDate = DateFormat('EEE, MMM d, yyyy').format(dt);
          final inStr = _formatTime(r.checkIn);
          final outStr = r.checkoutMissed ? 'Missed' : _formatTime(r.checkOut);
          final hours = r.hoursWorked != null ? '${r.hoursWorked!.toStringAsFixed(1)}h' : '—';
          final bg = _getStatusBg(r.status);
          final fg = _getStatusText(r.status);

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
                color: Colors.white,
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
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$inStr - $outStr',
                          style: TextStyle(
                            fontSize: 11,
                            color: r.checkoutMissed
                                ? AppColors.danger
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                    child: Text(
                      r.status.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hours,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (action) {
                      if (action == 'view') {
                        AttendanceDayDetailModal.show(
                          context,
                          date: dt,
                          record: r,
                          status: r.status,
                          actorId: r.userId,
                        );
                      } else if (action == 'edit') {
                        _showEditRecordDialog(r);
                      } else if (action == 'delete') {
                        _showDeleteRecordDialog(r);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Text('View Details'),
                      ),
                      if (isAdmin) ...[
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit Record'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete Record', style: TextStyle(color: AppColors.danger)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),

        // Pagination Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Page $_page of $_totalPages ($_totalRecords records)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              children: [
                OutlinedButton(
                  onPressed: _page > 1
                      ? () {
                          setState(() => _page--);
                          _fetchData();
                        }
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r8)),
                  ),
                  child: const Text('Previous', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.r8),
                  ),
                  child: Text(
                    '$_page',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _page < _totalPages
                      ? () {
                          setState(() => _page++);
                          _fetchData();
                        }
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r8)),
                  ),
                  child: const Text('Next', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
