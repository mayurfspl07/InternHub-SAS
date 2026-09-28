import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/metric_header.dart';
import '../../core/utils/formatters.dart';
import '../projects_tasks/project_detail_screen.dart';
import '../projects_tasks/project_form_dialog.dart';
import '../activity_audit/activity_timeline_screen.dart';
import 'dashboard_repository.dart';
import 'main_navigation_wrapper.dart';
import 'models/dashboard_models.dart';
import 'widgets/dashboard_charts.dart';
import 'widgets/dashboard_shared.dart';
import 'widgets/dashboard_tiles.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/status_chip.dart';

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

  /// [silent] keeps the current content on screen while refreshing.
  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent || _dashboardData == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _repository.getMentorDashboard();
      if (mounted) {
        setState(() {
          _dashboardData = data;
          _errorMessage = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (silent && _dashboardData != null) {
        showApiError(context, e, prefix: "Couldn't refresh");
      } else {
        setState(() {
          _errorMessage = apiErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  void _goToTab(int tab) => ref.read(mainTabProvider.notifier).state = tab;

  Future<void> _push(Route<dynamic> route) async {
    await Navigator.of(context).push(route);
    if (mounted) await _loadDashboard(silent: true);
  }

  void _openProject(int id) => _push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: id)));

  void _openInternAttendance(MentorDashboardIntern intern) async {
    await Navigator.of(context).pushNamed('/attendance/${intern.userId}');
    if (mounted) await _loadDashboard(silent: true);
  }

  void _createProject() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProjectFormDialog(onSuccess: () => _loadDashboard(silent: true)),
    );
  }

  Future<void> _handleLeaveReview(MentorDashboardLeaveRequest leave, String decision) async {
    if (_processingLeaveIds.contains(leave.id)) return;

    String? comment;
    if (decision == 'rejected') {
      comment = await askRejectReason(context, leave.userName);
      if (comment == null || !mounted) return;
    }

    setState(() => _processingLeaveIds.add(leave.id));
    try {
      await _repository.reviewLeave(leave.id, decision: decision, comment: comment);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(decision == 'approved' ? 'Leave approved' : 'Leave rejected'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        await _loadDashboard(silent: true);
      }
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't update the leave request");
    } finally {
      if (mounted) setState(() => _processingLeaveIds.remove(leave.id));
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
            message: _errorMessage ?? "Couldn't load your dashboard",
            onRetry: _loadDashboard,
          ),
        ),
      );
    }

    final data = _dashboardData!;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadDashboard(silent: true),
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: Column(
                    children: [
                      MetricHeader(
                        value: '${data.stats.presentToday}',
                        subtitle: 'of ${plural(data.stats.assignedInternsCount, 'intern')} checked in today',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _goToTab(MainTab.attendance),
                            icon: const Icon(Icons.co_present_outlined, size: 16),
                            label: const Text('Attendance'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: const StadiumBorder(),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _createProject,
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('New project'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: const StadiumBorder(),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                _buildHeroPresenceStrip(data.stats),
                const SizedBox(height: 20),

                _buildChartsSection(data),
                const SizedBox(height: 20),

                DashboardSectionTitle(
                  title: 'My interns',
                  count: data.assignedInterns.length,
                  actionLabel: 'See all',
                  onAction: () => _goToTab(MainTab.attendance),
                ),
                if (data.assignedInterns.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.people_outline_rounded,
                    title: 'No interns assigned',
                    subtitle: 'Interns in your cohorts will appear here.',
                  )
                else
                  _buildInternsGrid(data.assignedInterns),
                const SizedBox(height: 20),

                DashboardSectionTitle(
                  title: 'Active projects',
                  count: data.activeProjects.length,
                  actionLabel: 'See all',
                  onAction: () => _goToTab(MainTab.projects),
                ),
                if (data.activeProjects.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.folder_open_rounded,
                    title: 'No active projects',
                    subtitle: 'Create a project to start assigning tasks.',
                    actionLabel: 'New project',
                    onAction: _createProject,
                  )
                else
                  _buildProjectsList(data.activeProjects),
                const SizedBox(height: 20),

                DashboardSectionTitle(
                  title: 'Open tasks',
                  count: data.openTasks.length,
                ),
                if (data.openTasks.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.task_alt_rounded,
                    title: 'No open tasks',
                    subtitle: 'Every assigned task is done.',
                  )
                else
                  _buildTasksList(data.openTasks),
                const SizedBox(height: 20),

                DashboardSectionTitle(
                  title: 'Leave to review',
                  count: data.pendingLeaveRequests.length,
                  actionLabel: 'See all',
                  onAction: () => _goToTab(MainTab.leave),
                ),
                if (data.pendingLeaveRequests.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.event_available_rounded,
                    title: 'Nothing to review',
                    subtitle: "New leave requests from your interns show up here.",
                  )
                else
                  _buildPendingLeavesList(data.pendingLeaveRequests),
                const SizedBox(height: 20),

                DashboardSectionTitle(
                  title: 'Recent activity',
                  count: data.recentActivity.length,
                  actionLabel: 'See all',
                  onAction: () => _push(MaterialPageRoute(builder: (_) => const ActivityTimelineScreen())),
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

  Widget _buildHeroPresenceStrip(MentorDashboardStats stats) {
    return Column(
      children: [
        DashboardPresenceCapsules(
          title: "Today's attendance",
          subtitle: 'Your interns right now',
          present: stats.presentToday,
          absent: stats.absentToday,
          onLeave: stats.onLeaveToday,
        ),
        const SizedBox(height: 12),
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
                title: 'Interns',
                value: '${stats.assignedInternsCount}',
                subtitle: 'In your cohorts',
                icon: Icons.people_alt_rounded,
                iconColor: AppColors.primaryInk,
              ),
              DashboardKpiCard(
                title: 'Active projects',
                value: '${stats.activeProjects}/${stats.totalProjects}',
                subtitle: 'Active of total',
                icon: Icons.folder_special_rounded,
                iconColor: AppColors.infoInk,
              ),
              DashboardKpiCard(
                title: 'Open tasks',
                value: '${stats.openTasks}',
                subtitle: stats.overdueTasks > 0 ? '${stats.overdueTasks} overdue' : 'None overdue',
                icon: stats.overdueTasks > 0 ? Icons.warning_amber_rounded : Icons.assignment_turned_in_rounded,
                iconColor: stats.overdueTasks > 0 ? AppColors.dangerInk : AppColors.successInk,
              ),
              DashboardKpiCard(
                title: 'Hours logged',
                value: formatHours(stats.totalHours),
                subtitle: 'Last 30 days',
                icon: Icons.timer_outlined,
                iconColor: AppColors.warningInk,
              ),
              DashboardKpiCard(
                title: 'Leave to review',
                value: '${stats.pendingLeave}',
                subtitle: 'Waiting for you',
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
          title: 'Intern hours',
          subtitle: 'Hours your interns worked each day, last 30 days',
        ),
        const SizedBox(height: 16),
        DashboardStatusDistributionBar(
          title: 'Projects by status',
          statusCounts: data.projectStatus,
          colorMap: projectColors,
        ),
        const SizedBox(height: 16),
        DashboardTaskCapsules(
          title: 'Intern tasks',
          taskStatus: data.taskStatus,
          overdue: data.stats.overdueTasks,
        ),
      ],
    );
  }

  Widget _buildInternsGrid(List<MentorDashboardIntern> interns) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 900 ? 3 : (constraints.maxWidth >= 600 ? 2 : 1);
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (cols - 1)) / cols;

        // Wrap instead of a fixed-ratio grid so cards grow with larger text.
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final intern in interns) SizedBox(width: width, child: _internCard(intern))],
        );
      },
    );
  }

  Widget _internCard(MentorDashboardIntern intern) {
    final checkIn = formatTime(intern.checkIn);
    final status = intern.todayStatus.toLowerCase();
    return DashboardTile(
      onTap: () => _openInternAttendance(intern),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: intern.checkInPhotoUrl == null
                    ? null
                    : () => showPhotoModal(context, intern.checkInPhotoUrl, '${intern.name} · check-in photo'),
                child: AppAvatar(url: intern.checkInPhotoUrl, fallbackText: getInitials(intern.name), size: 42),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      intern.name,
                      style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      intern.department ?? intern.email,
                      style: AppTypography.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip.fromString(status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(checkIn.isEmpty ? 'No check-in yet' : 'In at $checkIn', style: AppTypography.label),
              Text('${formatHours(intern.hoursWorked)} today', style: AppTypography.label.copyWith(color: AppColors.ink)),
              if (intern.openTasksCount > 0) Text(plural(intern.openTasksCount, 'open task'), style: AppTypography.label),
              if (intern.streak > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_fire_department_rounded, size: 14, color: AppColors.warningInk),
                    const SizedBox(width: 2),
                    Text('${plural(intern.streak, 'day')} streak', style: AppTypography.label.copyWith(color: AppColors.warningInk)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProjectsList(List<MentorDashboardProject> projects) {
    return Column(
      children: [
        for (final p in projects) ...[
          DashboardProjectTile(
            name: p.name,
            status: p.status,
            subtitle: p.description,
            membersCount: p.membersCount,
            completedTasks: p.completedTasksCount,
            totalTasks: p.tasksCount,
            progress: p.progress,
            onTap: () => _openProject(p.id),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildTasksList(List<MentorDashboardTask> tasks) {
    return Column(
      children: [
        for (final t in tasks) ...[
          DashboardTaskTile(
            task: t,
            onTap: t.projectId == null ? null : () => _openProject(t.projectId!),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildPendingLeavesList(List<MentorDashboardLeaveRequest> leaves) {
    return Column(
      children: [
        for (final l in leaves) ...[
          DashboardLeaveReviewCard(
            leave: l,
            busy: _processingLeaveIds.contains(l.id),
            onApprove: () => _handleLeaveReview(l, 'approved'),
            onReject: () => _handleLeaveReview(l, 'rejected'),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
