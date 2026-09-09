import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/attendance_model.dart';
import 'attendance_repository.dart';
import 'checkin_checkout_screen.dart';
import 'widgets/attendance_day_detail_modal.dart';
import 'widgets/intern_attendance_export_dialog.dart';

class InternAttendanceScreen extends ConsumerStatefulWidget {
  const InternAttendanceScreen({super.key});

  @override
  ConsumerState<InternAttendanceScreen> createState() => _InternAttendanceScreenState();
}

class _InternAttendanceScreenState extends ConsumerState<InternAttendanceScreen> {
  final AttendanceRepository _repo = AttendanceRepository();

  bool _isLoading = true;
  AttendanceRecord? _todayRecord;
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  List<AttendanceRecord> _monthRecords = [];
  Map<String, AttendanceRecord> _recordsByDate = {};

  // View switch: 'calendar' or 'list'
  String _viewMode = 'calendar';

  // Client-side pagination for list mode (page size 6)
  int _listPage = 1;
  final int _listPageSize = 6;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch today's record
      final todayResult = await _repo.fetchTodayAttendance();
      _todayRecord = todayResult.record;

      // Also sync to app state provider if needed
      if (_todayRecord != null) {
        ref.read(appStateProvider.notifier).fetchAttendance();
      }

      // 2. Fetch history for current selected month
      final monthStr = DateFormat('yyyy-MM').format(_currentMonth);
      final history = await _repo.fetchHistory(month: monthStr, pageSize: 100);

      _monthRecords = history.records;
      _recordsByDate = {
        for (final r in history.records) r.date: r,
      };
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeMonth(int delta) async {
    final newMonth = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
    final user = ref.read(appStateProvider).currentUser;

    // Rule: cannot navigate calendar before joining month
    if (user.joiningDate != null && delta < 0) {
      final jDate = DateTime.tryParse(user.joiningDate!);
      if (jDate != null) {
        final joinMonth = DateTime(jDate.year, jDate.month, 1);
        if (newMonth.isBefore(joinMonth)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot navigate before your joining month.')),
          );
          return;
        }
      }
    }

