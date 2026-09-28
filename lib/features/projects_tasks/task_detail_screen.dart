import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/status_chip.dart';
import 'task_form_dialog.dart';
import '../../core/constants/app_typography.dart';
import '../../core/services/document_picker.dart';
import '../../core/utils/formatters.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final TaskModel task;
  final VoidCallback? onTaskUpdated;

  const TaskDetailScreen({super.key, required this.task, this.onTaskUpdated});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  late TaskModel _task;
  List<TaskComment> _comments = [];
  List<TaskAttachment> _attachments = [];
  List<TaskStatusColumn> _statuses = [];
  bool _isLoading = true;
  bool _hasLoaded = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _loadTaskDetails();
  }

  Future<void> _loadTaskDetails() async {
    setState(() {
      // After the first load, refresh in place instead of blanking the page.
      if (!_hasLoaded) _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        ApiClient().get('/api/projects/tasks/${_task.id}/comments'),
        ApiClient().get('/api/projects/tasks/${_task.id}/attachments'),
        if (_task.projectId.isNotEmpty) ApiClient().get('/api/projects/${_task.projectId}/task-statuses'),
      ]);

      // GET .../comments returns a list; GET .../attachments returns {task_id, attachments, total}.
      final commentsJson = results[0] is List ? results[0] as List : const [];
      final attachmentsJson = results[1] is Map ? ((results[1] as Map)['attachments'] as List? ?? const []) : const [];
      final attachmentsList =
          attachmentsJson.whereType<Map<String, dynamic>>().map(TaskAttachment.fromJson).toList();
      final commentsList = commentsJson.whereType<Map<String, dynamic>>().map((c) {
        final comment = TaskComment.fromJson(c);
        return comment.withAttachments(attachmentsList.where((a) => a.commentId == comment.id).toList());
      }).toList();

      // The project's workflow columns, {statuses: [...]}, in board order.
      final statusJson = results.length > 2 && results[2] is Map ? (results[2] as Map)['statuses'] : null;
      final statuses = (statusJson is List ? statusJson : const [])
          .whereType<Map<String, dynamic>>()
          .map(TaskStatusColumn.fromJson)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      if (mounted) {
        setState(() {
          _statuses = statuses;
          _comments = commentsList;
          _attachments = attachmentsList;
          _isLoading = false;
          _hasLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = apiErrorMessage(e);
        });
      }
    }
  }

  /// Files the task endpoints accept (images, PDF, Office documents, text, zip), up to 5 MB.
  static const _taskFileTypes = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf', 'txt', 'doc', 'docx', 'xls', 'xlsx', 'zip'];

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
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
    return ok == true;
  }

  Future<void> _deleteComment(TaskComment c) async {
    if (!await _confirm('Delete this comment?', 'Files attached to it are deleted too.')) return;
    try {
      await ApiClient().delete('/api/projects/tasks/comments/${c.id}');
      _loadTaskDetails();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't delete the comment");
    }
  }

  Future<void> _deleteAttachment(TaskAttachment att) async {
    if (!await _confirm('Delete this file?', att.fileName)) return;
    try {
      await ApiClient().delete('/api/projects/tasks/attachments/${att.id}');
      _loadTaskDetails();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't delete the file");
    }
  }

  Future<void> _download(TaskAttachment att) async {
    try {
      await FileExportService.downloadAndShare(
        endpoint: '/api/projects/tasks/attachments/${att.id}/download',
        defaultFileName: att.fileName,
      );
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't download ${att.fileName}");
    }
  }

  void _showAddCommentDialog() => _openUploadDialog(isComment: true);

  void _showUploadAttachmentDialog() => _openUploadDialog(isComment: false);

  /// Comment (text, optional file) or attachment (file, optional note). Stays open until the upload finishes.
  Future<void> _openUploadDialog({required bool isComment}) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _TaskUploadDialog(
        taskId: _task.id,
        isComment: isComment,
        allowedExtensions: _taskFileTypes,
      ),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isComment ? 'Comment posted' : 'File uploaded')),
      );
      _loadTaskDetails();
      widget.onTaskUpdated?.call();
    }
  }

  /// The task form needs the project (members to assign, workflow statuses).
  Future<ProjectModel> _fetchProject() async {
    final res = await ApiClient().get('/api/projects/${_task.projectId}');
    if (res is! Map<String, dynamic>) {
      throw ApiException(statusCode: 500, message: 'Unexpected response for the project.');
    }
    return ProjectModel.fromJson(res);
  }

  Future<void> _editTask() async {
    final ProjectModel project;
    try {
      project = await _fetchProject();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't open the task");
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskFormDialog(
        project: project,
        taskToEdit: _task,
        onTaskCreated: () async {
          widget.onTaskUpdated?.call();
          // Show the saved values: the project payload carries the updated task.
          try {
            final fresh = (await _fetchProject()).tasks.where((x) => x.id == _task.id);
            if (mounted && fresh.isNotEmpty) setState(() => _task = fresh.first);
          } catch (_) {
            // The edit itself succeeded; the list refresh above keeps the project view current.
          }
        },
      ),
    );
  }

  Future<void> _deleteTask() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this task?'),
        content: Text('"${_task.title}" moves to the recycle bin, where an admin can restore it.'),
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
    if (ok != true || !mounted) return;
    try {
      await ApiClient().delete('/api/tasks/${_task.id}');
      widget.onTaskUpdated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task deleted')));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't delete the task");
    }
  }

  String? _savingStatus; // the status being saved, so taps can't pile up

  void _changeStatus(String newStatusKey) async {
    if (_savingStatus != null || newStatusKey == _task.rawStatus) return;
    setState(() => _savingStatus = newStatusKey);
    try {
      await ApiClient().put('/api/projects/tasks/${_task.id}', body: {
        'status': newStatusKey,
      });
      setState(() {
        _task = _task.copyWith(rawStatus: newStatusKey, status: KanbanStatus.fromString(newStatusKey));
      });
      widget.onTaskUpdated?.call();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't change the status");
    } finally {
      if (mounted) setState(() => _savingStatus = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final isAdmin = user.isAdmin;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(
        context,
        title: _task.projectName.isNotEmpty ? _task.projectName : 'Task',
        actions: [
          if (_task.canEdit)
            HeaderAction(icon: Icons.edit_outlined, tooltip: 'Edit task', onTap: _editTask),
          if (_task.canDelete)
            HeaderAction(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete task',
              color: AppColors.danger,
              onTap: _deleteTask,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? LoadErrorView(title: 'Couldn\'t load this task', message: _loadError!, onRetry: _loadTaskDetails)
          : RefreshIndicator(
              onRefresh: _loadTaskDetails,
              child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _task.title,
                          style: AppTypography.title.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusChip.fromString(
                        _task.rawStatus,
                        label: _statuses.where((s) => s.key == _task.rawStatus).map((s) => s.title).firstOrNull,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Metadata pills
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StatusChip.fromPriority(_task.priority),
                      StatusChip(
                        icon: Icons.calendar_today_rounded,
                        label: _task.dueDate == null ? 'No due date' : 'Due ${formatDate(_task.dueDate)}',
                        statusType: _task.isOverdue ? StatusType.danger : StatusType.neutral,
                      ),
                      if (_task.assigneeName != null && _task.assigneeName!.isNotEmpty)
                        StatusChip(
                          icon: Icons.person_rounded,
                          label: _task.assigneeName!,
                          statusType: StatusType.neutral,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Text(
                    'Description',
                    style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
                    child: Text(
                      _task.description.isNotEmpty ? _task.description : 'No additional description provided.',
                      style: AppTypography.caption.copyWith(height: 1.4, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status selector: shown when the API says this user can move the task.
                  if (_task.canMove && _statuses.isNotEmpty) ...[
                    Text(
                      'Status',
                      style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in _statuses) ...[
                            _buildStatusButton(s.key, s.title, _task.rawStatus, s.color),
                            if (s != _statuses.last) const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                  ],

                  // Task Comments Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Comments (${_comments.length})',
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add_comment_rounded, size: 16),
                        label: const Text('Add comment'),
                        onPressed: _showAddCommentDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _comments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('No comments yet on this task.', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _comments.length,
                          itemBuilder: (context, i) {
                            final c = _comments[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppAvatar(url: c.authorAvatar, size: 32, fallbackText: c.authorName),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                c.authorName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(formatRelative(c.createdAt), style: AppTypography.label),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        if (c.message.isNotEmpty)
                                          Text(c.message, style: AppTypography.caption.copyWith(color: AppColors.ink)),
                                        for (final file in c.attachments) ...[
                                          const SizedBox(height: 6),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: () => _download(file),
                                            child: Container(
                                              constraints: const BoxConstraints(minHeight: 36),
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppColors.infoSoft,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.attachment_rounded, size: 14, color: AppColors.infoInk),
                                                  const SizedBox(width: 4),
                                                  Flexible(
                                                    child: Text(
                                                      file.fileName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: AppTypography.label.copyWith(color: AppColors.infoInk, fontWeight: FontWeight.w700),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  // Only admins can delete task comments.
                                  if (isAdmin)
                                    IconButton(
                                      tooltip: 'Delete comment',
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.textSecondary),
                                      onPressed: () => _deleteComment(c),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 20),

                  // Attachments Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Attachments (${_attachments.length})',
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                        label: const Text('Upload file'),
                        onPressed: _showUploadAttachmentDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _attachments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('No files attached.', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _attachments.length,
                          itemBuilder: (context, i) {
                            final att = _attachments[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
                              child: Row(
                                children: [
                                  const Icon(Icons.attach_file_rounded, color: AppColors.primaryInk),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          att.fileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                                        ),
                                        if (att.description != null && att.description!.isNotEmpty)
                                          Text(att.description!, style: AppTypography.label.copyWith(color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Download',
                                    icon: const Icon(Icons.download_rounded),
                                    onPressed: () => _download(att),
                                  ),
                                  // The API lets admins, the uploader and the project's mentors delete a file.
                                  if (isAdmin || user.isMentor || att.uploadedById == user.id)
                                    IconButton(
                                      tooltip: 'Delete file',
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.dangerInk),
                                      onPressed: () => _deleteAttachment(att),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
            ),
    );
  }

  Widget _buildStatusButton(String key, String label, String currentStatus, Color color) {
    final isSelected = currentStatus.toLowerCase().replaceAll(' ', '_') == key.toLowerCase();

    final saving = _savingStatus == key;
    // Selected = amber with ink text (readable for any org status color); the column color is the dot.
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: _savingStatus == null ? () => _changeStatus(key) : null,
        borderRadius: BorderRadius.circular(AppSpacing.rPill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.rPill),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (saving)
                const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
              else
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppColors.onPrimary : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskUploadDialog extends StatefulWidget {
  final String taskId;
  final bool isComment;
  final List<String> allowedExtensions;

  const _TaskUploadDialog({required this.taskId, required this.isComment, required this.allowedExtensions});

  @override
  State<_TaskUploadDialog> createState() => _TaskUploadDialogState();
}

class _TaskUploadDialogState extends State<_TaskUploadDialog> {
  final _text = TextEditingController();
  PickedDocument? _file;
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final doc = await pickDocument(allowedExtensions: widget.allowedExtensions, maxMb: 5);
      if (doc != null) {
        setState(() {
          _file = doc;
          _error = null;
        });
      }
    } on DocumentPickException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = "Couldn't open that file. Try another one.");
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (widget.isComment && text.isEmpty && _file == null) {
      setState(() => _error = 'Write a comment or attach a file.');
      return;
    }
    if (!widget.isComment && _file == null) {
      setState(() => _error = 'Choose a file to upload.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final files = [if (_file != null) await http.MultipartFile.fromPath('file', _file!.file.path)];
      final path = widget.isComment
          ? '/api/projects/tasks/${widget.taskId}/comments'
          : '/api/projects/tasks/${widget.taskId}/attachments';
      final fields = widget.isComment ? {'body': text} : {if (text.isNotEmpty) 'description': text};
      await ApiClient().postMultipart(path, fields: fields, files: files);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(widget.isComment ? 'Add a comment' : 'Upload a file'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomTextField(
              label: widget.isComment ? 'Comment' : 'Note (optional)',
              hintText: widget.isComment ? 'Share an update on this task' : 'e.g. Test results',
              controller: _text,
              maxLines: widget.isComment ? 3 : 1,
              textCapitalization: TextCapitalization.sentences,
              enabled: !_sending,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _sending ? null : _pick,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(
                _file == null ? (widget.isComment ? 'Attach a file (optional)' : 'Choose a file') : _file!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_file != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(_file!.sizeLabel, style: AppTypography.caption)),
                    TextButton(
                      onPressed: _sending ? null : () => setState(() => _file = null),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Images, PDF, Office files, text or zip · up to 5 MB', style: AppTypography.label),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.isComment ? 'Post' : 'Upload'),
        ),
      ],
    );
  }
}
