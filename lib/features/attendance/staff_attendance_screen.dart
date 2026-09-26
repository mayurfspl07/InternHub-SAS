import 'dart:async';
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
import 'widgets/staff_attendance_export_dialog.dart';

class StaffAttendanceScreen extends ConsumerStatefulWidget {
  final String initialTab; // 'all' | 'today'

  const StaffAttendanceScreen({super.key, this.initialTab = 'all'});

  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  final AttendanceRepository _repo = AttendanceRepository();

  late String _activeTab; // 'all' or 'today'
  bool _isLoading = true;

  // TAB ALL STATE
  List<AdminStudent> _allStudents = [];
  int _allPage = 1;
  int _allTotalPages = 1;
  int _allTotal = 0;
  final TextEditingController _allSearchController = TextEditingController();
  bool? _allIsActive;
  Timer? _allDebounceTimer;

  // TAB TODAY STATE
  AdminTodaySummary? _todaySummary;
  List<AdminTodayStudentItem> _todayStudents = [];
  int _todayPage = 1;
  int _todayTotalPages = 1;
  int _todayTotal = 0;
  final TextEditingController _todaySearchController = TextEditingController();
  final TextEditingController _todayDeptController = TextEditingController();
  String _todayStatus = 'All statuses';
  Timer? _todayDebounceTimer;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _loadData();
  }

  @override
  void dispose() {
    _allSearchController.dispose();
    _todaySearchController.dispose();
    _todayDeptController.dispose();
    _allDebounceTimer?.cancel();
    _todayDebounceTimer?.cancel();
    super.dispose();
  }

  bool _isMentorRole() {
    final role = ref.read(appStateProvider).currentUser.role;
    return role == UserRole.mentor;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    if (_activeTab == 'all') {
      await _fetchTabAll();
    } else {
      await _fetchTabToday();
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchTabAll() async {
    try {
      final res = await _repo.fetchStaffStudents(
        isMentor: _isMentorRole(),
        page: _allPage,
        pageSize: 20,
        search: _allSearchController.text.trim(),
        isActive: _allIsActive,
      );
      if (mounted) {
        setState(() {
          _allStudents = res.students;
          _allTotalPages = res.totalPages;
          _allTotal = res.total;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchTabToday() async {
    try {
      final res = await _repo.fetchStaffToday(
        isMentor: _isMentorRole(),
        page: _todayPage,
        pageSize: 20,
        search: _todaySearchController.text.trim(),
        department: _todayDeptController.text.trim(),
        status: _todayStatus != 'All statuses' ? _todayStatus : null,
      );
      if (mounted) {
        setState(() {
          _todaySummary = res.summary;
          _todayStudents = res.students;
          _todayTotalPages = res.totalPages;
          _todayTotal = res.total;
        });
      }
    } catch (_) {}
  }

  void _onAllSearchChanged(String val) {
    _allDebounceTimer?.cancel();
    _allDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      setState(() => _allPage = 1);
      _fetchTabAll();
    });
  }

  void _onTodaySearchChanged(String val) {
    _todayDebounceTimer?.cancel();
    _todayDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      setState(() => _todayPage = 1);
      _fetchTabToday();
    });
  }

  void _openStudentDetail(int studentId, [AdminStudent? student]) {
    Navigator.pushNamed(
      context,
      '/attendance/$studentId',
      arguments: student,
    );
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

  Color _getTodayStatusBg(String status) {
    switch (status.toLowerCase()) {
      case 'checked_in':
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
      case 'not_checked_in':
      default:
        return AppColors.surfaceMuted;
    }
  }

  Color _getTodayStatusFg(String status) {
    switch (status.toLowerCase()) {
      case 'checked_in':
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
      case 'not_checked_in':
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMentor = _isMentorRole();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeader(
                  title: 'Attendance',
                  subtitle: 'Student attendance, last 30 days',
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),

                // Top Segmented Tab Pill: [ All Attendance | 📅 Today's Attendance ]
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTabButton(
                        title: 'All Attendance',
                        isSelected: _activeTab == 'all',
                        onTap: () {
                          if (_activeTab != 'all') {
                            setState(() => _activeTab = 'all');
                            _loadData();
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                      _buildTabButton(
                        title: "Today's Attendance",
                        icon: Icons.calendar_today_outlined,
                        isSelected: _activeTab == 'today',
                        onTap: () {
                          if (_activeTab != 'today') {
                            setState(() => _activeTab = 'today');
                            _loadData();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Content for Active Tab
                if (_activeTab == 'all')
                  _buildAllAttendanceTab(isMentor)
                else
                  _buildTodayAttendanceTab(isMentor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? AppColors.ink
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? AppColors.ink
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // TAB 1: ALL ATTENDANCE (Screenshot 1)
  // -----------------------------------------------------------------
  Widget _buildAllAttendanceTab(bool isMentor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Symmetrical Filter Controls Card (SEARCH full width, STATUS + EXPORT side-by-side)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSpacing.r20),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Input (Full Width)
              Text(
                'SEARCH',
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
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.r12),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: TextField(
                  controller: _allSearchController,
                  onChanged: _onAllSearchChanged,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search name, email, department...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                    filled: false,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Row 2: Status Dropdown & Export Button (Symmetrical, 100% width)
              Row(
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
                              value: _allIsActive == null
                                  ? 'All'
                                  : (_allIsActive! ? 'Active' : 'Inactive'),
                              isExpanded: true,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                              dropdownColor: Colors.white,
                              items: const [
                                DropdownMenuItem(value: 'All', child: Text('All')),
                                DropdownMenuItem(value: 'Active', child: Text('Active')),
                                DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  if (v == 'Active') {
                                    _allIsActive = true;
                                  } else if (v == 'Inactive') {
                                    _allIsActive = false;
                                  } else {
                                    _allIsActive = null;
                                  }
                                  _allPage = 1;
                                });
                                _fetchTabAll();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Export Button
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 18),
                        SizedBox(
                          height: 42,
                          child: OutlinedButton.icon(
                            onPressed: () => StaffAttendanceExportDialog.show(
                              context,
                              isMentor: isMentor,
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
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Table Content
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_allStudents.isEmpty)
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
                'No students found.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          )
        else
          _buildAllStudentsList(),
      ],
    );
  }

  Widget _buildAllStudentsList() {
    return Column(
      children: [
        ..._allStudents.asMap().entries.map((entry) {
          final index = entry.key;
          final student = entry.value;
          final srNo = (_allPage - 1) * 20 + index + 1;
          final overview = student.attendanceOverview;
          final dept = student.department ?? 'General';

          return InkWell(
            onTap: () => _openStudentDetail(student.id, student),
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
                  // SR. NO Badge
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$srNo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name, Email & Department
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${student.email}  •  $dept',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Present, Absent, Late Mini-Pills
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildOverviewPill('P', overview?.present ?? 0, AppColors.success),
                      const SizedBox(width: 4),
                      _buildOverviewPill('A', overview?.absent ?? 0, AppColors.danger),
                      const SizedBox(width: 4),
                      _buildOverviewPill('L', overview?.late ?? 0, AppColors.warning),
                    ],
                  ),
                  const SizedBox(width: 4),

                  // Actions Menu
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
                        _openStudentDetail(student.id, student);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Text('View Details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),

        // Pagination
        _buildPaginationBar(
          page: _allPage,
          totalPages: _allTotalPages,
          total: _allTotal,
          label: 'students',
          onPrev: _allPage > 1
              ? () {
                  setState(() => _allPage--);
                  _fetchTabAll();
                }
              : null,
          onNext: _allPage < _allTotalPages
              ? () {
                  setState(() => _allPage++);
                  _fetchTabAll();
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildOverviewPill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
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

  // -----------------------------------------------------------------
  // TAB 2: TODAY'S ATTENDANCE (Screenshot 2)
  // -----------------------------------------------------------------
  Widget _buildTodayAttendanceTab(bool isMentor) {
    final summary = _todaySummary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 6 Summary Metric Cards in 2 Symmetrical Rows of 3 Cards each (100% full width)
        if (summary != null) ...[
          Row(
            children: [
              Expanded(child: _buildTodayStatCard('TOTAL INTERNS', '${summary.totalInterns}')),
              const SizedBox(width: 8),
              Expanded(child: _buildTodayStatCard('CHECKED IN', '${summary.checkedIn}')),
              const SizedBox(width: 8),
              Expanded(child: _buildTodayStatCard('CHECKED OUT', '${summary.checkedOut}')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildTodayStatCard('PRESENT', '${summary.present}')),
              const SizedBox(width: 8),
              Expanded(child: _buildTodayStatCard('LATE', '${summary.late}')),
              const SizedBox(width: 8),
              Expanded(child: _buildTodayStatCard('ATT. RATE', '${summary.attendanceRate.toStringAsFixed(1)}%')),
            ],
          ),
          const SizedBox(height: 14),
        ],

        // Filter Controls Card (SEARCH full width, STATUS + DEPARTMENT side by side)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSpacing.r20),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Input
              Text(
                'SEARCH',
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
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.r12),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: TextField(
                  controller: _todaySearchController,
                  onChanged: _onTodaySearchChanged,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search student name, email..',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                    filled: false,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  // Status Dropdown
                  Expanded(
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
                              value: _todayStatus,
                              isExpanded: true,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                              dropdownColor: Colors.white,
                              items: const [
                                DropdownMenuItem(value: 'All statuses', child: Text('All statuses')),
                                DropdownMenuItem(value: 'present', child: Text('Present')),
                                DropdownMenuItem(value: 'late', child: Text('Late')),
                                DropdownMenuItem(value: 'half_day', child: Text('Half-Day')),
                                DropdownMenuItem(value: 'absent', child: Text('Absent')),
                                DropdownMenuItem(value: 'on_leave', child: Text('On Leave')),
                                DropdownMenuItem(value: 'not_checked_in', child: Text('Not Checked In')),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _todayStatus = v;
                                    _todayPage = 1;
                                  });
                                  _fetchTabToday();
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Department Field
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEPARTMENT',
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
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppSpacing.r12),
                            border: Border.all(
                              color: AppColors.border,
                            ),
                          ),
                          child: TextField(
                            controller: _todayDeptController,
                            onChanged: (val) {
                              _todayDebounceTimer?.cancel();
                              _todayDebounceTimer = Timer(const Duration(milliseconds: 400), () {
                                setState(() => _todayPage = 1);
                                _fetchTabToday();
                              });
                            },
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Department...',
                              hintStyle: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: InputBorder.none,
                              filled: false,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
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
        const SizedBox(height: 14),

        // Today Students Table
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_todayStudents.isEmpty)
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
                'No student records for today.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          )
        else
          _buildTodayStudentsList(),
      ],
    );
  }

  Widget _buildTodayStatCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
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

  Widget _buildTodayStudentsList() {
    return Column(
      children: [
        ..._todayStudents.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final student = item.student;
          final srNo = (_todayPage - 1) * 20 + index + 1;

          final inTime = _formatTime(item.attendance?.checkIn);
          final outTime = _formatTime(item.attendance?.checkOut);
          final hours = item.attendance?.hoursWorked != null
              ? '${item.attendance!.hoursWorked!.toStringAsFixed(1)}h'
              : '—';

          final statusLabel = item.todayStatus == 'not_checked_in'
              ? 'Not Checked In'
              : item.todayStatus.replaceAll('_', ' ').toUpperCase();
          final bg = _getTodayStatusBg(item.todayStatus);
          final fg = _getTodayStatusFg(item.todayStatus);
          final dept = student.department ?? 'General';

          return InkWell(
            onTap: () => _openStudentDetail(student.id, student),
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
                  // SR. NO Badge
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$srNo',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Student info and shift details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              student.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '($dept)',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'In: $inTime  •  Out: $outTime  •  $hours',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Status Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Actions Menu
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
                        _openStudentDetail(student.id, student);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'view',
                        child: Text('View Details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 12),

        // Pagination
        _buildPaginationBar(
          page: _todayPage,
          totalPages: _todayTotalPages,
          total: _todayTotal,
          label: 'students',
          onPrev: _todayPage > 1
              ? () {
                  setState(() => _todayPage--);
                  _fetchTabToday();
                }
              : null,
          onNext: _todayPage < _todayTotalPages
              ? () {
                  setState(() => _todayPage++);
                  _fetchTabToday();
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildPaginationBar({
    required int page,
    required int totalPages,
    required int total,
    required String label,
    VoidCallback? onPrev,
    VoidCallback? onNext,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Page $page of $totalPages ($total $label)',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        Row(
          children: [
            OutlinedButton(
              onPressed: onPrev,
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
                '$page',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: onNext,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r8)),
              ),
              child: const Text('Next', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}
