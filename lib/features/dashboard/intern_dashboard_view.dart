import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/app_tag.dart';
import '../../shared/widgets/hero_banner_card.dart';
import '../../shared/widgets/horizontal_date_strip.dart';
import '../../shared/widgets/pastel_card.dart';
import '../../shared/widgets/reference_components.dart';
import '../../shared/widgets/load_error_view.dart';
import '../attendance/attendance_home_screen.dart';
import '../projects_tasks/projects_list_screen.dart';
import '../leaves/leave_dashboard_screen.dart';
import '../standup/standup_screen.dart';
import '../standup/standup_repository.dart';
import '../standup/models/standup_models.dart';
import '../announcements/announcements_screen.dart';
import 'dashboard_repository.dart';
import 'models/dashboard_models.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/dashboard_shared.dart';

class InternDashboardView extends ConsumerStatefulWidget {
  const InternDashboardView({super.key});

  @override
  ConsumerState<InternDashboardView> createState() => _InternDashboardViewState();
}

class _InternDashboardViewState extends ConsumerState<InternDashboardView> {
  final DashboardRepository _repository = DashboardRepository();

  bool _isLoading = true;
  String? _errorMessage;
  InternDashboardData? _dashboardData;
  StandupLog? _todayStandup;

  Timer? _timer;
  Duration _elapsedTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _startShiftTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startShiftTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateElapsedDuration();
      }
    });
  }

  void _updateElapsedDuration() {
    final checkInStr = _dashboardData?.todayAttendance.checkIn;
    if (checkInStr != null &&
        _dashboardData?.todayAttendance.hasCheckedIn == true &&
        _dashboardData?.todayAttendance.hasCheckedOut == false) {
      DateTime? checkInDate;
      if (checkInStr.contains('T') || checkInStr.contains('-')) {
        checkInDate = DateTime.tryParse(checkInStr);
      } else {
        // Format might be "HH:mm:ss" or "HH:mm"
        final parts = checkInStr.split(':');
        if (parts.length >= 2) {
          final now = DateTime.now();
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts[1]) ?? 0;
          checkInDate = DateTime(now.year, now.month, now.day, h, m);
        }
      }

      if (checkInDate != null) {
        final now = DateTime.now();
        if (now.isAfter(checkInDate)) {
          setState(() {
            _elapsedTime = now.difference(checkInDate!);
          });
          return;
        }
      }
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// Loads the dashboard and today's standup. [silent] refreshes without the skeleton
  /// (used when returning from a screen that may have changed the data).
  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent || _dashboardData == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _repository.getInternDashboard(),
        StandupRepository().getTodayStandup(),
      ]);
      if (mounted) {
        setState(() {
          _dashboardData = results[0] as InternDashboardData;
          _todayStandup = results[1] as StandupLog?;
          _isLoading = false;
          _errorMessage = null;
        });
        _updateElapsedDuration();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = apiErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  /// Opens a screen and refreshes the dashboard when the user comes back.
  Future<void> _pushAndRefresh(Route<dynamic> route) async {
    await Navigator.of(context).push(route);
    if (mounted) await _loadDashboard(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: SafeArea(child: DashboardLoadingSkeleton()),
      );
    }

    if (_errorMessage != null || _dashboardData == null) {
      return Scaffold(
        body: SafeArea(
          child: DashboardErrorState(
            message: _errorMessage ?? 'Failed to load dashboard data',
            onRetry: _loadDashboard,
          ),
        ),
      );
    }

    final data = _dashboardData!;
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboard,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1) WEEK AT A GLANCE
                HorizontalDateStrip(
                  selectedDate: DateTime.now(),
                  showMonthHeader: false,
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
                  onDateSelected: (_) {
                    _pushAndRefresh(
                      MaterialPageRoute(builder: (_) => const AttendanceHomeScreen()),
                    );
                  },
                ),

                // 2) MY DAY: attendance hero
                SectionHeader(
                  title: 'My Day',
                  actionText: 'History',
                  onActionTap: () {
                    _pushAndRefresh(
                      MaterialPageRoute(builder: (_) => const AttendanceHomeScreen()),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _buildAttendanceHero(
                  context,
                  data.todayAttendance,
                  data.streak,
                ),
                const SizedBox(height: 24),

                // 3) QUICK ACCESS
                const SectionHeader(title: 'Quick Access'),
                const SizedBox(height: 12),
                _buildQuickAccess(context, data),
                const SizedBox(height: 24),

                // 4) ACTIVE SPRINT
                _buildHeroProjectCard(
                  context,
                  data.activeProjects.isNotEmpty ? data.activeProjects.first : null,
                ),
                const SizedBox(height: 24),

                // 5) PERSONAL STATS STRIP
                _buildStatsStrip(data.stats, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 6) CHARTS
                _buildChartsRow(data),
                const SizedBox(height: 20),

                // 5) OPEN TASKS
                DashboardSectionTitle(
                  title: 'My Open Tasks',
                  count: data.openTasks.length,
                  actionLabel: 'View Projects →',
                  onAction: () {
                    _pushAndRefresh(
                      MaterialPageRoute(builder: (_) => const ProjectsListScreen()),
                    );
                  },
                ),
                if (data.openTasks.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.task_alt_rounded,
                    title: 'No pending tasks',
                    subtitle: 'Great job! You are all caught up for today.',
                  )
                else
                  _buildTasksList(data.openTasks, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 6) ACTIVE PROJECTS
                DashboardSectionTitle(
                  title: 'Active Projects',
                  count: data.activeProjects.length,
                  actionLabel: 'Explore All →',
                  onAction: () {
                    _pushAndRefresh(
                      MaterialPageRoute(builder: (_) => const ProjectsListScreen()),
                    );
                  },
                ),
                if (data.activeProjects.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.folder_open_rounded,
                    title: 'No active projects',
                    subtitle: 'You are currently not assigned to any projects.',
                  )
                else
                  _buildProjectsList(data.activeProjects, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 7) ANNOUNCEMENTS
                DashboardSectionTitle(
                  title: 'Announcements',
                  count: data.announcements.length,
                  actionLabel: 'View All →',
                  onAction: () {
                    _pushAndRefresh(
                      MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
                    );
                  },
                ),
                if (data.announcements.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.campaign_outlined,
                    title: 'No announcements',
                    subtitle: 'No team notices or updates posted yet.',
                  )
                else
                  _buildAnnouncementsList(data.announcements, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 8) RECENT LEAVE REQUESTS
                DashboardSectionTitle(
                  title: 'Recent Leaves',
                  count: data.recentLeaveRequests.length,
                  actionLabel: 'Manage Leaves →',
                  onAction: () {
                    _pushAndRefresh(
                      MaterialPageRoute(builder: (_) => const LeaveDashboardScreen()),
                    );
                  },
                ),
                if (data.recentLeaveRequests.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.calendar_today_rounded,
                    title: 'No recent leave applications',
                    subtitle: 'Need time off? Apply for leave easily.',
                    actionLabel: 'Apply Leave',
                    onAction: () {
                      _pushAndRefresh(
                        MaterialPageRoute(builder: (_) => const LeaveDashboardScreen()),
                      );
                    },
                  )
                else
                  _buildLeavesList(data.recentLeaveRequests.take(3).toList(), cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 9) RECENT ACTIVITY
                DashboardSectionTitle(
                  title: 'Recent Activity',
                  count: data.recentActivity.length,
                ),
                DashboardActivityTimeline(
                  activities: data.recentActivity,
                  initialCount: 6,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // SECTION BUILDERS
  // ==========================================

  Widget _buildHeroProjectCard(BuildContext context, InternDashboardProject? project) {
    final title = project?.name ?? 'Project Alpha';
    final rawDesc = project?.description;
    final String subtitle = (rawDesc != null && rawDesc.trim().isNotEmpty)
        ? rawDesc.trim()
        : 'Frontend Development';
    final progress = project?.progress ?? 0.85;
    final pct = (progress * 100).round();

    return ReferenceCard(
      padding: const EdgeInsets.all(AppSpacing.p20),
      onTap: () {
        _pushAndRefresh(
          MaterialPageRoute(builder: (_) => const ProjectsListScreen()),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppTag(
                label: 'Active sprint',
                color: AppColors.lavenderInk,
                background: AppColors.lavender,
              ),
              const Spacer(),
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_outward_rounded, size: 18, color: AppColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: AppTypography.title),
          const SizedBox(height: 4),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.body),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                project == null
                    ? 'No project yet'
                    : '${project.completedTasksCount}/${project.myTasksCount} of my tasks'
                        '${project.mentorName != null && project.mentorName!.isNotEmpty ? ' · ${project.mentorName}' : ''}',
                style: AppTypography.caption,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$pct%', style: AppTypography.cardTitle),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccess(BuildContext context, InternDashboardData data) {
    final standupDone = _todayStandup != null;

    void open(Widget screen) {
      _pushAndRefresh(MaterialPageRoute(builder: (_) => screen));
    }

    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          PastelCard(
            title: 'Attendance',
            icon: Icons.fingerprint_rounded,
            body: '${data.stats.effectiveDaysLogged} days logged so far',
            footer: 'Today',
            tag: data.todayAttendance.hasCheckedIn ? 'Checked in' : 'Not yet',
            tone: PastelTone.peach,
            onTap: () => open(const AttendanceHomeScreen()),
          ),
          const SizedBox(width: 12),
          PastelCard(
            title: 'Standup',
            icon: Icons.chat_bubble_outline_rounded,
            body: standupDone ? 'Your update is posted.' : 'What did you work on today?',
            footer: 'Today',
            tag: standupDone ? 'Submitted' : 'Pending',
            tone: PastelTone.lavender,
            onTap: () => open(const StandupScreen()),
          ),
          const SizedBox(width: 12),
          PastelCard(
            title: 'Projects',
            icon: Icons.folder_outlined,
            body: '${data.activeProjects.length} active, ${data.openTasks.length} open tasks',
            footer: 'Now',
            tag: 'Work',
            tone: PastelTone.sage,
            onTap: () => open(const ProjectsListScreen()),
          ),
          const SizedBox(width: 12),
          PastelCard(
            title: 'Leave',
            icon: Icons.beach_access_outlined,
            body: '${data.stats.pendingLeave} request(s) awaiting review',
            footer: 'This month',
            tag: 'Time off',
            tone: PastelTone.butter,
            onTap: () => open(const LeaveDashboardScreen()),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceHero(BuildContext context, InternTodayAttendance att, int streakDays) {
    final bool checkedIn = att.hasCheckedIn;
    final bool checkedOut = att.hasCheckedOut;

    String title;
    String subtitle;
    String ctaLabel;
    IconData ctaIcon;
    Widget illustration;

    if (!checkedIn) {
      title = "Let's start your day";
      subtitle = 'Clock in with camera verification & geofence.';
      ctaLabel = 'Check in now';
      ctaIcon = Icons.login_rounded;
      illustration = const SunriseIllustration(size: 84);
    } else if (!checkedOut) {
      title = "You're on shift";
      subtitle = 'Keep up the great work!';
      ctaLabel = 'Check out';
      ctaIcon = Icons.logout_rounded;
      illustration = Text(
        _elapsedTime.inSeconds > 0 ? _formatDuration(_elapsedTime) : '--:--:--',
        style: AppTypography.metric.copyWith(fontSize: 38, fontFeatures: const [FontFeature.tabularFigures()]),
      );
    } else {
      title = 'Day complete';
      subtitle = 'All shifts finished for today. Great effort!';
      ctaLabel = 'View day log';
      ctaIcon = Icons.fact_check_outlined;
      illustration = Text('${att.hoursWorked.toStringAsFixed(1)}h', style: AppTypography.metric.copyWith(fontSize: 40));
    }

    void openAttendance() {
      _pushAndRefresh(
        MaterialPageRoute(builder: (_) => const AttendanceHomeScreen()),
      );
    }

    return Column(
      children: [
        HeroBannerCard(
          title: title,
          subtitle: subtitle,
          illustration: illustration,
          height: 232,
          onTap: openAttendance,
          peekLabel: streakDays > 0 ? '$streakDays-day streak' : 'History',
          onPeekTap: openAttendance,
          footer: SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: openAttendance,
              icon: Icon(ctaIcon, size: 18),
              label: Text(ctaLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.ink,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ReferenceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              Row(
                children: [
                  _buildTimeCell('Check in', att.checkIn != null ? formatShortTime(att.checkIn!) : '--:--'),
                  _buildTimeCell('Check out', att.checkOut != null ? formatShortTime(att.checkOut!) : '--:--'),
                  _buildTimeCell('Hours', '${att.hoursWorked.toStringAsFixed(1)}h'),
                  if (att.checkInPhotoUrl != null && att.checkInPhotoUrl!.trim().isNotEmpty)
                    GestureDetector(
                      onTap: () => showPhotoModal(context, att.checkInPhotoUrl, 'Check-in Selfie'),
                      child: ClipOval(
                        child: Image.network(
                          att.checkInPhotoUrl!,
                          width: 38,
                          height: 38,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
              if (att.checkInAddress != null && att.checkInAddress!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        att.checkInAddress!,
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeCell(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.label),
          const SizedBox(height: 3),
          Text(value, style: AppTypography.bodyStrong),
        ],
      ),
    );
  }

  String formatShortTime(String raw) {
    if (raw.contains('T')) {
      final dt = DateTime.tryParse(raw);
      if (dt != null) return DateFormat('hh:mm a').format(dt);
    }
    return raw;
  }

  Widget _buildStatsStrip(
    InternDashboardStats stats,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    final pct = (stats.taskCompletionPercentage * 100).round();

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // 2 cols phone (<600), 3 cols tablet (<900), 5 cols wide
            int crossAxisCount = 2;
            if (constraints.maxWidth >= 900) {
              crossAxisCount = 5;
            } else if (constraints.maxWidth >= 600) {
              crossAxisCount = 3;
            }

            final items = [
              DashboardKpiCard(
                title: 'Total Hours',
                value: '${stats.totalHours.toStringAsFixed(1)}h',
                subtitle: 'Logged to date',
                icon: Icons.access_time_rounded,
                iconColor: AppColors.primary,
              ),
              DashboardKpiCard(
                title: 'Days Logged',
                value: '${stats.effectiveDaysLogged}',
                subtitle: 'Attendance active',
                icon: Icons.calendar_month_rounded,
                iconColor: AppColors.success,
              ),
              DashboardKpiCard(
                title: 'Tasks Done',
                value: '${stats.completedTasksCount}/${stats.assignedTasksCount}',
                subtitle: '$pct% completed',
                icon: Icons.task_alt_rounded,
                iconColor: AppColors.warning,
              ),
              DashboardKpiCard(
                title: 'Active Projects',
                value: '${stats.activeProjects}/${stats.totalProjects}',
                subtitle: 'Assigned batches',
                icon: Icons.folder_special_rounded,
                iconColor: AppColors.info,
              ),
              DashboardKpiCard(
                title: 'Pending Leaves',
                value: '${stats.pendingLeave}',
                subtitle: 'Awaiting review',
                icon: Icons.event_note_rounded,
                iconColor: AppColors.peachInk,
              ),
            ];

            return DashboardKpiGrid(items: items, columns: crossAxisCount);
          },
        ),
      ],
    );
  }

  Widget _buildChartsRow(InternDashboardData data) {
    final taskMap = data.taskStatus;
    final overdueCount = data.stats.overdueTasks;

    return Column(
      children: [
        if (overdueCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(AppSpacing.r16),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.dangerInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You have $overdueCount overdue task${overdueCount > 1 ? 's' : ''}. Please review deadlines.',
                    style: AppTypography.bodyStrong.copyWith(fontSize: 13, color: AppColors.dangerInk),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        DashboardTaskCapsules(
          title: 'My Tasks',
          taskStatus: taskMap,
        ),
        const SizedBox(height: 16),
        DashboardAttendanceChart(
          points: data.attendanceChart,
          title: 'Weekly Attendance Hours',
          subtitle: 'Daily distribution of worked hours',
        ),
      ],
    );
  }

  Widget _buildTasksList(
    List<InternDashboardTask> tasks,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tasks.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final t = tasks[index];

        Color priorityColor = AppColors.textSecondary;
        switch (t.priority.toLowerCase()) {
          case 'high':
          case 'urgent':
            priorityColor = AppColors.danger;
            break;
          case 'medium':
            priorityColor = AppColors.warning;
            break;
          case 'low':
            priorityColor = AppColors.success;
            break;
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.assignment_outlined, size: 20, color: priorityColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                    if (t.projectName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        t.projectName!,
                        style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: priorityColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            t.priority.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: priorityColor,
                            ),
                          ),
                        ),
                        if (t.effectiveDeadline != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.access_time_rounded, size: 12, color: secondaryTextColor),
                              const SizedBox(width: 4),
                              Text(
                                formatShortDate(t.effectiveDeadline),
                                style: TextStyle(fontSize: 11, color: secondaryTextColor),
                              ),
                            ],
                          ),
                        if (t.isOverdue)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'OVERDUE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProjectsList(
    List<InternDashboardProject> projects,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: projects.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final p = projects[index];
        final pct = (p.progress * 100).round();

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      p.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
              if (p.mentorName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Mentor: ${p.mentorName}',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tasks: ${p.completedTasksCount}/${p.myTasksCount}',
                    style: TextStyle(fontSize: 12, color: secondaryTextColor),
                  ),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p.progress,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnnouncementsList(
    List<DashboardAnnouncement> anns,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: anns.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final a = anns[index];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (a.isPinned) ...[
                    const Icon(Icons.push_pin, size: 14, color: AppColors.warning),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      a.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                  if (a.createdAt != null)
                    Text(
                      formatRelativeTime(a.createdAt),
                      style: TextStyle(fontSize: 11, color: secondaryTextColor),
                    ),
                ],
              ),
              if (a.effectiveContent.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  a.effectiveContent,
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeavesList(
    List<InternDashboardLeave> leaves,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: leaves.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final l = leaves[index];

        Color statusColor = AppColors.warning;
        if (l.status.toLowerCase() == 'approved') {
          statusColor = AppColors.success;
        } else if (l.status.toLowerCase() == 'rejected') {
          statusColor = AppColors.danger;
        }

        IconData leaveIcon = Icons.calendar_today_rounded;
        final type = l.leaveType.toLowerCase();
        if (type.contains('sick') || type.contains('medical')) {
          leaveIcon = Icons.local_hospital_outlined;
        } else if (type.contains('vacation') || type.contains('casual')) {
          leaveIcon = Icons.beach_access_rounded;
        }

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(leaveIcon, size: 18, color: AppColors.primaryInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${l.leaveType.toUpperCase()} LEAVE (${l.days} ${l.days > 1 ? 'days' : 'day'})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatShortDate(l.startDate)} → ${formatShortDate(l.endDate)}',
                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
