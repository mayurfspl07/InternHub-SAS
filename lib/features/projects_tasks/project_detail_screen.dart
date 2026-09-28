import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../activity_audit/activity_repository.dart';
import '../activity_audit/models/activity_models.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import 'task_form_dialog.dart';
import 'project_form_dialog.dart';
import 'task_detail_screen.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/status_chip.dart';
import '../../core/utils/formatters.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final ProjectModel? project;
  final int? projectId;

  const ProjectDetailScreen({
    super.key,
    this.project,
    this.projectId,
  }) : assert(project != null || projectId != null, 'Either project or projectId must be provided');

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  late ProjectModel _project;

  List<TaskModel> _tasks = [];
  List<ProjectComment> _comments = [];
  List<ProjectLink> _links = [];
  List<TaskStatusColumn> _taskStatuses = [];
  bool _isLoading = true;
  // After the first load, reloads keep the page on screen (no spinner, scroll kept).
  bool _hasLoaded = false;
  bool _refreshing = false;
  String? _loadError;
  List<AuditLogEntry> _activity = const [];

  // View state: 'board' or 'list'
  String _taskViewMode = 'board';

  // Task Filter state
  String _taskFilterText = '';
  String _taskPriorityFilter = 'all'; // all | low | medium | high
  String _taskAssigneeFilter = 'all'; // all | unassigned | member_id

  final TextEditingController _commentInputController = TextEditingController();
  bool _isPostingComment = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project ??
        ProjectModel(
          id: widget.projectId?.toString() ?? '',
          name: 'Loading...',
          title: 'Loading...',
          status: 'in_progress',
          startDate: DateTime.now(),
          endDate: DateTime.now(),
          deadline: DateTime.now(),
          mentorName: '',
          createdAt: DateTime.now(),
        );
    _loadProjectData();
  }

  @override
  void dispose() {
    _commentInputController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectData() async {
    setState(() {
      if (_hasLoaded) {
        _refreshing = true;
      } else {
        _isLoading = true;
      }
      _loadError = null;
    });
    final targetId = widget.project?.id ?? widget.projectId?.toString() ?? _project.id;
    try {
      final results = await Future.wait([
        ApiClient().get('/api/projects/$targetId'),
        ApiClient().get('/api/projects/$targetId/links'),
        ApiClient().get('/api/projects/$targetId/comments-board'),
        ApiClient().get('/api/projects/$targetId/task-statuses'),
      ]);

      List<Map<String, dynamic>> maps(dynamic v) =>
          v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

      final projRes = results[0];
      if (projRes is Map<String, dynamic>) {
        _project = ProjectModel.fromJson(projRes);
        _tasks = _project.tasks;
      }
      // links and comments-board return lists; task-statuses returns {statuses: [...]}
      final linkList = maps(results[1]).map(ProjectLink.fromJson).toList();
      final commentList = maps(results[2]).map(ProjectComment.fromJson).toList();
      final statusCols = maps(results[3] is Map ? (results[3] as Map)['statuses'] : null)
          .map(TaskStatusColumn.fromJson)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      if (mounted) {
        setState(() {
          _links = linkList;
          _comments = commentList;
          _taskStatuses = statusCols;
          _isLoading = false;
          _refreshing = false;
          _hasLoaded = true;
        });
      }
      _loadActivity(targetId);
    } catch (e) {
      if (!mounted) return;
      if (_hasLoaded) {
        // Keep what's on screen; just say the refresh failed.
        setState(() => _refreshing = false);
        showApiError(context, e, prefix: "Couldn't refresh the project");
      } else {
        setState(() {
          _isLoading = false;
          _loadError = apiErrorMessage(e);
        });
      }
    }
  }

  /// The project's real audit trail (GET /api/audit?project_id=).
  Future<void> _loadActivity(String projectId) async {
    final id = int.tryParse(projectId);
    if (id == null) return;
    try {
      final res = await ActivityRepository().fetchAudit(projectId: id);
      if (mounted) setState(() => _activity = res.logs.take(6).toList());
    } catch (_) {
      // Activity is secondary: the section simply stays empty when it can't load.
      if (mounted) setState(() => _activity = const []);
    }
  }

  // ========================================
  // ACTIONS & DIALOGS
  // ========================================

  Future<void> _exportProject() async {
    try {
      await FileExportService.downloadAndShare(
        endpoint: '/api/projects/${_project.id}/export',
        defaultFileName: '${_project.name.replaceAll(' ', '_')}_export.xlsx',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to export project.')),
        );
      }
    }
  }

  void _confirmDeleteProject() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r20)),
        title: const Text('Delete this project?'),
        content: Text('"${_project.name}" and its tasks move to the recycle bin, where an admin can restore them.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.surface,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ApiClient().delete('/api/projects/${_project.id}');
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Project deleted successfully!')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete project: ${apiErrorMessage(e)}')),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openEditProjectDialog() {
    // Open edit dialog preloaded with project data
    _showProjectFormDialog(isEdit: true);
  }

  void _showProjectFormDialog({required bool isEdit}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProjectFormDialog(
        projectToEdit: isEdit ? _project : null,
        onSuccess: _loadProjectData,
      ),
    );
  }

  // Assign intern dialog
  // GET /api/projects/interns?page=1&page_size=30&search={q?} (filter out users already in project.members)
  // POST /api/projects/{id}/assign with { "user_id": 41 }
  void _openAssignInternDialog() {
    final existingIds = _project.members.map((m) => m['id']?.toString()).toSet();
    showDialog(
      context: context,
      builder: (_) => _AssignInternDialog(
        projectId: _project.id,
        projectName: _project.name,
        excludeIds: existingIds,
        onAssigned: () {
          _loadProjectData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Intern added to the project')));
          }
        },
      ),
    );
  }

  // Unassign Intern Dialog
  // Pick from project.members, then confirm; DELETE /api/projects/{id}/assign/{userId}
  void _openUnassignInternDialog() {
    final interns = _project.members.where((m) => m['role'] == null || m['role'].toString().toLowerCase() == 'intern').toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: const Text('Remove an intern'),
        content: SizedBox(
          width: 360,
          child: interns.isEmpty
              ? const Text('No interns are on this project.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: interns.length,
                  itemBuilder: (_, i) {
                    final intern = interns[i];
                    final name = intern['name']?.toString() ?? 'Intern';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: AppAvatar(size: 36, fallbackText: name),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(intern['email']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.remove_circle_outline, color: AppColors.dangerInk),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (c) => AlertDialog(
                            title: Text('Remove $name?'),
                            content: const Text('They will no longer see this project or its tasks.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.danger,
                                  foregroundColor: AppColors.surface,
                                ),
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        try {
                          await ApiClient().delete('/api/projects/${_project.id}/assign/${intern['id']}');
                          _loadProjectData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name removed from the project')));
                          }
                        } catch (e) {
                          if (mounted) showApiError(context, e, prefix: "Couldn't remove $name");
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // Project Links Manager Modal
  void _openLinksModal() {
    final user = ref.read(appStateProvider).currentUser;
    showDialog(
      context: context,
      builder: (_) => _ProjectLinksDialog(
        projectId: _project.id,
        initialLinks: _links,
        // DELETE /api/projects/links/{id} is admin/mentor only.
        canDelete: user.role != UserRole.intern,
        onChanged: (links) => setState(() => _links = links),
      ),
    );
  }

  // Create Task Modal
  void _openCreateTaskModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TaskFormDialog(
        project: _project,
        onTaskCreated: () {
          _loadProjectData();
        },
      ),
    );
  }

  // Post Board Comment
  Future<void> _postBoardComment() async {
    final text = _commentInputController.text.trim();
    if (text.isEmpty) return;


    setState(() => _isPostingComment = true);
    try {
      await ApiClient().post('/api/projects/${_project.id}/comments-board', body: {'body': text});
      _commentInputController.clear();
      final updated = await ApiClient().get('/api/projects/${_project.id}/comments-board');
      List<ProjectComment> commList = [];
      if (updated is List) {
        commList = updated.whereType<Map<String, dynamic>>().map((c) => ProjectComment.fromJson(c)).toList();
      }
      if (mounted) {
        setState(() {
          _comments = commList;
          _isPostingComment = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPostingComment = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to post comment: ${apiErrorMessage(e)}')));
      }
    }
  }

  // Recent activity from the audit log, newest first.
  List<Map<String, String>> _activityItems() {
    return _activity.map((e) {
      final when = DateTime.tryParse(e.createdAt)?.toLocal();
      final icon = e.action.startsWith('project')
          ? 'folder'
          : (e.action.contains('status') || e.action.contains('complete') ? 'check' : 'task');
      return {
        'title': '${e.actorName} ${e.verb}${e.target.isNotEmpty ? ' "${e.target}"' : ''}',
        'time': when == null ? '' : formatRelative(when),
        'icon': icon,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    if (_isLoading && !_hasLoaded) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: pageAppBar(context, title: 'Project'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: pageAppBar(context, title: 'Project'),
        body: LoadErrorView(title: "Couldn't load this project", message: _loadError!, onRetry: _loadProjectData),
      );
    }

    // Permissions:
    // canEditProject: project.can_edit == true AND role != intern
    final canEditProject = _project.canEdit && user.role != UserRole.intern;
    // canManageTasks: admin OR mentor OR (intern AND user is in project.members)
    final isMember = _project.memberIds.contains(user.id) || _project.members.any((m) => m['id']?.toString() == user.id);
    final canManageTasks = user.role == UserRole.admin || user.role == UserRole.mentor || user.role == UserRole.superadmin || (user.role == UserRole.intern && isMember);

    // Progress formula:
    final doneTasks = _project.taskDone;
    final totalTasks = _project.taskTotal;
    final progressInt = (_project.progress * 100).round().clamp(0, 100);

    // Filter tasks
    final filteredTasks = _tasks.where((t) {
      if (_taskPriorityFilter != 'all' && t.priority.name.toLowerCase() != _taskPriorityFilter.toLowerCase()) {
        return false;
      }
      if (_taskAssigneeFilter != 'all') {
        if (_taskAssigneeFilter == 'unassigned') {
          if (t.assignedTo != null && t.assignedTo!.isNotEmpty) return false;
        } else {
          if (t.assignedTo != _taskAssigneeFilter) return false;
        }
      }
      if (_taskFilterText.isNotEmpty) {
        final query = _taskFilterText.toLowerCase();
        final matchesTitle = t.title.toLowerCase().contains(query);
        final matchesDesc = t.description.toLowerCase().contains(query);
        final matchesId = '#task-${t.id}'.toLowerCase().contains(query) || 'task-${t.id}'.toLowerCase().contains(query);
        if (!matchesTitle && !matchesDesc && !matchesId) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(
        context,
        title: 'Project',
        actions: [
          HeaderAction(
            icon: Icons.link_rounded,
            tooltip: 'Project links (${_links.length})',
            onTap: _openLinksModal,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
                onRefresh: _loadProjectData,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 4, AppSpacing.p20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_refreshing) ...[
                        const LinearProgressIndicator(minHeight: 2),
                        const SizedBox(height: 10),
                      ],
                      // Project Name & Status Badge & Description
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _project.name,
                                  style: AppTypography.headline.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppColors.ink),
                                ),
                                const SizedBox(height: 8),
                                StatusChip.fromString(_project.status),
                                if (_project.description.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _project.description,
                                    style: AppTypography.caption.copyWith(height: 1.4, color: AppColors.textSecondary),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Actions Button Bar (Edit, Assign, Unassign, Delete, Add task, Export)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (canManageTasks) ...[
                              ElevatedButton.icon(
                                onPressed: _openCreateTaskModal,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.onPrimary,
                                  elevation: 0,
                                  shadowColor: AppColors.primary.withValues(alpha: 0.4),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r16)),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: Text('Add task', style: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (canEditProject) ...[
                              _buildActionOutlineButton('Edit', Icons.edit_outlined, _openEditProjectDialog),
                              const SizedBox(width: 8),
                              _buildActionOutlineButton('Assign', Icons.person_add_alt_1_outlined, _openAssignInternDialog),
                              const SizedBox(width: 8),
                              _buildActionOutlineButton('Unassign', Icons.person_remove_outlined, _openUnassignInternDialog),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: _confirmDeleteProject,
                                borderRadius: BorderRadius.circular(AppSpacing.r16),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(AppSpacing.r16),
                                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.25), width: 1.2),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.dangerInk),
                                      const SizedBox(width: 6),
                                      Text('Delete', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.dangerInk)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            _buildActionOutlineButton('Export', Icons.file_download_outlined, _exportProject),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Two Main Columns / Cards (Overview & Progress + Mentors & Leadership)
                      _buildOverviewSection(doneTasks, totalTasks, progressInt),
                      const SizedBox(height: 16),

                      _buildMentorsSection(canEditProject),
                      const SizedBox(height: 24),

                      // Kanban Board Header (Kanban Board, Filter, Board / List switch)
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 10,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _taskViewMode == 'board' ? 'Board' : 'Tasks',
                                style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                ),
                                child: Text(
                                  '${filteredTasks.length} tasks',
                                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryInk),
                                ),
                              ),
                            ],
                          ),

                          // Filter button; tinted while any filter is on.
                          InkWell(
                            onTap: _showTaskFilterDialog,
                            borderRadius: BorderRadius.circular(AppSpacing.r12),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 40),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: _activeFilterCount > 0 ? AppColors.primarySoft : AppColors.surface,
                                borderRadius: BorderRadius.circular(AppSpacing.r12),
                                boxShadow: AppShadows.soft,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.filter_alt_outlined,
                                    size: 15,
                                    color: _activeFilterCount > 0 ? AppColors.primaryInk : AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _activeFilterCount > 0 ? 'Filter · $_activeFilterCount' : 'Filter',
                                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Board / List toggle
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(AppSpacing.r16),
                            ),
                            child: Row(
                              children: [
                                _buildViewModeToggle('board', 'Board', Icons.grid_view_rounded),
                                _buildViewModeToggle('list', 'List', Icons.view_list_rounded),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Task Views (Board or List)
                      if (_taskViewMode == 'board')
                        _buildKanbanBoardView(filteredTasks, canManageTasks)
                      else
                        _buildTaskListView(filteredTasks, canManageTasks),
                      const SizedBox(height: 24),

                      // Comments Board Section & Recent Activity Section
                      _buildCommentsBoardSection(),
                      const SizedBox(height: 16),

                      _buildRecentActivitySection(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  // ========================================
  // SUB-VIEWS
  // ========================================

  Widget _buildActionOutlineButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.r16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.r16),
          boxShadow: AppShadows.soft,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.ink),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection(int doneTasks, int totalTasks, int progressInt) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.p20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                ),
                child: Text(
                  '$progressInt%',
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$doneTasks / $totalTasks tasks completed',
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.r8),
            child: LinearProgressIndicator(
              value: _project.progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),

          // 4 Metric cards: Start Date, End Date, Tasks Done, Total Tasks
          Row(
            children: [
              Expanded(
                child: _buildMetricPill(
                  label: 'Start',
                  value: formatDate(_project.startDate),
                  icon: Icons.calendar_today_outlined,
                  bgColor: AppColors.lavender,
                  accentColor: AppColors.lavenderInk,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricPill(
                  label: 'End',
                  value: formatDate(_project.endDate),
                  icon: Icons.event_available_outlined,
                  bgColor: AppColors.infoSoft,
                  accentColor: AppColors.infoInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricPill(
                  label: 'Tasks done',
                  value: '$doneTasks',
                  icon: Icons.check_circle_outline_rounded,
                  bgColor: AppColors.successSoft,
                  accentColor: AppColors.successInk,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricPill(
                  label: 'Total tasks',
                  value: '$totalTasks',
                  icon: Icons.assignment_outlined,
                  bgColor: AppColors.warningSoft,
                  accentColor: AppColors.warningInk,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill({
    required String label,
    required String value,
    required IconData icon,
    required Color bgColor,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: accentColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: accentColor),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMentorsSection(bool canEditProject) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.p20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mentors',
            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 14),
          ..._project.mentors.map((m) {
            final name = m['name']?.toString() ?? 'Mentor';
            final role = m['role']?.toString() ?? 'Mentor';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppSpacing.r16),
                border: Border.all(color: AppColors.border, width: 1),
              ),
              child: Row(
                children: [
                  AppAvatar(size: 34, url: m['avatar_url']?.toString(), fallbackText: name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        Text(
                          humanize(role),
                          style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (canEditProject) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: _openEditProjectDialog,
              borderRadius: BorderRadius.circular(AppSpacing.r16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppSpacing.r16),
                  border: Border.all(color: AppColors.border, width: 1),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_outlined, size: 16, color: AppColors.primaryInk),
                      const SizedBox(width: 6),
                      Text(
                        'Change mentors',
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryInk),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildViewModeToggle(String mode, String label, IconData icon) {
    final isSel = _taskViewMode == mode;
    return InkWell(
      onTap: () => setState(() => _taskViewMode = mode),
      borderRadius: BorderRadius.circular(AppSpacing.r12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSel ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          boxShadow: isSel
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isSel ? AppColors.onPrimary : AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: isSel ? AppColors.onPrimary : AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // KANBAN COLUMNS WITH DRAG & DROP
  // ========================================
  static String _statusKey(String s) => s.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

  Widget _buildKanbanBoardView(List<TaskModel> taskList, bool canManageTasks) {
    if (_taskStatuses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('This project has no task statuses set up yet.', style: AppTypography.body),
      );
    }
    final keys = _taskStatuses.map((c) => _statusKey(c.key)).toSet();
    // Tasks whose status isn't one of the columns (e.g. a status that was removed) still show up.
    final orphans = taskList.where((t) => !keys.contains(_statusKey(t.rawStatus))).toList();
    final columns = [
      ..._taskStatuses,
      if (orphans.isNotEmpty)
        const TaskStatusColumn(key: '__other__', title: 'Other', color: AppColors.textSecondary, orderIndex: 999),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: columns.map((col) {
          final isOther = col.key == '__other__';
          final colTasks =
              isOther ? orphans : taskList.where((t) => _statusKey(t.rawStatus) == _statusKey(col.key)).toList();

          return DragTarget<TaskModel>(
            onWillAcceptWithDetails: (details) => !isOther && canManageTasks && details.data.canMove,
            onAcceptWithDetails: (details) async {
              final task = details.data;
              try {
                await ApiClient().put('/api/projects/tasks/${task.id}', body: {'status': col.key});
                _loadProjectData();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${apiErrorMessage(e)}')));
              }
            },
            builder: (context, candidateData, rejectedData) {
              return Container(
                width: 260,
                margin: const EdgeInsets.only(right: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppSpacing.r20),
                  border: Border.all(
                    color: candidateData.isNotEmpty
                        ? AppColors.primary
                        : AppColors.border,
                    width: candidateData.isNotEmpty ? 2.0 : 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Column Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: col.color, shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  col.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                          ),
                          child: Text('${colTasks.length}', style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Tasks in Column
                    if (colTasks.isEmpty)
                      Container(
                        height: 100,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppSpacing.r16),
                          border: Border.all(color: AppColors.border, style: BorderStyle.solid),
                        ),
                        child: Center(
                          child: Text('No tasks', style: AppTypography.label),
                        ),
                      )
                    else
                      ...colTasks.map((t) {
                        // Long-press to drag, so a normal swipe scrolls the board.
                        return canManageTasks && t.canMove
                            ? LongPressDraggable<TaskModel>(
                                data: t,
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: SizedBox(
                                    width: 240,
                                    child: _buildTaskCard(t),
                                  ),
                                ),
                                childWhenDragging: Opacity(opacity: 0.3, child: _buildTaskCard(t)),
                                child: _buildTaskCard(t),
                              )
                            : _buildTaskCard(t);
                      }),
                  ],
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTaskCard(TaskModel task) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(
              task: task,
              onTaskUpdated: _loadProjectData,
            ),
          ),
        ).then((_) => _loadProjectData());
      },
      borderRadius: BorderRadius.circular(AppSpacing.r16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
                StatusChip.fromPriority(task.priority),
                if (task.assigneeName != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      task.assigneeName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              task.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12,
                      color: task.isOverdue ? AppColors.dangerInk : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      task.dueDate == null
                          ? 'No due date'
                          : task.isOverdue
                              ? 'Overdue · ${formatDate(task.dueDate, withYear: false)}'
                              : formatDate(task.dueDate, withYear: false),
                      style: AppTypography.label.copyWith(
                        color: task.isOverdue ? AppColors.dangerInk : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (task.commentCount > 0) ...[
                      Icon(Icons.chat_bubble_outline_rounded, size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      Text('${task.commentCount}', style: AppTypography.label.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(width: 6),
                    ],
                    if (task.attachmentCount > 0) ...[
                      Icon(Icons.attach_file_rounded, size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      Text('${task.attachmentCount}', style: AppTypography.label.copyWith(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // LIST VIEW
  // ========================================
  Widget _buildTaskListView(List<TaskModel> taskList, bool canManageTasks) {
    if (taskList.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: Text(
          _activeFilterCount > 0 ? 'No tasks match the filter.' : 'No tasks yet.',
          style: AppTypography.body,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: taskList.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final t = taskList[i];
        return Card(
          elevation: 0,
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.r16),
            side: BorderSide(color: AppColors.border),
          ),
          child: ListTile(
            title: Text(
              t.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            subtitle: Text(
              '${t.dueDate == null ? 'No due date' : 'Due ${formatDate(t.dueDate, withYear: false)}'} · ${t.assigneeName ?? 'Unassigned'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(color: AppColors.textSecondary),
            ),
            trailing: StatusChip.fromString(
              t.rawStatus,
              label: _taskStatuses.where((c) => c.key == t.rawStatus).map((c) => c.title).firstOrNull,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TaskDetailScreen(task: t, onTaskUpdated: _loadProjectData)),
              ).then((_) => _loadProjectData());
            },
          ),
        );
      },
    );
  }

  int get _activeFilterCount =>
      [_taskFilterText.isNotEmpty, _taskPriorityFilter != 'all', _taskAssigneeFilter != 'all'].where((on) => on).length;

  void _showTaskFilterDialog() {
    // Edit a draft; nothing changes unless Apply is pressed.
    final search = TextEditingController(text: _taskFilterText);
    var priority = _taskPriorityFilter;
    var assignee = _taskAssigneeFilter;
    final people = <String, String>{
      for (final m in _project.members)
        if (m['id'] != null) m['id'].toString(): m['name']?.toString() ?? 'Member',
    };
    if (assignee != 'all' && assignee != 'unassigned' && !people.containsKey(assignee)) assignee = 'all';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            insetPadding: const EdgeInsets.all(16),
            title: const Text('Filter tasks'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: search,
                  decoration: const InputDecoration(labelText: 'Search title or description'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Any priority')),
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => setDialogState(() => priority = v ?? 'all'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: assignee,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Assignee'),
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('Anyone')),
                    const DropdownMenuItem(value: 'unassigned', child: Text('Unassigned')),
                    for (final e in people.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setDialogState(() => assignee = v ?? 'all'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _taskFilterText = '';
                    _taskPriorityFilter = 'all';
                    _taskAssigneeFilter = 'all';
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Clear'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _taskFilterText = search.text.trim();
                    _taskPriorityFilter = priority;
                    _taskAssigneeFilter = assignee;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ========================================
  // COMMENTS BOARD & RECENT ACTIVITY
  // ========================================
  Future<void> _deleteBoardComment(ProjectComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this comment?'),
        content: Text(c.body, maxLines: 3, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient().delete('/api/projects/comments-board/${c.id}');
      _loadProjectData();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't delete the comment");
    }
  }

  Widget _buildCommentsBoardSection() {
    final user = ref.read(appStateProvider).currentUser;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.p20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Comments',
                style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                ),
                child: Text(
                  plural(_comments.length, 'comment'),
                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Inline composer
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentInputController,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTypography.caption.copyWith(color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Write a short update for the team',
                    hintStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.r16),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.r16),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.r16),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  tooltip: 'Post comment',
                  icon: _isPostingComment
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : const Icon(Icons.send_rounded, color: AppColors.onPrimary, size: 18),
                  onPressed: _isPostingComment ? null : _postBoardComment,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('No comments yet.', style: AppTypography.caption),
              ),
            )
          else
            ..._comments.map((c) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppSpacing.r16),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppAvatar(url: c.userAvatar, size: 30, fallbackText: c.userName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(formatRelative(c.createdAt), style: AppTypography.label),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            c.body,
                            style: AppTypography.caption.copyWith(height: 1.3, color: AppColors.ink),
                          ),
                        ],
                      ),
                    ),
                    if (c.userId == user.id || user.isAdmin)
                      IconButton(
                        tooltip: 'Delete comment',
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textSecondary),
                        onPressed: () => _deleteBoardComment(c),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection() {
    final activity = _activityItems();
    if (activity.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.p20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent activity',
            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 14),
          ...activity.map((a) {
            IconData iconData = Icons.assignment_outlined;
            Color iconColor = AppColors.lavenderInk;
            Color iconBg = AppColors.lavender;

            if (a['icon'] == 'folder') {
              iconData = Icons.folder_open_rounded;
              iconColor = AppColors.warningInk;
              iconBg = AppColors.warningSoft;
            } else if (a['icon'] == 'check') {
              iconData = Icons.check_circle_outline_rounded;
              iconColor = AppColors.successInk;
              iconBg = AppColors.successSoft;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppSpacing.r16),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(iconData, size: 16, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a['title']!,
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a['time']!,
                          style: AppTypography.label.copyWith(color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Search the organization's interns and add one to the project.
class _AssignInternDialog extends StatefulWidget {
  final String projectId;
  final String projectName;
  final Set<String?> excludeIds;
  final VoidCallback onAssigned;

  const _AssignInternDialog({
    required this.projectId,
    required this.projectName,
    required this.excludeIds,
    required this.onAssigned,
  });

  @override
  State<_AssignInternDialog> createState() => _AssignInternDialogState();
}

class _AssignInternDialogState extends State<_AssignInternDialog> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _interns = const [];
  bool _loading = true;
  String? _error;
  String? _selectedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient().get('/api/users/dropdown', queryParameters: {'role': 'intern'});
      final list = res is Map && res['interns'] is List
          ? (res['interns'] as List).whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _interns = list.where((i) => !widget.excludeIds.contains(i['id']?.toString())).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  Future<void> _assign() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiClient().post('/api/projects/${widget.projectId}/assign',
          body: {'user_id': int.tryParse(_selectedId!) ?? _selectedId});
      if (!mounted) return;
      Navigator.pop(context);
      widget.onAssigned();
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final visible = _interns.where((i) {
      final name = i['name']?.toString().toLowerCase() ?? '';
      final email = i['email']?.toString().toLowerCase() ?? '';
      return q.isEmpty || name.contains(q) || email.contains(q);
    }).toList();

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: const Text('Add an intern'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('To ${widget.projectName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Search by name or email', prefixIcon: Icon(Icons.search, size: 18)),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_interns.isEmpty && _error == null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Every intern is already on this project.', style: AppTypography.body),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final intern = visible[i];
                      final id = intern['id']?.toString();
                      final name = intern['name']?.toString() ?? '';
                      final selected = id == _selectedId;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        selected: selected,
                        selectedTileColor: AppColors.primarySoft,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: AppAvatar(size: 36, fallbackText: name),
                        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(intern['email']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: selected ? const Icon(Icons.check_circle_rounded, color: AppColors.primaryInk) : null,
                        onTap: _saving ? null : () => setState(() => _selectedId = id),
                      );
                    },
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
              if (_interns.isEmpty) TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _selectedId == null || _saving ? null : _assign,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }
}

/// Shared resources for a project: add (anyone on it), open, and delete (staff).
class _ProjectLinksDialog extends StatefulWidget {
  final String projectId;
  final List<ProjectLink> initialLinks;
  final bool canDelete;
  final ValueChanged<List<ProjectLink>> onChanged;

  const _ProjectLinksDialog({
    required this.projectId,
    required this.initialLinks,
    required this.canDelete,
    required this.onChanged,
  });

  @override
  State<_ProjectLinksDialog> createState() => _ProjectLinksDialogState();
}

class _ProjectLinksDialogState extends State<_ProjectLinksDialog> {
  final _link = TextEditingController();
  final _remark = TextEditingController();
  late List<ProjectLink> _links = List.of(widget.initialLinks);
  String? _error;
  bool _adding = false;

  @override
  void dispose() {
    _link.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final updated = await ApiClient().get('/api/projects/${widget.projectId}/links');
    final list = updated is List
        ? updated.whereType<Map<String, dynamic>>().map(ProjectLink.fromJson).toList()
        : <ProjectLink>[];
    if (!mounted) return;
    setState(() => _links = list);
    widget.onChanged(list);
  }

  Future<void> _add() async {
    final raw = _link.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      setState(() => _error = 'Enter a full link starting with https://');
      return;
    }
    setState(() {
      _adding = true;
      _error = null;
    });
    try {
      await ApiClient().post('/api/projects/${widget.projectId}/links', body: {
        'link': raw,
        'remark': _remark.text.trim().isEmpty ? uri.host : _remark.text.trim(),
      });
      _link.clear();
      _remark.clear();
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(ProjectLink l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this link?'),
        content: Text(l.remark),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient().delete('/api/projects/links/${l.id}');
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    }
  }

  Future<void> _open(ProjectLink l) async {
    final uri = Uri.tryParse(l.link);
    final opened = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!opened && mounted) setState(() => _error = "Couldn't open that link.");
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text('Project links (${_links.length})'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enabled: !_adding,
              decoration: const InputDecoration(labelText: 'Link', hintText: 'https://docs.google.com/…'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _remark,
              textCapitalization: TextCapitalization.sentences,
              enabled: !_adding,
              decoration: const InputDecoration(labelText: 'Title (optional)', hintText: 'e.g. Design doc'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _adding ? null : _add,
                icon: _adding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_link_rounded, size: 16),
                label: const Text('Add link'),
              ),
            ),
            const Divider(height: 24),
            Flexible(
              child: _links.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('No links yet.', style: AppTypography.body, textAlign: TextAlign.center),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _links.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final l = _links[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.link_rounded, color: AppColors.infoInk),
                          title: Text(l.remark, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                          subtitle: Text(l.link, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption),
                          onTap: () => _open(l),
                          trailing: widget.canDelete
                              ? IconButton(
                                  tooltip: 'Delete link',
                                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.dangerInk),
                                  onPressed: () => _delete(l),
                                )
                              : const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textSecondary),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}
