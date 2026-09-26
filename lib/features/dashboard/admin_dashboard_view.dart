import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/metric_header.dart';
import '../../shared/widgets/app_tag.dart';
import '../../core/constants/app_spacing.dart';
import '../directory_cohorts/user_management_screen.dart';
import '../projects_tasks/projects_list_screen.dart';
import '../attendance/attendance_home_screen.dart';
import '../activity_audit/activity_timeline_screen.dart';
import 'dashboard_repository.dart';
import 'models/dashboard_models.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/dashboard_shared.dart';

class AdminDashboardView extends ConsumerStatefulWidget {
  const AdminDashboardView({super.key});

  @override
  ConsumerState<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends ConsumerState<AdminDashboardView> {
  final DashboardRepository _repository = DashboardRepository();

  bool _isLoading = true;
  String? _errorMessage;
  AdminDashboardData? _dashboardData;
  final Set<int> _processingLeaveIds = {};

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await _repository.getAdminDashboard();
      if (mounted) {
        setState(() {
          _dashboardData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLeaveReview(int id, String decision) async {
    if (_processingLeaveIds.contains(id)) return;

    setState(() {
      _processingLeaveIds.add(id);
    });

    try {
      await _repository.reviewLeave(id, decision: decision);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'approved' ? 'Leave request approved' : 'Leave request rejected',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: decision == 'approved' ? AppColors.success : AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadDashboard();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update leave: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingLeaveIds.remove(id);
        });
      }
    }
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
            message: _errorMessage ?? 'Failed to load admin dashboard',
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
                // 1) HEADLINE METRIC
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Column(
                    children: [
                      AppTag(
                        label: '${data.organization.name}${data.organization.type != null ? " · ${data.organization.type}" : ""}',
                        icon: Icons.business_rounded,
                        color: AppColors.primaryInk,
                        background: AppColors.primarySoft,
                      ),
                      const SizedBox(height: 14),
                      MetricHeader(value: '${data.stats.presentToday}', subtitle: 'of ${data.stats.totalMembers} team members checked in today'),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const UserManagementScreen()),
                              );
                            },
                            icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                            label: const Text('Manage Team'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // 2) HERO PRESENCE & KPIS
                _buildHeroPresenceSection(data.stats, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 3) TEAM SIZE CARD
                _buildTeamSizeCard(data.stats, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 4) CHARTS (PROJECT STATUS & TASK STATUS)
                _buildChartsSection(data),
                const SizedBox(height: 20),

                // 5) PRESENT TODAY LIST
                DashboardSectionTitle(
                  title: 'Present Today',
                  count: data.presentTodayList.length,
                  actionLabel: 'All Logs →',
                  onAction: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AttendanceHomeScreen()),
                    );
                  },
                ),
                if (data.presentTodayList.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.people_outline_rounded,
                    title: 'No check-ins today yet',
                    subtitle: 'Team members clocking in today will appear here.',
                  )
                else
                  _buildPresentList(data.presentTodayList, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 6) ACTIVE PROJECTS
                DashboardSectionTitle(
                  title: 'Active Projects',
                  count: data.activeProjects.length,
                  actionLabel: 'All Projects →',
                  onAction: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProjectsListScreen()),
                    );
                  },
                ),
                if (data.activeProjects.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.folder_open_rounded,
                    title: 'No active projects',
                    subtitle: 'Create a new project batch to monitor progress.',
                  )
                else
                  _buildProjectsList(data.activeProjects, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 7) OPEN TASKS
                DashboardSectionTitle(
                  title: 'Open Tasks Across Organization',
                  count: data.openTasks.length,
                ),
                if (data.openTasks.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.task_alt_rounded,
                    title: 'No pending tasks',
                    subtitle: 'All organization tasks are completed.',
                  )
                else
                  _buildTasksList(data.openTasks, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 8) PENDING LEAVE REQUESTS
                DashboardSectionTitle(
                  title: 'Pending Leave Approvals',
                  count: data.pendingLeaveRequests.length,
                ),
                if (data.pendingLeaveRequests.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.event_available_rounded,
                    title: 'No pending leaves',
                    subtitle: 'All organization leave requests have been reviewed.',
                  )
                else
                  _buildPendingLeavesList(data.pendingLeaveRequests, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 9) RECENT ACTIVITY
                DashboardSectionTitle(
                  title: 'Organization Activity Timeline',
                  count: data.recentActivity.length,
                  actionLabel: 'Full Log →',
                  onAction: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ActivityTimelineScreen()),
                    );
                  },
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

  Widget _buildHeroPresenceSection(
    AdminDashboardStats stats,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {

    return Column(
      children: [
        DashboardPresenceCapsules(
          title: 'Attendance Today',
          subtitle: 'Live workforce presence across all cohorts',
          present: stats.presentToday,
          absent: stats.absentToday,
          onLeave: stats.onLeaveToday > 0 ? stats.onLeaveToday : stats.pendingLeave,
        ),
        const SizedBox(height: 12),
        // KPIs Grid
        LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount = 2;
            if (constraints.maxWidth >= 900) {
              crossAxisCount = 5;
            } else if (constraints.maxWidth >= 600) {
              crossAxisCount = 3;
            }

            final items = [
              DashboardKpiCard(
                title: 'Present Today',
                value: '${stats.presentToday}',
                subtitle: 'Clocked in',
                icon: Icons.check_circle_outline_rounded,
                iconColor: AppColors.success,
              ),
              DashboardKpiCard(
                title: 'Absent Today',
                value: '${stats.absentToday}',
                subtitle: 'Not logged in',
                icon: Icons.cancel_outlined,
                iconColor: AppColors.danger,
              ),
              DashboardKpiCard(
                title: 'On Leave',
                value: '${stats.onLeaveToday > 0 ? stats.onLeaveToday : stats.pendingLeave}',
                subtitle: 'Authorized leave',
                icon: Icons.event_note_rounded,
                iconColor: AppColors.warning,
              ),
              DashboardKpiCard(
                title: 'Days Logged',
                value: '${stats.daysLogged}',
                subtitle: 'Cumulative days',
                icon: Icons.calendar_month_rounded,
                iconColor: AppColors.primary,
              ),
              DashboardKpiCard(
                title: 'Total Hours',
                value: '${stats.totalHours.toStringAsFixed(1)}h',
                subtitle: 'Org hours worked',
                icon: Icons.timer_outlined,
                iconColor: AppColors.info,
              ),
            ];

            return DashboardKpiGrid(items: items, columns: crossAxisCount);
          },
        ),
      ],
    );
  }

  Widget _buildTeamSizeCard(
    AdminDashboardStats stats,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_rounded, size: 26, color: AppColors.primaryInk),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stats.totalMembers} Total Members',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stats.totalInterns} Interns · ${stats.totalMentors} Mentors',
                  style: TextStyle(fontSize: 13, color: secondaryTextColor),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UserManagementScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Directory'),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection(AdminDashboardData data) {
    final taskMap = data.taskStatus;
    final overdueCount = data.stats.overdueTasks;


    const projectColors = {
      'planning': DashboardChartColors.projectPlanning,
      'active': DashboardChartColors.projectActive,
      'completed': DashboardChartColors.projectCompleted,
      'on_hold': DashboardChartColors.projectOnHold,
      'onhold': DashboardChartColors.projectOnHold,
    };

    return Column(
      children: [
        DashboardAttendanceChart(
          points: data.attendanceChart,
          title: 'Organization Attendance Trends',
          subtitle: 'Daily cumulative hours logged',
        ),
        const SizedBox(height: 16),
        DashboardStatusDistributionBar(
          title: 'Project Pipeline Status',
          statusCounts: data.projectStatus,
          colorMap: projectColors,
        ),
        const SizedBox(height: 16),
        DashboardTaskCapsules(
          title: 'Tasks Across Projects',
          taskStatus: taskMap,
          overdue: overdueCount,
        ),
      ],
    );
  }

  Widget _buildPresentList(
    List<AdminDashboardPresentIntern> presentList,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: presentList.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final intern = presentList[index];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (intern.checkInPhotoUrl != null) {
                    showPhotoModal(context, intern.checkInPhotoUrl, '${intern.name} Check-in Photo');
                  }
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: (intern.checkInPhotoUrl != null && intern.checkInPhotoUrl!.trim().isNotEmpty)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(21),
                          child: Image.network(
                            intern.checkInPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Text(getInitials(intern.name), style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            getInitials(intern.name),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      intern.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      intern.department ?? intern.email,
                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'IN ${intern.checkIn ?? "--:--"}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${intern.hoursWorked.toStringAsFixed(1)}h',
                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProjectsList(
    List<AdminDashboardProject> projects,
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
                      borderRadius: BorderRadius.circular(8),
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
                  'Lead Mentor: ${p.mentorName}',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Members: ${p.membersCount} · Tasks: ${p.completedTasksCount}/${p.tasksCount}',
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

  Widget _buildTasksList(
    List<MentorDashboardTask> tasks,
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
        if (t.priority.toLowerCase() == 'high' || t.priority.toLowerCase() == 'urgent') {
          priorityColor = AppColors.danger;
        } else if (t.priority.toLowerCase() == 'medium') {
          priorityColor = AppColors.warning;
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
                    const SizedBox(height: 2),
                    Text(
                      '${t.projectName ?? 'General'} · Assignee: ${t.assignedUserName ?? 'Unassigned'}',
                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                    ),
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
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: priorityColor),
                          ),
                        ),
                        if (t.deadline != null)
                          Text(
                            formatShortDate(t.deadline),
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
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
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.danger),
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

  Widget _buildPendingLeavesList(
    List<MentorDashboardLeaveRequest> leaves,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: leaves.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final l = leaves[index];
        final isProcessing = _processingLeaveIds.contains(l.id);

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
                      l.userName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${l.leaveType.toUpperCase()} (${l.days}d)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${formatShortDate(l.startDate)} → ${formatShortDate(l.endDate)}',
                style: TextStyle(fontSize: 12, color: secondaryTextColor),
              ),
              if (l.reason != null && l.reason!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '"${l.reason}"',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: secondaryTextColor),
                ),
              ],
              const SizedBox(height: 14),
              if (isProcessing)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _handleLeaveReview(l.id, 'rejected'),
                        icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
                        label: const Text('Reject', style: TextStyle(color: AppColors.danger)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.danger),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleLeaveReview(l.id, 'approved'),
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