    setState(() {
      _currentMonth = newMonth;
      _listPage = 1;
    });
    await _loadData();
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

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return const Color(0xFFD1FAE5); // Mint light
      case 'late':
        return const Color(0xFFFEF3C7); // Yellow light
      case 'half_day':
      case 'halfday':
        return const Color(0xFFE0F2FE); // Blue light
      case 'absent':
        return const Color(0xFFFEE2E2); // Red light
      case 'on_leave':
      case 'leave':
        return const Color(0xFFEDE9FE); // Purple light
      case 'excused':
        return const Color(0xFFCCFBF1); // Teal light
      case 'week_off':
      case 'off':
        return const Color(0xFFF3F4F6); // Grey light
      default:
        return Colors.transparent;
    }
  }

  Color _getStatusTextColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return const Color(0xFF065F46);
      case 'late':
        return const Color(0xFF92400E);
      case 'half_day':
      case 'halfday':
        return const Color(0xFF0369A1);
      case 'absent':
        return const Color(0xFF991B1B);
      case 'on_leave':
      case 'leave':
        return const Color(0xFF5B21B6);
      case 'excused':
        return const Color(0xFF115E59);
      case 'week_off':
      case 'off':
        return const Color(0xFF4B5563);
      default:
        return AppColors.textPrimaryLight;
    }
  }

  double _calculateMonthHours() {
    double total = 0;
    for (final r in _monthRecords) {
      if (r.hoursWorked != null) {
        total += r.hoursWorked!;
      }
    }
    return total;
  }

  int _calculateDaysLogged() {
    return _monthRecords.where((r) => r.checkIn != null).length;
  }

  void _onDayTapped(DateTime dayDate, AttendanceRecord? record, String resolvedStatus) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (dayDate.isAfter(today)) return; // upcoming day

    final user = ref.read(appStateProvider).currentUser;
    if (user.joiningDate != null) {
      final jDate = DateTime.tryParse(user.joiningDate!);
      if (jDate != null && dayDate.isBefore(DateTime(jDate.year, jDate.month, jDate.day))) {
        return; // not joined yet
      }
    }

    final actorId = int.tryParse(user.id);
    AttendanceDayDetailModal.show(
      context,
      date: dayDate,
      record: record,
      status: resolvedStatus,
      actorId: actorId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    final notCheckedIn = _todayRecord == null || _todayRecord?.checkIn == null;
    final canCheckOut = _todayRecord?.checkIn != null && _todayRecord?.checkOut == null;

    final todayHours = _todayRecord?.hoursWorked ?? 0.0;
    final monthHours = _calculateMonthHours();
    final daysLogged = _calculateDaysLogged();

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
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
                // Top Header Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.cardDark : Colors.white,
                        borderRadius: BorderRadius.circular(AppSpacing.r16),
                        border: Border.all(
                          color: isDark ? AppColors.borderDark : AppColors.borderLight,
                        ),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Color(0xFFF59E0B),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Attendance',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Track your daily check-ins, hours worked, and monthly attendance calendar.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Export CSV button
                    OutlinedButton.icon(
                      onPressed: () => InternAttendanceExportDialog.show(context),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text(
                        'Export CSV',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? Colors.white : AppColors.textPrimaryLight,
                        side: BorderSide(
                          color: isDark ? AppColors.borderDark : AppColors.borderLight,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.rPill),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 20),

                // Not Checked In Alert Banner (Screenshot 4)
                if (notCheckedIn) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C1C16) : const Color(0xFFFEF3C7).withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppSpacing.r20),
                      border: Border.all(
                        color: isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1F2937),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.access_time_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "You haven't checked in today",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: isDark ? Colors.white : const Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Verify your selfie photo & GPS location to log today's hours.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CheckinCheckoutScreen(isCheckOut: false),
                              ),
                            );
                            _loadData();
                          },
                          icon: const Text(
                            'Check in now',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          label: const Icon(Icons.arrow_forward_rounded, size: 14),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF111827),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // Layout: Today's Shift Card & Monthly Attendance Card
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 780;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 4,
                            child: _buildTodayShiftCard(
                              isDark: isDark,
                              notCheckedIn: notCheckedIn,
                              canCheckOut: canCheckOut,
                              todayHours: todayHours,
                              monthHours: monthHours,
                              daysLogged: daysLogged,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 6,
                            child: _buildMonthlyAttendanceCard(
                              isDark: isDark,
                              todayStr: todayStr,
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildTodayShiftCard(
                            isDark: isDark,
                            notCheckedIn: notCheckedIn,
                            canCheckOut: canCheckOut,
                            todayHours: todayHours,
                            monthHours: monthHours,
                            daysLogged: daysLogged,
                          ),
                          const SizedBox(height: 20),
                          _buildMonthlyAttendanceCard(
                            isDark: isDark,
                            todayStr: todayStr,
                          ),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------
  // CARD 1: TODAY'S SHIFT
  // -----------------------------------------------------------------
  Widget _buildTodayShiftCard({
    required bool isDark,
    required bool notCheckedIn,
    required bool canCheckOut,
    required double todayHours,
    required double monthHours,
    required int daysLogged,
  }) {
    final loginTime = _formatTime(_todayRecord?.checkIn);
    final logoutTime = _formatTime(_todayRecord?.checkOut);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.r12),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: Color(0xFFF59E0B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Today's Shift",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Login Time & Logout Time Boxes
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOGIN TIME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        loginTime,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOGOUT TIME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        logoutTime,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Metric Boxes: Hours Today (Yellow) & Month Total (Purple)
          Row(
            children: [
              // HOURS TODAY (Yellow box)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFFCA8A04) : AppColors.cardYellow,
                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                    border: Border.all(
                      color: isDark ? const Color(0xFFA16207) : const Color(0xFFE5C522),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HOURS TODAY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white70 : const Color(0xFF713F12),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${todayHours.toStringAsFixed(1)} hrs',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // MONTH TOTAL (Purple box)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF6D28D9) : const Color(0xFFDDD6FE),
                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF5B21B6) : const Color(0xFFC4B5FD),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MONTH TOTAL',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white70 : const Color(0xFF4C1D95),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${monthHours.toStringAsFixed(1)} hrs',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : const Color(0xFF2E1065),
                        ),
                      ),
                      Text(
                        '$daysLogged days logged',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : const Color(0xFF5B21B6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action Buttons: Check In & Check Out
          Row(
            children: [
              // Check In Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: notCheckedIn
                      ? () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CheckinCheckoutScreen(isCheckOut: false),
                            ),
                          );
                          _loadData();
                        }
                      : null,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text(
                    'Check In',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cardYellow,
                    foregroundColor: Colors.black87,
                    disabledBackgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                    disabledForegroundColor: isDark ? Colors.white38 : Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      side: BorderSide(
                        color: notCheckedIn ? const Color(0xFFD97706) : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Check Out Button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: canCheckOut
                      ? () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CheckinCheckoutScreen(isCheckOut: true),
                            ),
                          );
                          _loadData();
                        }
                      : null,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text(
                    'Check Out',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFCA5A5), // Light red/pink
                    foregroundColor: const Color(0xFF7F1D1D),
                    disabledBackgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                    disabledForegroundColor: isDark ? Colors.white38 : Colors.grey.shade400,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      side: BorderSide(
                        color: canCheckOut ? const Color(0xFFEF4444) : Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------
  // CARD 2: MONTHLY ATTENDANCE
  // -----------------------------------------------------------------
  Widget _buildMonthlyAttendanceCard({
    required bool isDark,
    required String todayStr,
  }) {
    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Monthly Attendance Title & Toggle [Calendar | List]
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.r12),
                    ),
                    child: const Icon(
                      Icons.date_range_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Monthly Attendance',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                ],
              ),

              // Calendar | List Toggle Pill (Screenshot 4)
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    _buildToggleItem(
                      title: 'Calendar',
                      isSelected: _viewMode == 'calendar',
                      isDark: isDark,
                      onTap: () => setState(() => _viewMode = 'calendar'),
                    ),
                    _buildToggleItem(
                      title: 'List',
                      isSelected: _viewMode == 'list',
                      isDark: isDark,
                      onTap: () => setState(() => _viewMode = 'list'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_viewMode == 'calendar') ...[
            // Month Navigation Row: < September 2026 >
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    monthLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Calendar Grid
            _buildCalendarGrid(isDark: isDark, todayStr: todayStr),
            const SizedBox(height: 20),

            // Status Legend Row
            _buildLegend(isDark: isDark),
          ] else ...[
            // List View Mode
            _buildListView(isDark: isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.cardYellowDark : AppColors.cardYellow)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? Colors.black87
                : (isDark ? Colors.white70 : AppColors.textSecondaryLight),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid({required bool isDark, required String todayStr}) {
    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final year = _currentMonth.year;
    final month = _currentMonth.month;

    final firstDayOfMonth = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingSpaces = firstDayOfMonth.weekday % 7; // Sunday = 0, Mon = 1...

    final totalCells = leadingSpaces + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final user = ref.read(appStateProvider).currentUser;
    DateTime? joiningDate;
    if (user.joiningDate != null) {
      final parsed = DateTime.tryParse(user.joiningDate!);
      if (parsed != null) joiningDate = DateTime(parsed.year, parsed.month, parsed.day);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      children: [
        // Weekday header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: weekdays
              .map(
                (d) => SizedBox(
                  width: 36,
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white54 : AppColors.textTertiaryLight,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),

        // Grid rows
        ...List.generate(rows, (rowIndex) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(7, (colIndex) {
                final cellIndex = rowIndex * 7 + colIndex;
                final dayNumber = cellIndex - leadingSpaces + 1;

                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox(width: 36, height: 36);
                }

                final cellDate = DateTime(year, month, dayNumber);
                final dateKey = DateFormat('yyyy-MM-dd').format(cellDate);
                final isToday = dateKey == todayStr;
                final isSunday = colIndex == 0;
                final record = _recordsByDate[dateKey];

                // Determine virtual status according to web rules
                String resolvedStatus;
                if (record != null) {
                  resolvedStatus = record.status;
                } else if (joiningDate != null && cellDate.isBefore(joiningDate)) {
                  resolvedStatus = 'not_joined';
                } else if (isSunday) {
                  resolvedStatus = 'week_off';
                } else if (cellDate.isBefore(today) || cellDate.isAtSameMomentAs(today)) {
                  resolvedStatus = 'absent';
                } else {
                  resolvedStatus = 'upcoming';
                }

                final isClickable = resolvedStatus != 'upcoming' && resolvedStatus != 'not_joined';
                final bg = _getStatusBgColor(resolvedStatus);
                final fg = _getStatusTextColor(resolvedStatus);

                return GestureDetector(
                  onTap: isClickable
                      ? () => _onDayTapped(cellDate, record, resolvedStatus)
                      : null,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isToday
                            ? const Color(0xFFEF4444) // Today ring
                            : (bg == Colors.transparent
                                ? (isDark ? AppColors.borderDark : const Color(0xFFE5E7EB))
                                : Colors.transparent),
                        width: isToday ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                          color: resolvedStatus == 'upcoming'
                              ? (isDark ? Colors.white38 : Colors.grey.shade400)
                              : fg,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLegend({required bool isDark}) {
    final items = [
      ('Present', const Color(0xFF10B981)),
      ('Late', const Color(0xFFEAB308)),
      ('Half-Day', const Color(0xFF0284C7)),
      ('Absent', const Color(0xFFEF4444)),
      ('Leave', const Color(0xFF8B5CF6)),
      ('Off', const Color(0xFF6B7280)),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: item.$2,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              item.$1,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildListView({required bool isDark}) {
    if (_monthRecords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            'No records found for this month.',
            style: TextStyle(
              color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
            ),
          ),
        ),
      );
    }

    final total = _monthRecords.length;
    final totalPages = (total / _listPageSize).ceil();
    final startIndex = (_listPage - 1) * _listPageSize;
    final endIndex = (startIndex + _listPageSize < total) ? startIndex + _listPageSize : total;
    final pageRecords = _monthRecords.sublist(startIndex, endIndex);

    return Column(
      children: [
        ...pageRecords.map((r) {
          final dt = DateTime.tryParse(r.date) ?? DateTime.now();
          final formattedDate = DateFormat('EEE, MMM d').format(dt);
          final inStr = _formatTime(r.checkIn);
          final outStr = _formatTime(r.checkOut);
          final hours = r.hoursWorked != null ? '${r.hoursWorked!.toStringAsFixed(1)}h' : '—';
          final bg = _getStatusBgColor(r.status);
          final fg = _getStatusTextColor(r.status);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$inStr - $outStr',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                const SizedBox(width: 14),
                Text(
                  hours,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => _onDayTapped(dt, r, r.status),
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),

        // Pagination Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Page $_listPage of $totalPages ($total records)',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: _listPage > 1 ? () => setState(() => _listPage--) : null,
                  icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
                Text(
                  '$_listPage',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                IconButton(
                  onPressed: _listPage < totalPages ? () => setState(() => _listPage++) : null,
                  icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
