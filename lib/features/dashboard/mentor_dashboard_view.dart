import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/metric_header.dart';
import '../../core/constants/app_spacing.dart';
import '../attendance/attendance_home_screen.dart';
import '../projects_tasks/projects_list_screen.dart';
import '../activity_audit/activity_timeline_screen.dart';
import 'dashboard_repository.dart';
import 'models/dashboard_models.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/dashboard_shared.dart';

class MentorDashboardView extends ConsumerStatefulWidget {
  const MentorDashboardView({super.key});

  @override
  ConsumerState<MentorDashboardView> createState() => _MentorDashboardViewState();
}

class _MentorDashboardViewState extends ConsumerState<MentorDashboardView> {
  final DashboardRepository _repository = DashboardRepository();

  bool _isLoading = true;
  String? _errorMessage;
  MentorDashboardData? _dashboardData;
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
      final data = await _repository.getMentorDashboard();
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
            message: _errorMessage ?? 'Failed to load mentor dashboard',
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
                      MetricHeader(value: '${data.stats.presentToday}', subtitle: 'of ${data.stats.assignedInternsCount} interns checked in today'),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const AttendanceHomeScreen()),
                              );
                            },
                            icon: const Icon(Icons.co_present_outlined, size: 16),
                            label: const Text('Attendance'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ProjectsListScreen()),
                              );
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('New Project'),
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
                _buildHeroPresenceStrip(data.stats, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 3) CHARTS
                _buildChartsSection(data),
                const SizedBox(height: 20),

                // 4) ASSIGNED INTERNS GRID
                DashboardSectionTitle(
                  title: 'Assigned Interns',
                  count: data.assignedInterns.length,
                  actionLabel: 'All Attendance →',
                  onAction: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AttendanceHomeScreen()),
                    );
                  },
                ),
                if (data.assignedInterns.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.people_outline_rounded,
                    title: 'No interns assigned',
                    subtitle: 'Interns assigned to your cohorts will appear here.',
                  )
                else
                  _buildInternsGrid(data.assignedInterns, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 5) ACTIVE PROJECTS
                DashboardSectionTitle(
                  title: 'Active Projects',
                  count: data.activeProjects.length,
                  actionLabel: 'Manage All →',
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
                    subtitle: 'Create a new sprint project to get started.',
                    actionLabel: 'Create Project',
                    onAction: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProjectsListScreen()),
                      );
                    },
                  )
                else
                  _buildProjectsList(data.activeProjects, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 6) OPEN & OVERDUE TASKS
                DashboardSectionTitle(
                  title: 'Team Open Tasks',
                  count: data.openTasks.length,
                ),
                if (data.openTasks.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.task_alt_rounded,
                    title: 'No open tasks',
                    subtitle: 'All assigned tasks have been completed.',
                  )
                else
                  _buildTasksList(data.openTasks, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 7) PENDING LEAVE REQUESTS
                DashboardSectionTitle(
                  title: 'Pending Leave Approvals',
                  count: data.pendingLeaveRequests.length,
                ),
                if (data.pendingLeaveRequests.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.event_available_rounded,
                    title: 'No pending leave requests',
                    subtitle: 'All leave requests from your interns are processed.',
                  )
                else
                  _buildPendingLeavesList(data.pendingLeaveRequests, cardBg, borderColor, primaryTextColor, secondaryTextColor),
                const SizedBox(height: 20),

                // 8) RECENT ACTIVITY
                DashboardSectionTitle(
                  title: 'Recent Activity',
                  count: data.recentActivity.length,
                  actionLabel: 'View Full Timeline →',
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

  Widget _buildHeroPresenceStrip(
    MentorDashboardStats stats,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {

    return Column(
      children: [
        DashboardPresenceCapsules(
          title: "Today's Attendance",
          subtitle: 'Real-time check-in presence overview',
          present: stats.presentToday,
          absent: stats.absentToday,
          onLeave: stats.pendingLeave,
        ),
        const SizedBox(height: 12),
        // KPI Strip
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
                title: 'Assigned Interns',
                value: '${stats.assignedInternsCount}',
                subtitle: 'Active cohort roster',
                icon: Icons.people_alt_rounded,
                iconColor: AppColors.primary,
              ),
              DashboardKpiCard(
                title: 'Active Projects',
                value: '${stats.activeProjects}/${stats.totalProjects}',
                subtitle: 'In sprint progress',
                icon: Icons.folder_special_rounded,
                iconColor: AppColors.info,
              ),
              DashboardKpiCard(
                title: 'Open Tasks',
                value: '${stats.openTasks}',
                subtitle: stats.overdueTasks > 0 ? '⚠️ ${stats.overdueTasks} overdue' : 'On schedule',
                icon: Icons.assignment_turned_in_rounded,
                iconColor: stats.overdueTasks > 0 ? AppColors.danger : AppColors.success,
              ),
              DashboardKpiCard(
                title: 'Total Hours',
                value: '${stats.totalHours.toStringAsFixed(1)}h',
                subtitle: 'Logged across team',
                icon: Icons.timer_outlined,
                iconColor: AppColors.warning,
              ),
              DashboardKpiCard(
                title: 'Pending Leaves',
                value: '${stats.pendingLeave}',
                subtitle: 'Awaiting your approval',
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

  Widget _buildChartsSection(MentorDashboardData data) {
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
          title: 'Intern Attendance Hours',
          subtitle: 'Daily cumulative team hours worked',
        ),
        const SizedBox(height: 16),
        DashboardStatusDistributionBar(
          title: 'Projects by Status',
          statusCounts: data.projectStatus,
          colorMap: projectColors,
        ),
        const SizedBox(height: 16),
        DashboardTaskCapsules(
          title: 'Intern Tasks',
          taskStatus: taskMap,
          overdue: overdueCount,
        ),
      ],
    );
  }

  Widget _buildInternsGrid(
    List<MentorDashboardIntern> interns,
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int cols = 1;
        if (constraints.maxWidth >= 900) {
          cols = 3;
        } else if (constraints.maxWidth >= 600) {
          cols = 2;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: interns.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: cols == 1 ? 2.6 : 1.6,
          ),
          itemBuilder: (context, index) {
            final intern = interns[index];
            final bool isPresent = intern.isPresent;
            final Color statusColor = isPresent ? AppColors.success : AppColors.textTertiary;

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (intern.checkInPhotoUrl != null) {
                            showPhotoModal(context, intern.checkInPhotoUrl, '${intern.name} Check-in Photo');
                          }
                        },
                        child: Stack(
                          children: [
                            Container(
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
                                          child: Text(
                                            getInitials(intern.name),
                                            style: TextStyle(fontWeight: FontWeight.w700),
                                          ),
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
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: cardBg, width: 2),
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
                              intern.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: primaryTextColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              intern.department ?? intern.email,
                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                          intern.todayStatus.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Metrics footer
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        intern.checkIn != null ? 'In: ${intern.checkIn}' : 'Not logged',
                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                      ),
                      Text(
                        '${intern.hoursWorked.toStringAsFixed(1)}h worked',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                      if (intern.streak > 0)
                        Text(
                          '🔥 ${intern.streak}d',
                          style: const TextStyle(fontSize: 11, color: AppColors.warning),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProjectsList(
    List<MentorDashboardProject> projects,
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
              if (p.description != null && p.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  p.description!,
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                      '${t.projectName ?? 'General'} · Assigned to: ${t.assignedUserName ?? 'Unassigned'}',
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
              // Action Buttons
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
