import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import 'create_task_bottom_sheet.dart';
import 'project_form_dialog.dart';
import 'task_detail_screen.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final ProjectModel project;

  const ProjectDetailScreen({super.key, required this.project});

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
    _project = widget.project;
    _loadProjectData();
  }

  @override
  void dispose() {
    _commentInputController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiClient().get('/api/projects/${_project.id}'),
        ApiClient().get('/api/projects/${_project.id}/links').catchError((_) => []),
        ApiClient().get('/api/projects/${_project.id}/comments-board').catchError((_) => []),
        ApiClient().get('/api/projects/task-statuses').catchError((_) => []),
      ]);

      // 1. Project + embedded tasks/members
      final projRes = results[0];
      if (projRes is Map<String, dynamic>) {
        _project = ProjectModel.fromJson(projRes);
        _tasks = _project.tasks;
      }

      // 2. Links
      List<ProjectLink> linkList = [];
      final linkRes = results[1];
      if (linkRes is List) {
        linkList = linkRes.whereType<Map<String, dynamic>>().map((l) => ProjectLink.fromJson(l)).toList();
      } else if (linkRes is Map<String, dynamic>) {
        final items = linkRes['links'] ?? linkRes['items'] ?? linkRes['data'];
        if (items is List) linkList = items.whereType<Map<String, dynamic>>().map((l) => ProjectLink.fromJson(l)).toList();
      }

      // 3. Comments Board
      List<ProjectComment> commentList = [];
      final commRes = results[2];
      if (commRes is List) {
        commentList = commRes.whereType<Map<String, dynamic>>().map((c) => ProjectComment.fromJson(c)).toList();
      } else if (commRes is Map<String, dynamic>) {
        final items = commRes['comments'] ?? commRes['items'] ?? commRes['data'];
        if (items is List) commentList = items.whereType<Map<String, dynamic>>().map((c) => ProjectComment.fromJson(c)).toList();
      }

      // 4. Task Statuses
      List<TaskStatusColumn> statusCols = [];
      final statusRes = results[3];
      if (statusRes is List) {
        statusCols = statusRes.whereType<Map<String, dynamic>>().map((c) => TaskStatusColumn.fromJson(c)).toList();
      } else if (statusRes is Map<String, dynamic>) {
        final items = statusRes['statuses'] ?? statusRes['items'] ?? statusRes['data'];
        if (items is List) statusCols = items.whereType<Map<String, dynamic>>().map((c) => TaskStatusColumn.fromJson(c)).toList();
      }

      if (statusCols.isEmpty) {
        statusCols = TaskStatusColumn.fallbackColumns();
      }

      if (mounted) {
        setState(() {
          _links = linkList;
          _comments = commentList;
          _taskStatuses = statusCols;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
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
        title: const Text('Delete Project'),
        content: Text('Are you sure you want to delete "${_project.name}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
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
            child: const Text('Delete'),
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final existingIds = _project.members.map((m) => m['id']?.toString()).toSet();

          if (loading) {
            ApiClient()
                .get('/api/users/dropdown?role=intern')
                .catchError((_) => ApiClient().get('/api/projects/interns?page=1&page_size=30'))
                .then((res) {
              List<Map<String, dynamic>> list = [];
              if (res is List) {
                list = res.whereType<Map<String, dynamic>>().toList();
              } else if (res is Map && (res['users'] ?? res['interns'] ?? res['items'] ?? res['data']) is List) {
                list = ((res['users'] ?? res['interns'] ?? res['items'] ?? res['data']) as List).whereType<Map<String, dynamic>>().toList();
              }
              var filtered = list.where((i) => !existingIds.contains(i['id']?.toString())).toList();
              if (filtered.isEmpty) {
                final all = ref.read(appStateProvider).allUsers;
                filtered = all
                    .where((u) => u.role == UserRole.intern && !existingIds.contains(u.id))
                    .map((u) => {'id': u.id, 'name': u.name, 'email': u.email, 'role': 'intern'})
                    .toList();
              }

              setDialogState(() {
                availableInterns = filtered;
                loading = false;
              });
            }).catchError((_) {
              final all = ref.read(appStateProvider).allUsers;
              final filtered = all
                  .where((u) => u.role == UserRole.intern && !existingIds.contains(u.id))
                  .map((u) => {'id': u.id, 'name': u.name, 'email': u.email, 'role': 'intern'})
                  .toList();
              setDialogState(() {
                availableInterns = filtered;
                loading = false;
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
                            const Text('Assign Intern', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'Outfit')),
                            const SizedBox(height: 2),
                            Text('Select an intern to assign to ${_project.name}.', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
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

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
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
                          backgroundColor: const Color(0xFF4B5563), // Dark grey button from screenshot 5
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      trailing: const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444)),
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
                            decoration: BoxDecoration(color: const Color(0xFFE0E7FF), borderRadius: BorderRadius.circular(10)),
                            child: Text('${_links.length}', style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 12)),
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
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
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
                                leading: const Icon(Icons.link_rounded, color: Color(0xFF3B82F6)),
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
                                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
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

  // Synthetic Activity Items (client-only, max 4)
  List<Map<String, String>> _buildSyntheticActivity() {
    final items = <Map<String, String>>[];

    // 1. "{mentor_name} created this project" using created_at
    items.add({
      'title': '${_project.mentorName} created this project',
      'time': DateFormat('MMM d, h:mm a').format(_project.createdAt),
      'icon': 'folder',
    });

    // 2. Last 2 tasks: "{assignee} added task \"{title}\""
    final sortedTasks = List<TaskModel>.from(_tasks)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    int taskCount = 0;
    for (final t in sortedTasks) {
      if (taskCount >= 2) break;
      final who = t.assigneeName ?? t.createdByName ?? 'Team';
      items.add({
        'title': '$who added task "${t.title}"',
        'time': DateFormat('MMM d, h:mm a').format(t.createdAt),
        'icon': 'task',
      });
      taskCount++;
    }

    // 3. Last completed/done task: "Task \"{title}\" was completed"
    final completedTask = _tasks.firstWhere(
      (t) => t.status == KanbanStatus.completed || t.rawStatus.toLowerCase() == 'completed' || t.rawStatus.toLowerCase() == 'done',
      orElse: () => TaskModel(
        id: '',
        projectId: '',
        title: '',
        status: KanbanStatus.todo,
        priority: TaskPriority.medium,
        dueDate: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );
    if (completedTask.id.isNotEmpty && items.length < 4) {
      items.add({
        'title': 'Task "${completedTask.title}" was completed',
        'time': DateFormat('MMM d, h:mm a').format(completedTask.createdAt),
        'icon': 'check',
      });
    }

    return items.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
      backgroundColor: isDark ? const Color(0xFF101216) : const Color(0xFFF9FAFC),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadProjectData,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Back button & Link buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
                              side: BorderSide(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            ),
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: const Text('Back to projects', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: _openLinksModal,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
                                  side: BorderSide(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                ),
                                icon: const Icon(Icons.link_rounded, size: 16),
                                label: Text('Get Project Link (${_links.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Project Name & Status Badge & Actions
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
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          fontFamily: 'Outfit',
                                          color: isDark ? Colors.white : const Color(0xFF111827),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE0E7FF),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        _project.status.toUpperCase(),
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF3B82F6)),
                                      ),
                                    ),
                                  ],
                                ),
                                if (_project.description.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _project.description,
                                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : const Color(0xFF6B7280)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Actions Button Bar (matching screenshot 3: Edit, Assign, Unassign, Delete, Add task, Export)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (canEditProject) ...[
                              _buildActionOutlineButton('Edit', Icons.edit_outlined, _openEditProjectDialog, isDark),
                              const SizedBox(width: 8),
                              _buildActionOutlineButton('Assign', Icons.person_add_alt_1_outlined, _openAssignInternDialog, isDark),
                              const SizedBox(width: 8),
                              _buildActionOutlineButton('Unassign', Icons.person_remove_outlined, _openUnassignInternDialog, isDark),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _confirmDeleteProject,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                label: const Text('Delete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (canManageTasks) ...[
                              ElevatedButton.icon(
                                onPressed: _openCreateTaskModal,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1F2937),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add task', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 8),
                            ],
                            OutlinedButton.icon(
                              onPressed: _exportProject,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
                                side: BorderSide(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              icon: const Icon(Icons.file_upload_outlined, size: 16),
                              label: const Text('Export', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Two Main Columns / Cards (Overview & Progress + Mentors & Leadership)
                      _buildOverviewSection(doneTasks, totalTasks, progressInt, isDark),
                      const SizedBox(height: 16),

                      _buildMentorsSection(canEditProject, isDark),
                      const SizedBox(height: 24),

                      // Kanban Board Header (Kanban Board, Filter, Board / List switch)
                      Row(
                        children: [
                          Row(
                            children: [
                              Text(
                                _taskViewMode == 'board' ? 'Kanban Board' : 'Task List',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'Outfit',
                                  color: isDark ? Colors.white : const Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${filteredTasks.length} tasks',
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : const Color(0xFF6B7280)),
                              ),
                            ],
                          ),
                          const Spacer(),

                          // Filter button
                          OutlinedButton.icon(
                            onPressed: _showTaskFilterDialog,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
                              side: BorderSide(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            icon: const Icon(Icons.filter_alt_outlined, size: 16),
                            label: const Text('Filter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),

                          // Board / List toggle
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1F232D) : const Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                _buildViewModeToggle('board', 'Board', Icons.grid_view_rounded, isDark),
                                _buildViewModeToggle('list', 'List', Icons.view_list_rounded, isDark),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Task Views (Board or List)
                      if (_taskViewMode == 'board')
                        _buildKanbanBoardView(filteredTasks, canManageTasks, isDark)
                      else
                        _buildTaskListView(filteredTasks, canManageTasks, isDark),
                      const SizedBox(height: 24),

                      // Comments Board Section & Recent Activity Section
                      _buildCommentsBoardSection(isDark),
                      const SizedBox(height: 16),

                      _buildRecentActivitySection(isDark),
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

  Widget _buildActionOutlineButton(String label, IconData icon, VoidCallback onTap, bool isDark) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
        side: BorderSide(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildOverviewSection(int doneTasks, int totalTasks, int progressInt, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Overview & Progress', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'Outfit')),
              Text('$progressInt%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$doneTasks / $totalTasks tasks completed', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 10),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _project.progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: isDark ? const Color(0xFF2A2E3B) : const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
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
                  color: const Color(0xFFF3E8FF),
                  textColor: const Color(0xFF7E22CE),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricPill(
                  label: 'END DATE',
                  value: DateFormat('yyyy-MM-dd').format(_project.endDate),
                  icon: Icons.calendar_today_outlined,
                  color: const Color(0xFFEFF6FF),
                  textColor: const Color(0xFF1D4ED8),
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricPill(
                  label: 'TASKS DONE',
                  value: '$doneTasks',
                  icon: Icons.check_circle_outline_rounded,
                  color: const Color(0xFFECFDF5),
                  textColor: const Color(0xFF047857),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricPill(
                  label: 'TOTAL TASKS',
                  value: '$totalTasks',
                  icon: Icons.assignment_outlined,
                  color: const Color(0xFFFEF3C7),
                  textColor: const Color(0xFFB45309),
                  isDark: isDark,
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
    required Color color,
    required Color textColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E232E) : color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isDark ? Colors.white70 : textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isDark ? Colors.white60 : textColor)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMentorsSection(bool canEditProject, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Mentors & Leadership', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'Outfit')),
          const SizedBox(height: 12),
          ..._project.mentors.map((m) {
            final name = m['name']?.toString() ?? 'Mentor';
            final role = m['role']?.toString() ?? 'Mentor';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFDE68A),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'M',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(role, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), style: BorderStyle.solid),
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16),
                      SizedBox(width: 4),
                      Text('Add another mentor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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

  Widget _buildViewModeToggle(String mode, String label, IconData icon, bool isDark) {
    final isSel = _taskViewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _taskViewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFFFBBF24) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSel ? const Color(0xFF1F2937) : (isDark ? Colors.white60 : const Color(0xFF6B7280))),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                color: isSel ? const Color(0xFF1F2937) : (isDark ? Colors.white60 : const Color(0xFF6B7280)),
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
  Widget _buildKanbanBoardView(List<TaskModel> taskList, bool canManageTasks, bool isDark) {
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
                  color: isDark ? const Color(0xFF1A1D24) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: candidateData.isNotEmpty ? const Color(0xFF3B82F6) : (isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937)),
                    width: candidateData.isNotEmpty ? 2.0 : 1.2,
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
                            Text(col.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                          child: Text('${colTasks.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
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
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                        ),
                        child: Center(
                          child: Text('No tasks in ${col.title}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
                                    child: _buildTaskCard(t, isDark),
                                  ),
                                ),
                                childWhenDragging: Opacity(opacity: 0.3, child: _buildTaskCard(t, isDark)),
                                child: _buildTaskCard(t, isDark),
                              )
                            : _buildTaskCard(t, isDark);
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

  Widget _buildTaskCard(TaskModel task, bool isDark) {
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121418) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? const Color(0xFF2C313E) : const Color(0xFFE5E7EB)),
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
                    color: task.priority == TaskPriority.high ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    task.priority.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: task.priority == TaskPriority.high ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                    ),
                  ),
                ),
                if (task.assigneeName != null)
                  Text(task.assigneeName!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 12, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(DateFormat('yyyy-MM-dd').format(task.dueDate), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                Row(
                  children: [
                    if (task.commentCount > 0) ...[
                      const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: Colors.grey),
                      const SizedBox(width: 2),
                      Text('${task.commentCount}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      const SizedBox(width: 6),
                    ],
                    if (task.attachmentCount > 0) ...[
                      const Icon(Icons.attach_file_rounded, size: 12, color: Colors.grey),
                      const SizedBox(width: 2),
                      Text('${task.attachmentCount}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
  Widget _buildTaskListView(List<TaskModel> taskList, bool canManageTasks, bool isDark) {
    if (taskList.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: const Text('No tasks found matching filter.'),
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
          color: isDark ? const Color(0xFF1A1D24) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isDark ? const Color(0xFF2C313E) : const Color(0xFFE5E7EB)),
          ),
          child: ListTile(
            title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('Due: ${DateFormat('yyyy-MM-dd').format(t.dueDate)} • Assignee: ${t.assigneeName ?? 'Unassigned'}', style: const TextStyle(fontSize: 11)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(t.rawStatus.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
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
            title: const Text('Filter Tasks'),
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
                onPressed: () {
                  setState(() {});
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
  Widget _buildCommentsBoardSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Project Comments', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'Outfit')),
              Text('${_comments.length} comments', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 12),

          // Inline composer matching screenshot 3 ("Write project message (max 100 chars)...")
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentInputController,
                  maxLength: 100,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Write project message (max 100 chars)...',
                    hintStyle: const TextStyle(fontSize: 12),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF121418) : const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _isPostingComment
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Color(0xFF3B82F6)),
                onPressed: _isPostingComment ? null : _postBoardComment,
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('No project comments posted yet.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ),
            )
          else
            ..._comments.map((c) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF121418) : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppAvatar(url: c.userAvatar, size: 28, fallbackText: c.userName),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(c.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              Text(DateFormat('MMM d, h:mm a').format(c.createdAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(c.body, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.grey),
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

  Widget _buildRecentActivitySection(bool isDark) {
    final activity = _buildSyntheticActivity();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1D24) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? const Color(0xFF2C313E) : const Color(0xFF1F2937), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'Outfit')),
          const SizedBox(height: 12),
          ...activity.map((a) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF121418) : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF3E8FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.assignment_outlined, size: 16, color: Color(0xFF7E22CE)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(a['time']!, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
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
