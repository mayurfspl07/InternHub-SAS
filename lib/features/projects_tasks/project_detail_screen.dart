import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../activity_audit/activity_repository.dart';
import '../activity_audit/models/activity_models.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/reference_components.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import 'create_task_bottom_sheet.dart';
import 'project_form_dialog.dart';
import 'task_detail_screen.dart';

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
      _isLoading = true;
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
        });
      }
      _loadActivity(targetId);
    } catch (e) {
      if (mounted) {
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
        title: const Text('Delete Project', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete "${_project.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r12)),
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
                    SnackBar(content: Text('Failed to delete project: $e')),
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

  // Assign Intern Dialog (Screenshot 5)
  // GET /api/projects/interns?page=1&page_size=30&search={q?} (filter out users already in project.members)
  // POST /api/projects/{id}/assign with { "user_id": 41 }
  void _openAssignInternDialog() async {
    final searchCtrl = TextEditingController();
    String? selectedInternId;
    List<Map<String, dynamic>> availableInterns = [];
    bool loading = true;
    bool loaded = false;
    String? loadError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final existingIds = _project.members.map((m) => m['id']?.toString()).toSet();

          if (loading) {
            loading = false; // start the request once
            ApiClient().get('/api/users/dropdown', queryParameters: {'role': 'intern'}).then((res) {
              final list = res is Map && res['interns'] is List
                  ? (res['interns'] as List).whereType<Map<String, dynamic>>().toList()
                  : <Map<String, dynamic>>[];
              setDialogState(() {
                availableInterns = list.where((i) => !existingIds.contains(i['id']?.toString())).toList();
                loadError = null;
                loaded = true;
              });
            }).catchError((Object e) {
              setDialogState(() {
                loadError = apiErrorMessage(e);
                loaded = true;
              });
            });
          }

          final q = searchCtrl.text.trim().toLowerCase();
          final filtered = availableInterns.where((i) {
            final name = i['name']?.toString().toLowerCase() ?? '';
            final email = i['email']?.toString().toLowerCase() ?? '';
            return name.contains(q) || email.contains(q);
          }).toList();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Assign Intern', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('Select an intern to assign to ${_project.name}.', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text('SELECT INTERN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search interns by name or email...',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 16),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (!loaded)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    )
                  else if (loadError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text("Couldn't load interns: $loadError",
                          style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                    )
                  else if (availableInterns.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text('Every intern is already on this project.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),

                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedInternId,
                        hint: const Text('-- Choose an intern --', style: TextStyle(fontSize: 12)),
                        isExpanded: true,
                        items: filtered.map((i) {
                          return DropdownMenuItem(
                            value: i['id']?.toString() ?? '',
                            child: Text('${i['name']} (${i['email']})', style: const TextStyle(fontSize: 12)),
                          );
                        }).toList(),
                        onChanged: (val) => setDialogState(() => selectedInternId = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Wrap(
                    alignment: WrapAlignment.end,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: selectedInternId == null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                try {
                                  final uid = int.tryParse(selectedInternId!) ?? selectedInternId;
                                  await ApiClient().post('/api/projects/${_project.id}/assign', body: {'user_id': uid});
                                  _loadProjectData();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Intern assigned successfully!')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r12)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text('Assign Intern', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Unassign Intern Dialog
  // Pick from project.members, DELETE /api/projects/{id}/assign/{userId}
  void _openUnassignInternDialog() {
    final interns = _project.members.where((m) => m['role'] == null || m['role'].toString().toLowerCase() == 'intern').toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unassign Intern'),
        content: SizedBox(
          width: 360,
          child: interns.isEmpty
              ? const Text('No interns currently assigned.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: interns.length,
                  itemBuilder: (_, i) {
                    final intern = interns[i];
                    return ListTile(
                      title: Text(intern['name']?.toString() ?? 'Intern'),
                      subtitle: Text(intern['email']?.toString() ?? ''),
                      trailing: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                      onTap: () async {
                        Navigator.pop(ctx);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        try {
                          await ApiClient().delete('/api/projects/${_project.id}/assign/${intern['id']}');
                          _loadProjectData();
                          if (mounted) {
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(content: Text('Intern unassigned successfully.')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
                          }
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
    final linkCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              width: 500,
              constraints: const BoxConstraints(maxHeight: 520),
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Text('Project Links', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.lavender, borderRadius: BorderRadius.circular(10)),
                            child: Text('${_links.length}', style: const TextStyle(color: AppColors.info, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(height: 16),

                  // Add link row
                  TextField(
                    controller: linkCtrl,
                    decoration: const InputDecoration(labelText: 'Resource URL *', hintText: 'https://docs.google.com/...'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarkCtrl,
                    decoration: const InputDecoration(labelText: 'Remark / Title', hintText: 'e.g. PRD draft'),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r12)),
                      ),
                      icon: const Icon(Icons.add_link_rounded, size: 16),
                      label: const Text('Add Link'),
                      onPressed: () async {
                        final rawLink = linkCtrl.text.trim();
                        if (rawLink.isEmpty) return;
                        final remark = remarkCtrl.text.trim().isEmpty ? 'Project Resource' : remarkCtrl.text.trim();
                        try {
                          await ApiClient().post('/api/projects/${_project.id}/links', body: {
                            'link': rawLink,
                            'remark': remark,
                          });
                          linkCtrl.clear();
                          remarkCtrl.clear();
                          final updated = await ApiClient().get('/api/projects/${_project.id}/links');
                          List<ProjectLink> lList = [];
                          if (updated is List) lList = updated.whereType<Map<String, dynamic>>().map((l) => ProjectLink.fromJson(l)).toList();
                          setDialogState(() {
                            _links = lList;
                          });
                          setState(() {});
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Existing Links List
                  Expanded(
                    child: _links.isEmpty
                        ? const Center(child: Text('No links added yet.'))
                        : ListView.separated(
                            itemCount: _links.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final l = _links[i];
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.link_rounded, color: AppColors.info),
                                title: Text(l.remark, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(l.link, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                                      onPressed: () {
                                        final uri = Uri.tryParse(l.link);
                                        if (uri != null && uri.scheme.startsWith('http')) {
                                          launchUrl(uri, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                                      onPressed: () async {
                                        await ApiClient().delete('/api/projects/links/${l.id}');
                                        setDialogState(() => _links.removeAt(i));
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Create Task Modal
  void _openCreateTaskModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CreateTaskBottomSheet(
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

    if (text.length > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment must be under 100 characters')),
      );
      return;
    }

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to post comment: $e')));
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
        'time': when == null ? '' : DateFormat('MMM d, h:mm a').format(when),
        'icon': icon,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    if (_isLoading && _project.name == 'Loading...') {
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
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadProjectData,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Back button & Links button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          CircularIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            iconSize: 18,
                            onTap: () => Navigator.pop(context),
                          ),
                          InkWell(
                            onTap: _openLinksModal,
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                boxShadow: AppShadows.soft,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.link_rounded, size: 16, color: AppColors.primaryInk),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Project Links',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primarySoft,
                                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                    ),
                                    child: Text(
                                      '${_links.length}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primaryInk,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Project Name & Status Badge & Description
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _project.name,
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.5,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySoft,
                                        borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                      ),
                                      child: Text(
                                        _project.status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                          color: AppColors.primaryInk,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_project.description.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    _project.description,
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                      color: AppColors.textSecondary,
                                    ),
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
                                label: const Text('Add Task', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                                      SizedBox(width: 6),
                                      Text('Delete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.danger)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            _buildActionOutlineButton('Export', Icons.file_upload_outlined, _exportProject),
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
                                _taskViewMode == 'board' ? 'Kanban Board' : 'Task List',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
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
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryInk,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Filter button
                          InkWell(
                            onTap: _showTaskFilterDialog,
                            borderRadius: BorderRadius.circular(AppSpacing.r12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(AppSpacing.r12),
        boxShadow: AppShadows.soft,
      ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.filter_alt_outlined, size: 15, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Filter',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.ink,
                                    ),
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
          color: Colors.white,
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
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
        color: Colors.white,
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
                'Overview & Progress',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                ),
                child: Text(
                  '$progressInt%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$doneTasks / $totalTasks tasks completed',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
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
                  label: 'START DATE',
                  value: DateFormat('yyyy-MM-dd').format(_project.startDate),
                  icon: Icons.calendar_today_outlined,
                  bgColor: AppColors.lavender,
                  accentColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricPill(
                  label: 'END DATE',
                  value: DateFormat('yyyy-MM-dd').format(_project.endDate),
                  icon: Icons.event_available_outlined,
                  bgColor: AppColors.infoSoft,
                  accentColor: AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricPill(
                  label: 'TASKS DONE',
                  value: '$doneTasks',
                  icon: Icons.check_circle_outline_rounded,
                  bgColor: AppColors.successSoft,
                  accentColor: AppColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricPill(
                  label: 'TOTAL TASKS',
                  value: '$totalTasks',
                  icon: Icons.assignment_outlined,
                  bgColor: AppColors.warningSoft,
                  accentColor: AppColors.warning,
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
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mentors & Leadership',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
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
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'M',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.warningInk),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
                      const Icon(Icons.add_rounded, size: 16, color: AppColors.primaryInk),
                      const SizedBox(width: 6),
                      Text(
                        'Add another mentor',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryInk,
                        ),
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
    return GestureDetector(
      onTap: () => setState(() => _taskViewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                color: isSel ? AppColors.onPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // KANBAN COLUMNS WITH DRAG & DROP
  // ========================================
  Widget _buildKanbanBoardView(List<TaskModel> taskList, bool canManageTasks) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _taskStatuses.map((col) {
          final colTasks = taskList.where((t) {
            final s = t.rawStatus.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
            final k = col.key.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');
            if (s == k) return true;
            if (k.contains('todo') && (s.contains('todo') || s == 'to_do')) return true;
            if (k.contains('progress') && s.contains('progress')) return true;
            if ((k.contains('review') || k.contains('test')) && (s.contains('review') || s.contains('test'))) return true;
            if ((k.contains('complete') || k.contains('done')) && (s.contains('complete') || s.contains('done'))) return true;
            return false;
          }).toList();

          return DragTarget<TaskModel>(
            onWillAcceptWithDetails: (details) => canManageTasks && details.data.canMove,
            onAcceptWithDetails: (details) async {
              final task = details.data;
              try {
                await ApiClient().put('/api/projects/tasks/${task.id}', body: {'status': col.key});
                _loadProjectData();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
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
                        Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: col.color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(col.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                          ),
                          child: Text('${colTasks.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.ink)),
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
                          child: Text('No tasks in ${col.title}', style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                        ),
                      )
                    else
                      ...colTasks.map((t) {
                        return canManageTasks && t.canMove
                            ? Draggable<TaskModel>(
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
    Color priorityBg;
    Color priorityColor;
    if (task.priority == TaskPriority.high) {
      priorityBg = AppColors.dangerSoft;
      priorityColor = AppColors.danger;
    } else if (task.priority == TaskPriority.medium) {
      priorityBg = AppColors.warningSoft;
      priorityColor = AppColors.warning;
    } else {
      priorityBg = AppColors.infoSoft;
      priorityColor = AppColors.info;
    }

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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: priorityBg,
                    borderRadius: BorderRadius.circular(AppSpacing.r8),
                  ),
                  child: Text(
                    task.priority.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: priorityColor,
                    ),
                  ),
                ),
                if (task.assigneeName != null)
                  Text(
                    task.assigneeName!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              task.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.ink,
              ),
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(
                      task.dueDate == null ? 'No due date' : DateFormat('yyyy-MM-dd').format(task.dueDate!),
                      style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (task.commentCount > 0) ...[
                      Icon(Icons.chat_bubble_outline_rounded, size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      Text('${task.commentCount}', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                      const SizedBox(width: 6),
                    ],
                    if (task.attachmentCount > 0) ...[
                      Icon(Icons.attach_file_rounded, size: 12, color: AppColors.textTertiary),
                      const SizedBox(width: 2),
                      Text('${task.attachmentCount}', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
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
          'No tasks found matching filter.',
          style: TextStyle(color: AppColors.textSecondary),
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
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.r16),
            side: BorderSide(color: AppColors.border),
          ),
          child: ListTile(
            title: Text(
              t.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.ink,
              ),
            ),
            subtitle: Text(
              '${t.dueDate == null ? 'No due date' : 'Due: ${DateFormat('yyyy-MM-dd').format(t.dueDate!)}'} • Assignee: ${t.assigneeName ?? 'Unassigned'}',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(AppSpacing.r12),
              ),
              child: Text(
                t.rawStatus.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryInk,
                ),
              ),
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

  void _showTaskFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r24)),
            title: const Text('Filter Tasks', style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Search text or #task-id'),
                  onChanged: (v) => _taskFilterText = v,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _taskPriorityFilter,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Priorities')),
                    DropdownMenuItem(value: 'low', child: Text('Low')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'high', child: Text('High')),
                  ],
                  onChanged: (v) => _taskPriorityFilter = v ?? 'all',
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
                child: const Text('Reset'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r12)),
                ),
                onPressed: () {
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
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
  Widget _buildCommentsBoardSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.p20),
      decoration: BoxDecoration(
        color: Colors.white,
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
                'Project Comments',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                ),
                child: Text(
                  '${_comments.length} comments',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryInk,
                  ),
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
                  style: TextStyle(fontSize: 12, color: AppColors.ink),
                  decoration: InputDecoration(
                    hintText: 'Write project message (max 100 chars)...',
                    hintStyle: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    counterText: '',
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
                  icon: _isPostingComment
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
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
                child: Text('No project comments posted yet.', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                c.userName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: AppColors.ink,
                                ),
                              ),
                              Text(
                                DateFormat('MMM d, h:mm a').format(c.createdAt),
                                style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            c.body,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.textTertiary),
                      onPressed: () async {
                        await ApiClient().delete('/api/projects/comments-board/${c.id}');
                        _loadProjectData();
                      },
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Activity',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          ...activity.map((a) {
            IconData iconData = Icons.assignment_outlined;
            Color iconColor = AppColors.primary;
            Color iconBg = AppColors.lavender;

            if (a['icon'] == 'folder') {
              iconData = Icons.folder_open_rounded;
              iconColor = AppColors.warning;
              iconBg = AppColors.warningSoft;
            } else if (a['icon'] == 'check') {
              iconData = Icons.check_circle_outline_rounded;
              iconColor = AppColors.success;
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
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a['time']!,
                          style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
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
