import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/metric_header.dart';
import '../../shared/widgets/app_tag.dart';
import '../directory_cohorts/user_management_screen.dart';
import '../projects_tasks/project_detail_screen.dart';
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

  /// [silent] keeps the current content on screen while refreshing.
  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent || _dashboardData == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _repository.getAdminDashboard();
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

  Future<void> _pushNamed(String name) async {
    await Navigator.of(context).pushNamed(name);
    if (mounted) await _loadDashboard(silent: true);
  }

  void _openProject(int id) => _push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: id)));

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
                      if (data.organization.name.isNotEmpty) ...[
                        AppTag(
                          label: '${data.organization.name}${data.organization.type != null ? " · ${humanize(data.organization.type)}" : ""}',
                          icon: Icons.business_rounded,
                          color: AppColors.primaryInk,
                          background: AppColors.primarySoft,
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Attendance counts cover interns only, so the headline does too.
                      MetricHeader(
                        value: '${data.stats.presentToday}',
                        subtitle: 'of ${plural(data.stats.totalInterns, 'intern')} checked in today',
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _push(MaterialPageRoute(builder: (_) => const UserManagementScreen())),
                        icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                        label: const Text('Manage users'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                _buildHeroPresenceSection(data.stats),
                const SizedBox(height: 20),

                _buildTeamSizeCard(data.stats),
                const SizedBox(height: 20),

                _buildChartsSection(data),
                const SizedBox(height: 20),

                DashboardSectionTitle(
                  title: 'Checked in today',
                  count: data.presentTodayList.length,
                  actionLabel: 'See all',
                  onAction: () => _goToTab(MainTab.attendance),
                ),
                if (data.presentTodayList.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.people_outline_rounded,
                    title: 'No check-ins yet today',
                    subtitle: 'Interns appear here as they check in.',
                  )
                else
                  _buildPresentList(data.presentTodayList),
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
                    subtitle: 'Active projects and their progress show here.',
                  )
                else
                  Column(
                    children: [
                      for (final p in data.activeProjects) ...[
                        DashboardProjectTile(
                          name: p.name,
                          status: p.status,
                          subtitle: p.mentorName != null ? 'Mentor: ${p.mentorName}' : null,
                          membersCount: p.membersCount,
                          completedTasks: p.completedTasksCount,
                          totalTasks: p.tasksCount,
                          progress: p.progress,
                          onTap: () => _openProject(p.id),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),

                DashboardSectionTitle(
                  title: 'Open tasks',
                  count: data.openTasks.length,
                ),
                if (data.openTasks.isEmpty)
                  DashboardEmptyCard(
                    icon: Icons.task_alt_rounded,
                    title: 'No open tasks',
                    subtitle: 'Every task in your organization is done.',
                  )
                else
                  Column(
                    children: [
                      for (final t in data.openTasks) ...[
                        DashboardTaskTile(
                          task: t,
                          onTap: t.projectId == null ? null : () => _openProject(t.projectId!),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                const SizedBox(height: 10),

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
                    subtitle: 'New leave requests show up here.',
                  )
                else
                  Column(
                    children: [
                      for (final l in data.pendingLeaveRequests) ...[
                        DashboardLeaveReviewCard(
                          leave: l,
                          busy: _processingLeaveIds.contains(l.id),
                          onApprove: () => _handleLeaveReview(l, 'approved'),
                          onReject: () => _handleLeaveReview(l, 'rejected'),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),

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

  Widget _buildHeroPresenceSection(AdminDashboardStats stats) {
    return Column(
      children: [
        // Present / absent / on leave live here once; the KPIs below cover everything else.
        DashboardPresenceCapsules(
          title: "Today's attendance",
          subtitle: 'All interns in your organization',
          present: stats.presentToday,
          absent: stats.absentToday,
          onLeave: stats.onLeaveToday,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 900 ? 4 : 2;

            final items = [
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
                subtitle: 'Waiting for a decision',
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

  Widget _buildTeamSizeCard(AdminDashboardStats stats) {
    return DashboardTile(
      onTap: () => _pushNamed('/team'),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
            child: const Icon(Icons.groups_rounded, size: 26, color: AppColors.primaryInk),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plural(stats.totalMembers, 'member'),
                  style: AppTypography.section.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${plural(stats.totalInterns, 'intern')} · ${plural(stats.totalMentors, 'mentor')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('Directory', style: AppTypography.bodyStrong.copyWith(color: AppColors.primaryInk)),
          const Icon(Icons.chevron_right_rounded, color: AppColors.primaryInk),
        ],
      ),
    );
  }

  Widget _buildChartsSection(AdminDashboardData data) {
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
          subtitle: 'Hours worked each day, last 30 days',
        ),
        const SizedBox(height: 16),
        DashboardStatusDistributionBar(
          title: 'Projects by status',
          statusCounts: data.projectStatus,
          colorMap: projectColors,
        ),
        const SizedBox(height: 16),
        DashboardTaskCapsules(
          title: 'Tasks by status',
          taskStatus: data.taskStatus,
          overdue: data.stats.overdueTasks,
        ),
      ],
    );
  }

  Widget _buildPresentList(List<AdminDashboardPresentIntern> presentList) {
    return Column(
      children: [
        for (final intern in presentList) ...[
          DashboardTile(
            onTap: () => _pushNamed('/attendance/${intern.userId}'),
            child: Row(
              children: [
                GestureDetector(
                  onTap: intern.checkInPhotoUrl == null
                      ? null
                      : () => showPhotoModal(context, intern.checkInPhotoUrl, '${intern.name} · check-in photo'),
                  child: AppAvatar(url: intern.checkInPhotoUrl, fallbackText: intern.name, size: 42),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        intern.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        intern.department ?? intern.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatTime(intern.checkIn, fallback: '—'),
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.successInk),
                    ),
                    const SizedBox(height: 2),
                    Text(formatHours(intern.hoursWorked), style: AppTypography.label),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
