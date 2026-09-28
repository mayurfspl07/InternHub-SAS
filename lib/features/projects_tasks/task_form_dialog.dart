import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../shared/models/project_model.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../core/constants/app_typography.dart';
import '../../core/utils/formatters.dart';

class TaskFormDialog extends ConsumerStatefulWidget {
  final ProjectModel? project;
  final TaskModel? taskToEdit;
  final VoidCallback? onTaskCreated;

  const TaskFormDialog({
    super.key,
    this.project,
    this.taskToEdit,
    this.onTaskCreated,
  });

  @override
  ConsumerState<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends ConsumerState<TaskFormDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _assigneeSearchController = TextEditingController();

  String _selectedStatus = 'todo';
  List<TaskStatusColumn> _taskStatuses = [];
  String _selectedPriority = 'medium';
  DateTime? _dueDate;

  String? _selectedAssigneeId;

  bool _isLoading = true;
  String? _loadError;
  bool _isSubmitting = false;
  // Errors show after the first Save attempt, then update live.
  bool _attempted = false;

  String? _titleError;
  String? _descError;
  String? _assigneeError;
  String? _dueDateError;

  @override
  void initState() {
    super.initState();
    if (widget.taskToEdit != null) {
      final t = widget.taskToEdit!;
      _titleController.text = t.title;
      _descController.text = t.description;
      _selectedStatus = t.rawStatus;
      _selectedPriority = t.priority.name;
      _dueDate = t.dueDate;
      _selectedAssigneeId = t.assignedTo;
    }
    _loadStatuses();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _assigneeSearchController.dispose();
    super.dispose();
  }

