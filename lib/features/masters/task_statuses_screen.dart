import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/reference_components.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import 'masters_repository.dart';
import 'models/masters_models.dart';
import 'widgets/access_restricted_view.dart';

class TaskStatusesScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const TaskStatusesScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<TaskStatusesScreen> createState() => _TaskStatusesScreenState();
}

class _TaskStatusesScreenState extends ConsumerState<TaskStatusesScreen> {
  final MastersRepository _repository = MastersRepository();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isReordering = false;
  String? _errorMessage;

  List<TaskStatus> _allStatuses = [];
  String _searchQuery = '';
  String _selectedCategory = 'all'; // all | todo | in_progress | done

  @override
  void initState() {
    super.initState();
    _fetchStatuses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchStatuses() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _repository.getTaskStatuses();
      if (mounted) {
        setState(() {
          _allStatuses = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  List<TaskStatus> get _filteredStatuses {
    return _allStatuses.where((s) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase().trim();
        final matches = s.name.toLowerCase().contains(q) || s.slug.toLowerCase().contains(q);
        if (!matches) return false;
      }
      if (_selectedCategory != 'all') {
        final cat = s.statusCategory.toLowerCase().trim();
        if (_selectedCategory == 'done') {
          if (cat != 'done' && cat != 'completed') return false;
        } else if (_selectedCategory == 'in_progress') {
          if (cat != 'in_progress' && cat != 'inprogress' && cat != 'doing' && cat != 'testing') return false;
        } else if (_selectedCategory == 'todo') {
          if (cat == 'done' || cat == 'completed' || cat == 'in_progress' || cat == 'inprogress') return false;
        }
      }
      return true;
    }).toList();
  }

  Future<void> _reorder(int currentIndex, int targetIndex, List<TaskStatus> currentList) async {
    if (_isReordering || targetIndex < 0 || targetIndex >= currentList.length) return;

    setState(() => _isReordering = true);

    try {
      final updatedList = List<TaskStatus>.from(currentList);
      final item = updatedList.removeAt(currentIndex);
      updatedList.insert(targetIndex, item);

      final statusIds = updatedList.map((s) => s.id).toList();
      await _repository.reorderTaskStatuses(statusIds);
      await _fetchStatuses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reorder: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isReordering = false);
      }
    }
  }

