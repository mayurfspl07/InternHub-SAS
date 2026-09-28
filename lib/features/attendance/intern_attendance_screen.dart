import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/attendance_model.dart';
import 'attendance_repository.dart';
import 'checkin_checkout_screen.dart';
import 'widgets/attendance_day_detail_modal.dart';
import 'widgets/intern_attendance_export_dialog.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../core/utils/formatters.dart';

class InternAttendanceScreen extends ConsumerStatefulWidget {
  const InternAttendanceScreen({super.key});

  @override
  ConsumerState<InternAttendanceScreen> createState() => _InternAttendanceScreenState();
}

class _InternAttendanceScreenState extends ConsumerState<InternAttendanceScreen> {
  final AttendanceRepository _repo = AttendanceRepository();

  bool _isLoading = true;
  String? _loadError;
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
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      // 1. Fetch today's record
      final todayResult = await _repo.fetchTodayAttendance();
      _todayRecord = todayResult.record;


      // 2. Fetch history for current selected month
      final monthStr = DateFormat('yyyy-MM').format(_currentMonth);
      final history = await _repo.fetchHistory(month: monthStr, pageSize: 100);

      _monthRecords = history.records;
      _recordsByDate = {
        for (final r in history.records) r.date: r,
      };
    } catch (e) {
      _loadError = apiErrorMessage(e);
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _changeMonth(int delta) async {
    final newMonth = DateTime(_currentMonth.year, _currentMonth.month + delta, 1);
    final user = ref.read(appStateProvider).currentUser;
    final thisMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    if (newMonth.isAfter(thisMonth)) return; // no attendance in future months

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
        return AppColors.successSoft; // Mint light
      case 'late':
        return AppColors.warningSoft; // Yellow light
      case 'half_day':
      case 'halfday':
        return AppColors.infoSoft; // Blue light
      case 'absent':
        return AppColors.dangerSoft; // Red light
      case 'on_leave':
      case 'leave':
        return AppColors.lavender; // Purple light
      case 'excused':
        return AppColors.successSoft; // Teal light
      case 'week_off':
      case 'off':
        return AppColors.surfaceMuted; // Grey light
      default:
        return Colors.transparent;
    }
  }

  Color _getStatusTextColor(String status) {
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
      case 'week_off':
      case 'off':
        return AppColors.textSecondary;
      default:
        return AppColors.ink;
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

  int _countStatus(AttendanceStatus status) =>
      _monthRecords.where((r) => AttendanceStatus.fromString(r.status) == status).length;

  Widget _statPill(Color dot, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.r20),
          boxShadow: AppShadows.soft,
        ),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
          ],
        ),
      ),
    );
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
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    final notCheckedIn = _todayRecord == null || _todayRecord?.checkIn == null;
    final canCheckOut = _todayRecord?.checkIn != null && _todayRecord?.checkOut == null;

    final todayHours = _todayRecord?.hoursWorked ?? 0.0;
    final monthHours = _calculateMonthHours();
    final daysLogged = _calculateDaysLogged();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                PageHeader(
                  title: 'Attendance',
                  padding: EdgeInsets.zero,
                  actions: [
                    HeaderAction(
                      icon: Icons.download_rounded,
                      tooltip: 'Export CSV',
                      onTap: () => InternAttendanceExportDialog.show(context),
                    ),
                  ],
                ),
                if (_isLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (!_isLoading && _loadError != null) ...[
                  const SizedBox(height: 12),
                  LoadErrorView(
                    title: "Couldn't load your attendance",
                    message: _loadError!,
                    onRetry: _loadData,
                    compact: true,
                  ),
                ],
                const SizedBox(height: 20),

                if (_loadError == null) ...[
                  // Month totals from the loaded records
                  Row(
                    children: [
                      _statPill(AppColors.success, '${_countStatus(AttendanceStatus.present)} present'),
                      const SizedBox(width: 8),
                      _statPill(AppColors.warning, '${_countStatus(AttendanceStatus.late)} late'),
                      const SizedBox(width: 8),
                      _statPill(AppColors.danger, '${_countStatus(AttendanceStatus.absent)} absent'),
                    ],
                  ),
                  const SizedBox(height: 18),

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
                                todayStr: todayStr,
                              ),
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildTodayShiftCard(
                              notCheckedIn: notCheckedIn,
                              canCheckOut: canCheckOut,
                              todayHours: todayHours,
                              monthHours: monthHours,
                              daysLogged: daysLogged,
                            ),
                            const SizedBox(height: 20),
                            _buildMonthlyAttendanceCard(
                              todayStr: todayStr,
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ],
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
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
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.r12),
                ),
                child: const Icon(
                  Icons.access_time_rounded,
                  color: AppColors.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Today's Shift",
                style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
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
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOGIN TIME',
                        style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        loginTime,
                        style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
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
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                    border: Border.all(
                      color: AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LOGOUT TIME',
                        style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        logoutTime,
                        style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
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
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                    border: Border.all(
                      color: AppColors.primary,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hours today',
                        style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.onPrimary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${todayHours.toStringAsFixed(1)} hrs',
                        style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
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
                    color: AppColors.lavender,
                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                    border: Border.all(
                      color: AppColors.lavender,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MONTH TOTAL',
                        style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.lavenderInk, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${monthHours.toStringAsFixed(1)} hrs',
                        style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.lavenderInk),
                      ),
                      Text(
                        '$daysLogged days logged',
                        style: AppTypography.label.copyWith(color: AppColors.lavenderInk),
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
                  label: Text(
                    'Check In',
                    style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.border,
                    disabledForegroundColor: AppColors.textTertiary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
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
                  label: Text(
                    'Check Out',
                    style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.dangerSoft, // Light red/pink
                    foregroundColor: AppColors.dangerInk,
                    disabledBackgroundColor: AppColors.border,
                    disabledForegroundColor: AppColors.textTertiary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      side: BorderSide(
                        color: canCheckOut ? AppColors.danger : Colors.transparent,
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
    required String todayStr,
  }) {
    final monthLabel = DateFormat('MMMM yyyy').format(_currentMonth);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Monthly Attendance Title & Toggle [Calendar | List]
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.r12),
                    ),
                    child: const Icon(
                      Icons.date_range_rounded,
                      color: AppColors.primaryInk,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                    'Monthly Attendance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  ),
                ],
              ),
              ),
              const SizedBox(width: 8),

              // Calendar | List toggle
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    _buildToggleItem(
                      title: 'Calendar',
                      isSelected: _viewMode == 'calendar',
                      onTap: () => setState(() => _viewMode = 'calendar'),
                    ),
                    _buildToggleItem(
                      title: 'List',
                      isSelected: _viewMode == 'list',
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
                  tooltip: 'Previous month',
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: AppColors.ink,
                  visualDensity: VisualDensity.compact,
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      monthLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _currentMonth.year == DateTime.now().year && _currentMonth.month == DateTime.now().month
                      ? null
                      : () => _changeMonth(1),
                  tooltip: 'Next month',
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: AppColors.ink,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Calendar Grid
            _buildCalendarGrid(todayStr: todayStr),
            const SizedBox(height: 20),

            // Status Legend Row
            _buildLegend(),
          ] else ...[
            // List View Mode
            _buildListView(),
          ],
        ],
      ),
    );
  }

  Widget _buildToggleItem({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Text(
          title,
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: isSelected
                ? AppColors.ink
                : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid({required String todayStr}) {
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
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.textTertiary),
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
                } else if (cellDate.isBefore(today)) {
                  resolvedStatus = 'absent';
                } else if (cellDate.isAtSameMomentAs(today)) {
                  resolvedStatus = 'pending'; // today, not checked in yet
                } else {
                  resolvedStatus = 'upcoming';
                }

                final isClickable = resolvedStatus != 'upcoming' && resolvedStatus != 'not_joined';
                final bg = _getStatusBgColor(resolvedStatus);
                final fg = _getStatusTextColor(resolvedStatus);

                return Semantics(
                  label: '${DateFormat('d MMMM').format(cellDate)}, ${humanize(resolvedStatus)}',
                  button: isClickable,
                  excludeSemantics: true,
                  child: GestureDetector(
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
                            ? AppColors.ink // Today ring
                            : (bg == Colors.transparent
                                ? AppColors.border
                                : Colors.transparent),
                        width: isToday ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$dayNumber',
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: resolvedStatus == 'upcoming'
                              ? AppColors.textTertiary
                              : fg),
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

  Widget _buildLegend() {
    final items = [
      ('Present', AppColors.success),
      ('Late', AppColors.warning),
      ('Half day', AppColors.info),
      ('Absent', AppColors.danger),
      ('On leave', AppColors.lavenderInk),
      ('Off', AppColors.textSecondary),
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
              style: AppTypography.label.copyWith(color: AppColors.textSecondary),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildListView() {
    if (_monthRecords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: Text(
            'No records found for this month.',
            style: TextStyle(
              color: AppColors.textSecondary,
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

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              border: Border.all(
                color: AppColors.border,
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
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$inStr - $outStr',
                        style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                StatusChip.fromString(r.status),
                const SizedBox(width: 14),
                Text(
                  hours,
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => _onDayTapped(dt, r, r.status),
                  tooltip: 'Open day',
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),

        PaginationBar(
          page: _listPage,
          totalPages: totalPages,
          totalItems: total,
          itemLabel: 'records',
          onPageChanged: (p) => setState(() => _listPage = p),
        ),
      ],
    );
  }
}