  /// The project's own workflow columns (`{statuses: [...]}`), in board order.
  Future<void> _loadStatuses() async {
    final proj = widget.project;
    if (proj == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final res = await ApiClient().get('/api/projects/${proj.id}/task-statuses');
      final items = res is Map ? res['statuses'] : null;
      final cols = (items is List ? items : const [])
          .whereType<Map<String, dynamic>>()
          .map(TaskStatusColumn.fromJson)
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      if (cols.isEmpty) throw ApiException(statusCode: 500, message: 'This project has no task statuses set up.');

      if (mounted) {
        setState(() {
          _taskStatuses = cols;
          if (widget.taskToEdit == null) {
            _selectedStatus = cols.firstWhere((c) => c.isDefault, orElse: () => cols.first).key;
          }
          _isLoading = false;
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

  void _validate() {
    setState(() {
      final title = _titleController.text.trim();
      if (title.isEmpty) {
        _titleError = 'Title is required';
      } else if (title.length > 100) {
        _titleError = 'Max 100 characters';
      } else {
        _titleError = null;
      }

      final desc = _descController.text.trim();
      if (desc.length > 1000) {
        _descError = 'Max 1000 characters';
      } else {
        _descError = null;
      }

      if (_selectedAssigneeId == null || _selectedAssigneeId!.isEmpty) {
        _assigneeError = 'Pick who will do this task';
      } else {
        _assigneeError = null;
      }

      // On CREATE, due date must be today or later
      if (widget.taskToEdit == null && _dueDate != null) {
        final today = DateTime.now();
        final todayZero = DateTime(today.year, today.month, today.day);
        final dueZero = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day);
        if (dueZero.isBefore(todayZero)) {
          _dueDateError = 'Due date must be today or later';
        } else {
          _dueDateError = null;
        }
      } else {
        _dueDateError = null;
      }

      if (!_attempted) {
        _titleError = _descError = _assigneeError = _dueDateError = null;
      }
    });
  }

  Future<void> _submit() async {
    _attempted = true;
    _validate();
    if (_titleError != null || _descError != null || _assigneeError != null || _dueDateError != null) {
      return;
    }

    final proj = widget.project;
    if (proj == null) return;

    final parsedAssignee = int.tryParse(_selectedAssigneeId!) ?? _selectedAssigneeId;

    final payload = <String, dynamic>{
      'title': _titleController.text.trim(),
      'status': _selectedStatus,
      'priority': _selectedPriority,
      'assigned_to': parsedAssignee,
    };

    final desc = _descController.text.trim();
    if (desc.isNotEmpty) {
      payload['description'] = desc;
    }

    if (_dueDate != null) {
      payload['due_date'] = DateFormat('yyyy-MM-dd').format(_dueDate!);
    }

    setState(() => _isSubmitting = true);

    try {
      if (widget.taskToEdit != null) {
        await ApiClient().put('/api/projects/tasks/${widget.taskToEdit!.id}', body: payload);
      } else {
        await ApiClient().post('/api/projects/${proj.id}/tasks', body: payload);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.taskToEdit != null ? 'Task updated successfully!' : 'Task created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onTaskCreated?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(e)),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final proj = widget.project;
    final members = proj?.members ?? [];

    final assigneeQuery = _assigneeSearchController.text.trim().toLowerCase();
    final filteredMembers = members.where((m) {
      final name = m['name']?.toString().toLowerCase() ?? '';
      final email = m['email']?.toString().toLowerCase() ?? '';
      return name.contains(assigneeQuery) || email.contains(assigneeQuery);
    }).toList();

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.all(22),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LoadErrorView(
                        title: "Couldn't open the task form",
                        message: _loadError!,
                        onRetry: _loadStatuses,
                        compact: true,
                      ),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                    ],
                  )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.taskToEdit != null ? 'Edit task' : 'New task',
                          style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        tooltip: 'Close',
                        onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Scrollable body; the dialog is only as tall as its content.
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title *
                          _buildLabel('Title'),
                          TextField(
                            controller: _titleController,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => _validate(),
                            style: AppTypography.caption.copyWith(color: AppColors.ink),
                            decoration: _inputDecoration(
                              hint: 'e.g. Implement authentication middleware',
                              errorText: _titleError,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Notes / Description
                          _buildLabel('Description (optional)'),
                          TextField(
                            controller: _descController,
                            maxLines: 3,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (_) => _validate(),
                            style: AppTypography.caption.copyWith(color: AppColors.ink),
                            decoration: _inputDecoration(
                              hint: 'Add implementation instructions, context or links...',
                              errorText: _descError,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Status & Priority Row
                          Row(
                            children: [
                              // Status
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel('Status'),
                                    Container(
                                      height: 42,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceMuted,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedStatus,
                                          isExpanded: true,
                                          dropdownColor: AppColors.surface,
                                          items: _taskStatuses.map((s) {
                                            return DropdownMenuItem(
                                              value: s.key,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      s.title,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: AppTypography.caption.copyWith(color: AppColors.ink),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) setState(() => _selectedStatus = val);
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Priority
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel('Priority'),
                                    Container(
                                      height: 42,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceMuted,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.border),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedPriority,
                                          isExpanded: true,
                                          dropdownColor: AppColors.surface,
                                          items: const [
                                            DropdownMenuItem(value: 'low', child: Text('Low')),
                                            DropdownMenuItem(value: 'medium', child: Text('Medium')),
                                            DropdownMenuItem(value: 'high', child: Text('High')),
                                          ],
                                          onChanged: (val) {
                                            if (val != null) setState(() => _selectedPriority = val);
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Assignee *
                          _buildLabel('Assignee'),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _assigneeError != null
                                    ? AppColors.danger
                                    : AppColors.border,
                              ),
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _assigneeSearchController,
                                    onChanged: (_) => setState(() {}),
                                    style: AppTypography.caption.copyWith(color: AppColors.ink),
                                    decoration: InputDecoration(
                                      hintText: 'Search project members',
                                      hintStyle: AppTypography.label.copyWith(color: AppColors.textTertiary),
                                      prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textTertiary),
                                      filled: true,
                                      fillColor: AppColors.surface,
                                      contentPadding: EdgeInsets.zero,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: AppColors.border),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (filteredMembers.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      members.isEmpty
                                          ? 'Nobody is on this project yet. Add interns to the project first.'
                                          : 'Nobody matches that search.',
                                      style: AppTypography.caption,
                                    ),
                                  )
                                else
                                SizedBox(
                                  height: 150,
                                  child: ListView.builder(
                                    itemCount: filteredMembers.length,
                                    itemBuilder: (ctx, i) {
                                      final mem = filteredMembers[i];
                                      final id = mem['id']?.toString() ?? '';
                                      final isSelected = _selectedAssigneeId == id;

                                      return InkWell(
                                        onTap: () {
                                          setState(() {
                                            _selectedAssigneeId = id;
                                          });
                                          _validate();
                                        },
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 6),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isSelected ? AppColors.primarySoft : AppColors.surface,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isSelected ? AppColors.primary : AppColors.border,
                                              width: isSelected ? 1.5 : 1.0,
                                            ),
                                          ),
                                          // Name over email so long addresses never push the name off-screen.
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      mem['name']?.toString() ?? 'Member',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
                                                    ),
                                                    Text(
                                                      mem['email']?.toString() ?? '',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: AppTypography.label,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (isSelected) const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primaryInk),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_assigneeError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Text(_assigneeError!, style: AppTypography.label.copyWith(color: AppColors.dangerInk)),
                            ),
                          const SizedBox(height: 14),

                          // Due Date
                          _buildLabel('Due date (optional)'),
                          InkWell(
                            onTap: () async {
                              final today = DateUtils.dateOnly(DateTime.now());
                              // New tasks can't be due in the past; an existing task keeps its date pickable.
                              final first = widget.taskToEdit == null
                                  ? today
                                  : (_dueDate != null && _dueDate!.isBefore(today) ? _dueDate! : today);
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _dueDate != null && !_dueDate!.isBefore(first) ? _dueDate! : first,
                                firstDate: first,
                                lastDate: DateTime(today.year + 5),
                              );
                              if (picked != null) {
                                setState(() => _dueDate = picked);
                                _validate();
                              }
                            },
                            child: Container(
                              height: 42,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _dueDateError != null ? AppColors.danger : AppColors.border,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _dueDate != null ? formatDate(_dueDate) : 'No due date',
                                    style: AppTypography.caption.copyWith(color: _dueDate != null ? AppColors.ink : AppColors.textTertiary),
                                  ),
                                  const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          if (_dueDateError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Text(_dueDateError!, style: AppTypography.label.copyWith(color: AppColors.dangerInk)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Actions: Cancel & Create Task
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                            : Text(widget.taskToEdit != null ? 'Save' : 'Create task'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: AppTypography.bodyStrong.copyWith(fontSize: 13),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, String? errorText}) {
    return InputDecoration(
      hintText: hint,
      errorText: errorText,
      hintStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
    );
  }
}