  void _openCreateOrEditDialog({TaskStatus? status}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaskStatusDialog(
        status: status,
        existingCount: _allStatuses.length,
        onSuccess: _fetchStatuses,
      ),
    );
  }

  Future<void> _confirmDelete(TaskStatus status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Delete Task Status?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(
            'Are you sure you want to delete status "${status.name}"? Tasks associated with this status may need to be migrated.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _repository.deleteTaskStatus(status.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Task status "${status.name}" deleted successfully'), backgroundColor: AppColors.success),
          );
          _fetchStatuses();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete status: $e'), backgroundColor: AppColors.danger),
          );
        }
      }
    }
  }

  Widget _buildCategoryBadge(String catLabel) {
    Color bg;
    Color fg;
    IconData icon;

    switch (catLabel) {
      case 'Done':
        bg = AppColors.successSoft;
        fg = AppColors.successInk;
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'In Progress':
        bg = AppColors.infoSoft;
        fg = AppColors.info;
        icon = Icons.access_time_rounded;
        break;
      case 'To Do':
      default:
        bg = AppColors.surfaceMuted;
        fg = AppColors.textSecondary;
        icon = Icons.circle_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
          Text(catLabel, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    if (!canManageTaskStatuses(user)) {
      return Scaffold(
        appBar: pageAppBar(context, title: 'Task Statuses'),
        body: const AccessRestrictedView(title: 'Task Statuses Access Restricted'),
      );
    }

    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final filtered = _filteredStatuses;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchStatuses,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageHeader(
                        title: 'Task Statuses',
                        subtitle: 'Workflow states and colors',
                        showBack: widget.showBackButton && Navigator.canPop(context),
                        padding: const EdgeInsets.only(bottom: 16),
                        actions: [
                          CircularIconButton(
                            icon: Icons.add_rounded,
                            backgroundColor: AppColors.primary,
                            iconColor: AppColors.onPrimary,
                            onTap: () => _openCreateOrEditDialog(),
                          ),
                        ],
                      ),

                      // Filters
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 560;

                            final searchField = TextField(
                              controller: _searchController,
                              onChanged: (val) => setState(() => _searchQuery = val),
                              style: TextStyle(color: primaryTextColor, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Search by status name or slug...',
                                hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                                prefixIcon: Icon(Icons.search_rounded, size: 18, color: secondaryTextColor),
                                filled: true,
                                fillColor: AppColors.surfaceMuted,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                              ),
                            );

                            final categoryDropdown = Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedCategory,
                                  dropdownColor: cardBg,
                                  style: TextStyle(color: primaryTextColor, fontSize: 13),
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All Categories')),
                                    DropdownMenuItem(value: 'todo', child: Text('To Do')),
                                    DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                                    DropdownMenuItem(value: 'done', child: Text('Done')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedCategory = val);
                                  },
                                ),
                              ),
                            );

                            final countText = Text(
                              '${filtered.length} status${filtered.length == 1 ? '' : 'es'}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryTextColor),
                            );

                            if (isWide) {
                              return Row(
                                children: [
                                  Expanded(child: searchField),
                                  const SizedBox(width: 12),
                                  categoryDropdown,
                                  const SizedBox(width: 14),
                                  countText,
                                ],
                              );
                            } else {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  searchField,
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      categoryDropdown,
                                      countText,
                                    ],
                                  ),
                                ],
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Content Area
              if (_isLoading && _allStatuses.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              else if (_errorMessage != null && _allStatuses.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
                        const SizedBox(height: 12),
                        Text('Failed to load task statuses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor)),
                        const SizedBox(height: 6),
                        Text(_errorMessage!, style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _fetchStatuses, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 32),
                    child: Container(
                      padding: const EdgeInsets.all(48),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.list_alt_rounded, size: 56, color: AppColors.textTertiary),
                          const SizedBox(height: 14),
                          Text('No task statuses found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryTextColor)),
                          const SizedBox(height: 6),
                          Text(
                            _searchQuery.isNotEmpty ? 'No statuses match "$_searchQuery".' : 'Create task statuses to define workflows for tasks.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: secondaryTextColor),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () => _openCreateOrEditDialog(),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add Task Status', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 24,
                          headingRowHeight: 50,
                          dataRowMinHeight: 56,
                          dataRowMaxHeight: 64,
                          columns: const [
                            DataColumn(label: Text('SR. NO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                            DataColumn(label: Text('STATUS NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                            DataColumn(label: Text('SLUG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                            DataColumn(label: Text('CATEGORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                            DataColumn(label: Text('DEFAULT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                            DataColumn(label: Text('ORDER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                            DataColumn(label: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5))),
                          ],
                          rows: List.generate(filtered.length, (idx) {
                            final s = filtered[idx];
                            final color = s.parsedColor;

                            return DataRow(
                              cells: [
                                DataCell(Text('${idx + 1}', style: TextStyle(fontSize: 13, color: secondaryTextColor))),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(s.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primaryTextColor)),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceMuted,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Text(
                                      s.slug,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: primaryTextColor,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(_buildCategoryBadge(s.categoryBadge)),
                                DataCell(
                                  s.isDefault
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.dangerSoft,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            '✓ DEFAULT',
                                            style: TextStyle(color: AppColors.danger, fontSize: 10, fontWeight: FontWeight.w700),
                                          ),
                                        )
                                      : Text('—', style: TextStyle(color: secondaryTextColor)),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${s.orderIndex}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor)),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        color: idx > 0 ? primaryTextColor : secondaryTextColor.withValues(alpha: 0.3),
                                        onPressed: idx > 0 ? () => _reorder(idx, idx - 1, filtered) : null,
                                      ),
                                      const SizedBox(width: 6),
                                      IconButton(
                                        icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        color: idx < filtered.length - 1 ? primaryTextColor : secondaryTextColor.withValues(alpha: 0.3),
                                        onPressed: idx < filtered.length - 1 ? () => _reorder(idx, idx + 1, filtered) : null,
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => _openCreateOrEditDialog(status: s),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        child: Text('Edit', style: TextStyle(fontSize: 12, color: primaryTextColor)),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        color: AppColors.danger.withValues(alpha: 0.8),
                                        onPressed: () => _confirmDelete(s),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

// Dialog for Create & Edit Task Status
class _TaskStatusDialog extends StatefulWidget {
  final TaskStatus? status;
  final int existingCount;
  final VoidCallback onSuccess;

  const _TaskStatusDialog({
    this.status,
    required this.existingCount,
    required this.onSuccess,
  });

  @override
  State<_TaskStatusDialog> createState() => _TaskStatusDialogState();
}

class _TaskStatusDialogState extends State<_TaskStatusDialog> {
  final _nameController = TextEditingController();
  final _slugController = TextEditingController();
  final _colorHexController = TextEditingController(text: '#8B5CF6');
  final _orderController = TextEditingController();

  String _statusCategory = 'in_progress';
  bool _isDefault = false;
  String _selectedColorHex = '#8B5CF6';
  bool _manualSlug = false;
  bool _isSaving = false;

  static const List<String> _colorPresets = [
    '#8B5CF6',
    '#6366F1',
    '#3B82F6',
    '#06B6D4',
    '#14B8A6',
    '#10B981',
    '#F59E0B',
    '#F97316',
    '#EF4444',
    '#EC4899',
    '#64748B',
    '#374151',
  ];

  bool get isEdit => widget.status != null;

  @override
  void initState() {
    super.initState();
    if (widget.status != null) {
      final s = widget.status!;
      _nameController.text = s.name;
      _slugController.text = s.slug;
      _selectedColorHex = s.color;
      _colorHexController.text = s.color;
      _statusCategory = s.statusCategory;
      _isDefault = s.isDefault;
      _orderController.text = s.orderIndex.toString();
      _manualSlug = true;
    } else {
      _orderController.text = (widget.existingCount + 1).toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _colorHexController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  void _onNameChanged(String val) {
    if (!_manualSlug) {
      final gen = generateSlug(val);
      _slugController.text = gen;
    }
    setState(() {});
  }

  void _selectColor(String hex) {
    setState(() {
      _selectedColorHex = hex;
      _colorHexController.text = hex;
    });
  }

  Future<void> _submit() async {
    final nameTrimmed = _nameController.text.trim();
    if (nameTrimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status name is required')),
      );
      return;
    }

    final slugTrimmed = _slugController.text.trim().isNotEmpty
        ? _slugController.text.trim()
        : generateSlug(nameTrimmed);

    final order = int.tryParse(_orderController.text.trim()) ?? 1;

    setState(() => _isSaving = true);

    try {
      if (isEdit) {
        await MastersRepository().updateTaskStatus(
          widget.status!.id,
          name: nameTrimmed,
          slug: slugTrimmed,
          color: _selectedColorHex,
          statusCategory: _statusCategory,
          isDefault: _isDefault,
          orderIndex: order,
        );
      } else {
        await MastersRepository().createTaskStatus(
          name: nameTrimmed,
          slug: slugTrimmed,
          color: _selectedColorHex,
          statusCategory: _statusCategory,
          isDefault: _isDefault,
          orderIndex: order,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Task status updated successfully' : 'Task status created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save status: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogBg = Colors.white;
    final borderColor = AppColors.border;
    final fieldBg = Colors.white;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final activeColor = parseHexColor(_selectedColorHex);
    final previewName = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Preview Status';

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Edit Task Status' : 'Create Task Status',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add a new task workflow status available across projects.',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: borderColor)),
                      child: Icon(Icons.close_rounded, size: 18, color: secondaryTextColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Live Badge Preview
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'BADGE PREVIEW',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: activeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: activeColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(
                            previewName,
                            style: TextStyle(color: activeColor, fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // STATUS NAME *
              Row(
                children: [
                  Text('STATUS NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor)),
                  const SizedBox(width: 4),
                  const Text('*', style: TextStyle(fontSize: 14, color: AppColors.danger)),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                onChanged: _onNameChanged,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. QA / Testing, In Review, Blocked',
                  hintStyle: TextStyle(color: secondaryTextColor, fontSize: 14),
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                ),
              ),
              const SizedBox(height: 16),

              // SLUG (IDENTIFIER)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('SLUG (IDENTIFIER)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor)),
                  Text('Auto-generated if empty', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _slugController,
                onChanged: (_) => setState(() => _manualSlug = true),
                style: TextStyle(color: primaryTextColor, fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'e.g. qa_testing',
                  hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                ),
              ),
              const SizedBox(height: 16),

              // STATUS CATEGORY
              Text('STATUS CATEGORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('category_$_statusCategory'),
                initialValue: _statusCategory,
                isExpanded: true,
                style: TextStyle(color: primaryTextColor, fontSize: 13),
                dropdownColor: dialogBg,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                ),
                items: const [
                  DropdownMenuItem(value: 'todo', child: Text('To Do — backlog/pending')),
                  DropdownMenuItem(value: 'in_progress', child: Text('In Progress — active/review')),
                  DropdownMenuItem(value: 'done', child: Text('Completed / Done')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _statusCategory = val);
                },
              ),
              const SizedBox(height: 16),

              // COLOR TOKEN
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('COLOR TOKEN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor)),
                  Text(_selectedColorHex, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colorPresets.map((hex) {
                  final c = parseHexColor(hex);
                  final isSelected = hex.toLowerCase() == _selectedColorHex.toLowerCase();
                  return InkWell(
                    onTap: () => _selectColor(hex),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: isSelected ? Colors.white : Colors.transparent, width: 2),
                        boxShadow: isSelected ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)] : null,
                      ),
                      child: isSelected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _colorHexController,
                      onChanged: (val) {
                        if (val.trim().isNotEmpty) {
                          setState(() => _selectedColorHex = val.trim());
                        }
                      },
                      style: TextStyle(color: primaryTextColor, fontSize: 13, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: '#8B5CF6',
                        filled: true,
                        fillColor: fieldBg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: borderColor)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // DEFAULT STATUS SWITCH & ORDER INDEX
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: fieldBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Default Status', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primaryTextColor)),
                                const SizedBox(height: 2),
                                Text('Apply to new tasks', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isDefault,
                            activeThumbColor: AppColors.primary,
                            onChanged: (val) => setState(() => _isDefault = val),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ORDER INDEX', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: primaryTextColor)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _orderController,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: primaryTextColor, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '1',
                            filled: true,
                            fillColor: fieldBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Actions
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryTextColor,
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                        : Text(isEdit ? 'Save Changes' : 'Create Status', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
