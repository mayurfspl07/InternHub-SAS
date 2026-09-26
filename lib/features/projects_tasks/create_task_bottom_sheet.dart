import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../shared/models/project_model.dart';
import '../../core/constants/app_colors.dart';

class CreateTaskBottomSheet extends ConsumerStatefulWidget {
  final ProjectModel? project;
  final TaskModel? taskToEdit;
  final VoidCallback? onTaskCreated;

  const CreateTaskBottomSheet({
    super.key,
    this.project,
    this.taskToEdit,
    this.onTaskCreated,
  });

  @override
  ConsumerState<CreateTaskBottomSheet> createState() => _CreateTaskBottomSheetState();
}

class _CreateTaskBottomSheetState extends ConsumerState<CreateTaskBottomSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _assigneeSearchController = TextEditingController();

  String _selectedStatus = 'todo';
  List<TaskStatusColumn> _taskStatuses = [];
  String _selectedPriority = 'medium';
  DateTime? _dueDate;

  String? _selectedAssigneeId;

  bool _isLoading = true;
  bool _isSubmitting = false;

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

  Future<void> _loadStatuses() async {
    try {
      final res = await ApiClient().get('/api/projects/task-statuses');
      List<TaskStatusColumn> cols = [];
      if (res is List) {
        cols = res.whereType<Map<String, dynamic>>().map((c) => TaskStatusColumn.fromJson(c)).toList();
      } else if (res is Map<String, dynamic>) {
        final items = res['statuses'] ?? res['items'] ?? res['data'];
        if (items is List) {
          cols = items.whereType<Map<String, dynamic>>().map((c) => TaskStatusColumn.fromJson(c)).toList();
        }
      }

      if (cols.isEmpty) {
        cols = TaskStatusColumn.fallbackColumns();
      }

      if (mounted) {
        setState(() {
          _taskStatuses = cols;
          if (widget.taskToEdit == null) {
            _selectedStatus = cols.firstWhere((c) => c.isDefault, orElse: () => cols.first).key;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _taskStatuses = TaskStatusColumn.fallbackColumns();
          if (widget.taskToEdit == null) {
            _selectedStatus = 'todo';
          }
          _isLoading = false;
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
        _assigneeError = 'Assignee is required';
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
    });
  }

  Future<void> _submit() async {
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
            content: Text(e is ApiException ? e.message : 'Failed: $e'),
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
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.all(22),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header matching screenshot 4
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.taskToEdit != null ? 'Edit Task' : 'Create New Task',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Scrollable Body
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title *
                          _buildLabel('TITLE *'),
                          TextField(
                            controller: _titleController,
                            onChanged: (_) => _validate(),
                            style: TextStyle(fontSize: 13, color: AppColors.ink),
                            decoration: _inputDecoration(
                              hint: 'e.g. Implement authentication middleware',
                              errorText: _titleError,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Notes / Description
                          _buildLabel('NOTES / DESCRIPTION'),
                          TextField(
                            controller: _descController,
                            maxLines: 3,
                            onChanged: (_) => _validate(),
                            style: TextStyle(fontSize: 13, color: AppColors.ink),
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
                                    _buildLabel('STATUS'),
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
                                          dropdownColor: Colors.white,
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
                                                  Text(s.title, style: TextStyle(fontSize: 13, color: AppColors.ink)),
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
                                    _buildLabel('PRIORITY'),
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
                                          dropdownColor: Colors.white,
                                          items: const [
                                            DropdownMenuItem(value: 'low', child: Text('Low Priority')),
                                            DropdownMenuItem(value: 'medium', child: Text('Medium Priority')),
                                            DropdownMenuItem(value: 'high', child: Text('High Priority')),
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
                          _buildLabel('ASSIGNEE *'),
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
                                    style: TextStyle(fontSize: 12, color: AppColors.ink),
                                    decoration: InputDecoration(
                                      hintText: 'Search intern name...',
                                      hintStyle: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                      prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textTertiary),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.zero,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: AppColors.border),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 110,
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
                                            color: isSelected
                                                ? AppColors.lavender
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: isSelected ? AppColors.info : AppColors.border,
                                              width: isSelected ? 1.5 : 1.0,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                mem['name']?.toString() ?? 'Member',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                  color: isSelected ? AppColors.info : AppColors.ink,
                                                ),
                                              ),
                                              Text(
                                                mem['email']?.toString() ?? '',
                                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                              ),
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
                              child: Text(_assigneeError!, style: const TextStyle(fontSize: 11, color: AppColors.danger)),
                            ),
                          const SizedBox(height: 14),

                          // Due Date
                          _buildLabel('DUE DATE'),
                          InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _dueDate ?? DateTime.now(),
                                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                lastDate: DateTime(2035),
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
                                    _dueDate != null ? DateFormat('dd/MM/yyyy').format(_dueDate!) : 'dd/mm/yyyy',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _dueDate != null ? AppColors.ink : AppColors.textTertiary,
                                    ),
                                  ),
                                  const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                          if (_dueDateError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Text(_dueDateError!, style: const TextStyle(fontSize: 11, color: AppColors.danger)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Actions: Cancel & Create Task
                  Wrap(
                    alignment: WrapAlignment.end,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2))
                            : Text(widget.taskToEdit != null ? 'Update Task' : 'Create Task', style: const TextStyle(fontWeight: FontWeight.bold)),
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, String? errorText}) {
    return InputDecoration(
      hintText: hint,
      errorText: errorText,
      hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
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
