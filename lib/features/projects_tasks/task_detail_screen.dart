import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/status_chip.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _loadTaskDetails();
  }

  Future<void> _loadTaskDetails() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiClient().get('/api/projects/tasks/${_task.id}/comments').catchError((_) => []),
        ApiClient().get('/api/projects/tasks/${_task.id}/attachments').catchError((_) => []),
      ]);

      List<TaskComment> commentsList = [];
      final commRes = results[0];
      if (commRes is List) {
        commentsList = commRes.whereType<Map<String, dynamic>>().map((c) => TaskComment.fromJson(c)).toList();
      } else if (commRes is Map<String, dynamic>) {
        final items = commRes['comments'] ?? commRes['data'];
        if (items is List) commentsList = items.whereType<Map<String, dynamic>>().map((c) => TaskComment.fromJson(c)).toList();
      }

      List<TaskAttachment> attachmentsList = [];
      final attRes = results[1];
      if (attRes is List) {
        attachmentsList = attRes.whereType<Map<String, dynamic>>().map((a) => TaskAttachment.fromJson(a)).toList();
      } else if (attRes is Map<String, dynamic>) {
        final items = attRes['attachments'] ?? attRes['data'];
        if (items is List) attachmentsList = items.whereType<Map<String, dynamic>>().map((a) => TaskAttachment.fromJson(a)).toList();
      }

      if (mounted) {
        setState(() {
          _comments = commentsList;
          _attachments = attachmentsList;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Upload Validation
  // max 5 MB; allowed: jpg/jpeg/png/webp/gif/pdf/txt/doc/docx/xls/xlsx/zip
  String? _validateUploadFile(File file) {
    final size = file.lengthSync();
    if (size == 0) return 'File cannot be empty.';
    if (size > 5 * 1024 * 1024) {
      return 'Attachment must be 5 MB or smaller.';
    }
    final ext = file.path.split('.').last.toLowerCase();
    const allowed = ['jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf', 'txt', 'doc', 'docx', 'xls', 'xlsx', 'zip'];
    if (!allowed.contains(ext)) {
      return 'Attachment type is not allowed. Use images, PDF, Office docs, or zip.';
    }
    return null;
  }

  void _showAddCommentDialog() {
    final commentController = TextEditingController();
    File? pickedFile;
    String? fileError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Add Task Comment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTextField(
                  label: 'Comment',
                  hintText: 'Share an update or note on this task...',
                  controller: commentController,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(source: ImageSource.gallery);
                        if (picked != null) {
                          final f = File(picked.path);
                          final err = _validateUploadFile(f);
                          setDialogState(() {
                            if (err != null) {
                              fileError = err;
                              pickedFile = null;
                            } else {
                              pickedFile = f;
                              fileError = null;
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.attach_file_rounded, size: 16),
                      label: const Text('Attach Image/File', style: TextStyle(fontSize: 12)),
                    ),
                    if (pickedFile != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickedFile!.path.split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setDialogState(() => pickedFile = null),
                      ),
                    ],
                  ],
                ),
                if (fileError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(fileError!, style: const TextStyle(color: AppColors.danger, fontSize: 11)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary),
                onPressed: () async {
                  final text = commentController.text.trim();
                  if (text.isEmpty && pickedFile == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a comment message or attach a file.')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);

                  try {
                    List<http.MultipartFile> files = [];
                    if (pickedFile != null) {
                      files.add(await http.MultipartFile.fromPath('file', pickedFile!.path));
                    }
                    await ApiClient().postMultipart(
                      '/api/projects/tasks/${_task.id}/comments',
                      fields: {'body': text},
                      files: files,
                    );
                    _loadTaskDetails();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to post comment: $e')),
                      );
                    }
                  }
                },
                child: const Text('Post'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showUploadAttachmentDialog() {
    File? pickedFile;
    String? fileError;
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Upload Task Attachment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery);
                    if (picked != null) {
                      final f = File(picked.path);
                      final err = _validateUploadFile(f);
                      setDialogState(() {
                        if (err != null) {
                          fileError = err;
                          pickedFile = null;
                        } else {
                          pickedFile = f;
                          fileError = null;
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(pickedFile == null ? 'Choose File' : pickedFile!.path.split('/').last),
                ),
                if (fileError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(fileError!, style: const TextStyle(color: AppColors.danger, fontSize: 11)),
                  ),
                const SizedBox(height: 12),
                CustomTextField(
                  label: 'Description (optional)',
                  hintText: 'e.g. Test results screenshot',
                  controller: descController,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary),
                onPressed: () async {
                  if (pickedFile == null) {
                    setDialogState(() => fileError = 'Please choose a file to upload.');
                    return;
                  }
                  Navigator.pop(ctx);
                  try {
                    final files = [await http.MultipartFile.fromPath('file', pickedFile!.path)];
                    final fields = <String, String>{};
                    final desc = descController.text.trim();
                    if (desc.isNotEmpty) fields['description'] = desc;

                    await ApiClient().postMultipart(
                      '/api/projects/tasks/${_task.id}/attachments',
                      fields: fields,
                      files: files,
                    );
                    _loadTaskDetails();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to upload attachment: $e')),
                      );
                    }
                  }
                },
                child: const Text('Upload'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _changeStatus(String newStatusKey) async {
    try {
      await ApiClient().put('/api/projects/tasks/${_task.id}', body: {
        'status': newStatusKey,
      });
      setState(() {
        _task = _task.copyWith(rawStatus: newStatusKey, status: KanbanStatus.fromString(newStatusKey));
      });
      widget.onTaskUpdated?.call();
      ref.read(appStateProvider.notifier).fetchProjects();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    // canManageTasks = admin OR mentor OR (intern AND user is in project.members)
    final canManageTasks = user.role == UserRole.admin ||
        user.role == UserRole.mentor ||
        user.role == UserRole.superadmin ||
        _task.assignedTo == user.id;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(
        context,
        title: _task.projectName.isNotEmpty ? _task.projectName : 'Task Details',
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                      StatusChip(label: _task.rawStatus.toUpperCase().replaceAll('_', ' '), statusType: StatusType.primary),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Metadata pills
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.flag_rounded, size: 16, color: AppColors.primaryInk),
                        label: Text('Priority: ${_task.priority.name.toUpperCase()}'),
                      ),
                      Chip(
                        avatar: const Icon(Icons.calendar_today_rounded, size: 14),
                        label: Text('Due: ${DateFormat('yyyy-MM-dd').format(_task.dueDate)}'),
                      ),
                      if (_task.assigneeName != null && _task.assigneeName!.isNotEmpty)
                        Chip(
                          avatar: const Icon(Icons.person_rounded, size: 14),
                          label: Text('Assignee: ${_task.assigneeName}'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Text(
                    'Notes / Description',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.soft,
      ),
                    child: Text(
                      _task.description.isNotEmpty ? _task.description : 'No additional description provided.',
                      style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Status Selector Buttons
                  if (canManageTasks && _task.canMove) ...[
                    Text(
                      'Update Status',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildStatusButton('todo', 'To Do', _task.rawStatus, AppColors.textSecondary),
                          const SizedBox(width: 8),
                          _buildStatusButton('in_progress', 'In Progress', _task.rawStatus, AppColors.info),
                          const SizedBox(width: 8),
                          _buildStatusButton('testing', 'Review', _task.rawStatus, AppColors.warning),
                          const SizedBox(width: 8),
                          _buildStatusButton('completed', 'Completed', _task.rawStatus, AppColors.success),
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add_comment_rounded, size: 16),
                        label: const Text('Add Comment'),
                        onPressed: _showAddCommentDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _comments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('No comments yet on this task.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                                color: Colors.white,
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
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(c.authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                            Text(
                                              DateFormat('yyyy-MM-dd').format(c.createdAt),
                                              style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        if (c.message.isNotEmpty)
                                          Text(c.message, style: const TextStyle(fontSize: 13)),
                                        if (c.fileUrl != null && c.fileUrl!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          InkWell(
                                            onTap: () {
                                              FileExportService.downloadAndShare(
                                                endpoint: c.fileUrl!,
                                                defaultFileName: c.fileName ?? 'comment_attachment',
                                              );
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.infoSoft,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.attachment_rounded, size: 14, color: AppColors.info),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    c.fileName ?? 'View Attachment',
                                                    style: const TextStyle(fontSize: 11, color: AppColors.info, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.textTertiary),
                                    onPressed: () async {
                                      await ApiClient().delete('/api/projects/tasks/comments/${c.id}');
                                      _loadTaskDetails();
                                    },
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.upload_file_rounded, size: 16),
                        label: const Text('Upload File'),
                        onPressed: _showUploadAttachmentDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _attachments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('No files attached.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                                color: Colors.white,
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
                                        Text(att.fileName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                        if (att.description != null && att.description!.isNotEmpty)
                                          Text(att.description!, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.download_rounded),
                                    onPressed: () async {
                                      await FileExportService.downloadAndShare(
                                        endpoint: '/api/projects/tasks/attachments/${att.id}/download',
                                        defaultFileName: att.fileName,
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                    onPressed: () async {
                                      await ApiClient().delete('/api/projects/tasks/attachments/${att.id}');
                                      _loadTaskDetails();
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusButton(String key, String label, String currentStatus, Color color) {
    final isSelected = currentStatus.toLowerCase().replaceAll(' ', '_') == key.toLowerCase();

    return InkWell(
      onTap: () => _changeStatus(key),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}
