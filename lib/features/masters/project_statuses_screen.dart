import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/reference_components.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import 'masters_repository.dart';
import 'models/masters_models.dart';
import 'widgets/access_restricted_view.dart';

class ProjectStatusesScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const ProjectStatusesScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<ProjectStatusesScreen> createState() => _ProjectStatusesScreenState();
}

class _ProjectStatusesScreenState extends ConsumerState<ProjectStatusesScreen> {
  final MastersRepository _repository = MastersRepository();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isReordering = false;
  String? _errorMessage;

  List<ProjectStatus> _allStatuses = [];
  String _searchQuery = '';

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
      final list = await _repository.getProjectStatuses();
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

  List<ProjectStatus> get _filteredStatuses {
    if (_searchQuery.isEmpty) return _allStatuses;
    final q = _searchQuery.toLowerCase().trim();
    return _allStatuses.where((s) {
      return s.name.toLowerCase().contains(q) || s.slug.toLowerCase().contains(q);
    }).toList();
  }

  // Active projects count
  int get _activeProjectsCount {
    return _allStatuses.fold(0, (sum, s) => sum + s.projectCount);
  }

  // Default status
  ProjectStatus? get _defaultStatus {
    try {
      return _allStatuses.firstWhere((s) => s.isDefault);
    } catch (_) {
      return null;
    }
  }

  Future<void> _reorder(int originalIndex, int targetIndex) async {
    if (_isReordering || targetIndex < 0 || targetIndex >= _allStatuses.length) return;
    if (_searchQuery.trim().isNotEmpty) return; // Disabled during search

    setState(() => _isReordering = true);

    try {
      final updatedList = List<ProjectStatus>.from(_allStatuses);
      final item = updatedList.removeAt(originalIndex);
      updatedList.insert(targetIndex, item);

      final statusIds = updatedList.map((s) => s.id).toList();
      await _repository.reorderProjectStatuses(statusIds);
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

  void _openCreateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateProjectStatusDialog(
        existingCount: _allStatuses.length,
        onSuccess: _fetchStatuses,
      ),
    );
  }

  void _openEditDialog(ProjectStatus status) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditProjectStatusDialog(
        status: status,
        onSuccess: _fetchStatuses,
      ),
    );
  }

  Future<void> _confirmDelete(ProjectStatus status) async {
    final hasProjects = status.projectCount > 0;
    final isDefault = status.isDefault;
    final isBlocked = hasProjects || isDefault;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            isBlocked ? 'Cannot Delete Status' : 'Delete Project Status?',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDefault)
                const Text(
                  '• This status is currently set as the default project status. Assign another status as default before deleting.',
                  style: TextStyle(fontSize: 14, color: AppColors.danger),
                ),
              if (hasProjects)
                Padding(
                  padding: EdgeInsets.only(top: isDefault ? 8.0 : 0.0),
                  child: Text(
                    '• There are ${status.projectCount} active projects assigned to this status bucket. Reassign them before deleting.',
                    style: const TextStyle(fontSize: 14, color: AppColors.danger),
                  ),
                ),
              if (!isBlocked)
                Text(
                  'Are you sure you want to delete status "${status.name}"? This action cannot be undone.',
                  style: const TextStyle(fontSize: 14),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isBlocked ? 'Dismiss' : 'Cancel'),
            ),
            if (!isBlocked)
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Delete'),
              ),
          ],
        );
      },
    );

    if (confirmed == true && !isBlocked) {
      try {
        await _repository.deleteProjectStatus(status.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Project status "${status.name}" deleted successfully'),
              backgroundColor: AppColors.success,
            ),
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

  Widget _buildStatusPill(ProjectStatus status) {
    final color = status.parsedColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.name,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    if (!canManageProjectStatuses(user)) {
      return Scaffold(
        appBar: pageAppBar(context, title: 'Project Statuses'),
        body: const AccessRestrictedView(title: 'Project Statuses Access Restricted'),
      );
    }

    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final filtered = _filteredStatuses;
    final defStatus = _defaultStatus;

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
                        title: 'Project Statuses',
                        subtitle: 'Project lifecycle stages',
                        showBack: widget.showBackButton && Navigator.canPop(context),
                        padding: const EdgeInsets.only(bottom: 16),
                        actions: [
                          CircularIconButton(
                            icon: Icons.add_rounded,
                            backgroundColor: AppColors.primary,
                            iconColor: AppColors.onPrimary,
                            onTap: _openCreateDialog,
                          ),
                        ],
                      ),

                      // Metric Cards (3)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 700;
                          final card1 = _buildMetricCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            primaryTextColor: primaryTextColor,
                            secondaryTextColor: secondaryTextColor,
                            iconBg: AppColors.warningSoft,
                            iconColor: AppColors.warning,
                            icon: Icons.layers_outlined,
                            title: 'TOTAL STATUSES',
                            valueWidget: Text(
                              '${_allStatuses.length}',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                          );

                          final card2 = _buildMetricCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            primaryTextColor: primaryTextColor,
                            secondaryTextColor: secondaryTextColor,
                            iconBg: AppColors.infoSoft,
                            iconColor: AppColors.info,
                            icon: Icons.folder_open_rounded,
                            title: 'ACTIVE PROJECTS',
                            valueWidget: Text(
                              '$_activeProjectsCount',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                          );

                          final card3 = _buildMetricCard(
                            cardBg: cardBg,
                            borderColor: borderColor,
                            primaryTextColor: primaryTextColor,
                            secondaryTextColor: secondaryTextColor,
                            iconBg: AppColors.successSoft,
                            iconColor: AppColors.success,
                            icon: Icons.auto_awesome_rounded,
                            title: 'DEFAULT STATUS',
                            valueWidget: defStatus != null
                                ? _buildStatusPill(defStatus)
                                : Text('None set', style: TextStyle(fontSize: 14, color: secondaryTextColor, fontWeight: FontWeight.w600)),
                          );

                          if (isWide) {
                            return Row(
                              children: [
                                Expanded(child: card1),
                                const SizedBox(width: 16),
                                Expanded(child: card2),
                                const SizedBox(width: 16),
                                Expanded(child: card3),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                card1,
                                const SizedBox(height: 10),
                                card2,
                                const SizedBox(height: 10),
                                card3,
                              ],
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Filter & Table Container
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar & Counter
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 42,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: borderColor),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, size: 18, color: secondaryTextColor),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        onChanged: (val) => setState(() => _searchQuery = val),
                                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                                        decoration: InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                          border: InputBorder.none,
                                          filled: false,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          hintText: 'Search statuses by name or slug...',
                                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                                        ),
                                      ),
                                    ),
                                    if (_searchQuery.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                        child: Icon(Icons.close, size: 16, color: secondaryTextColor),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              'Showing ${filtered.length} of ${_allStatuses.length} status buckets',
                              style: TextStyle(fontSize: 12, color: secondaryTextColor, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Table or State
                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(Icons.error_outline, size: 36, color: AppColors.danger),
                                  const SizedBox(height: 8),
                                  Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
                                  const SizedBox(height: 12),
                                  ElevatedButton(
                                    onPressed: _fetchStatuses,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.layers_clear_outlined, size: 48, color: secondaryTextColor.withValues(alpha: 0.5)),
                                  const SizedBox(height: 10),
                                  Text(
                                    _searchQuery.isNotEmpty ? 'No project statuses match your search.' : 'No project statuses configured yet.',
                                    style: TextStyle(color: secondaryTextColor, fontSize: 14),
                                  ),
                                  if (_searchQuery.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      child: const Text('Clear search'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 900),
                              child: DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  AppColors.surfaceMuted,
                                ),
                                headingTextStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: secondaryTextColor,
                                ),
                                dataRowMinHeight: 56,
                                dataRowMaxHeight: 64,
                                horizontalMargin: 16,
                                columnSpacing: 24,
                                columns: const [
                                  DataColumn(label: Text('SR. NO')),
                                  DataColumn(label: Text('STATUS NAME & BADGE')),
                                  DataColumn(label: Text('COLOR HEX')),
                                  DataColumn(label: Text('PROJECTS COUNT')),
                                  DataColumn(label: Text('DEFAULT')),
                                  DataColumn(label: Text('TYPE')),
                                  DataColumn(label: Text('ORDER')),
                                  DataColumn(label: Text('ACTIONS')),
                                ],
                                rows: List.generate(filtered.length, (index) {
                                  final status = filtered[index];
                                  final originalIndex = _allStatuses.indexOf(status);
                                  final canReorder = _searchQuery.isEmpty && !_isReordering;
                                  final isFirst = originalIndex == 0;
                                  final isLast = originalIndex == _allStatuses.length - 1;

                                  final canDelete = !status.isDefault && status.projectCount == 0;

                                  return DataRow(
                                    cells: [
                                      // SR. NO
                                      DataCell(
                                        Text(
                                          '${index + 1}',
                                          style: TextStyle(fontSize: 12, color: secondaryTextColor, fontWeight: FontWeight.w600),
                                        ),
                                      ),

                                      // STATUS NAME & BADGE + slug
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildStatusPill(status),
                                            const SizedBox(width: 8),
                                            Text(
                                              '(${status.slug})',
                                              style: GoogleFonts.robotoMono(
                                                fontSize: 11,
                                                color: secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // COLOR HEX
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: status.parsedColor,
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              status.color.toUpperCase(),
                                              style: GoogleFonts.robotoMono(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: primaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // PROJECTS COUNT
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceMuted,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: borderColor),
                                          ),
                                          child: Text(
                                            '${status.projectCount}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: primaryTextColor,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // DEFAULT
                                      DataCell(
                                        status.isDefault
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppColors.successSoft,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.check, size: 12, color: AppColors.successInk),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Default',
                                                      style: TextStyle(
                                                        color: AppColors.successInk,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : Text('—', style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                                      ),

                                      // TYPE (SYSTEM vs CUSTOM)
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: status.isSystem ? AppColors.surfaceMuted : AppColors.warningSoft,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: status.isSystem ? AppColors.border : AppColors.primarySoft,
                                            ),
                                          ),
                                          child: Text(
                                            status.isSystem ? 'SYSTEM' : 'CUSTOM',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                              color: status.isSystem ? AppColors.textSecondary : AppColors.warningInk,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // ORDER (Up / Down)
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                              color: (canReorder && !isFirst) ? primaryTextColor : secondaryTextColor.withValues(alpha: 0.3),
                                              onPressed: (canReorder && !isFirst)
                                                  ? () => _reorder(originalIndex, originalIndex - 1)
                                                  : null,
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                                              color: (canReorder && !isLast) ? primaryTextColor : secondaryTextColor.withValues(alpha: 0.3),
                                              onPressed: (canReorder && !isLast)
                                                  ? () => _reorder(originalIndex, originalIndex + 1)
                                                  : null,
                                            ),
                                          ],
                                        ),
                                      ),

                                      // ACTIONS
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Edit Button
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                border: Border.all(color: borderColor),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: IconButton(
                                                icon: const Icon(Icons.edit_outlined, size: 16),
                                                padding: EdgeInsets.zero,
                                                color: primaryTextColor,
                                                tooltip: 'Edit Status',
                                                onPressed: () => _openEditDialog(status),
                                              ),
                                            ),
                                            const SizedBox(width: 8),

                                            // Delete Button
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: canDelete ? AppColors.danger.withValues(alpha: 0.3) : borderColor,
                                                ),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: IconButton(
                                                icon: Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 16,
                                                  color: canDelete ? AppColors.danger : secondaryTextColor.withValues(alpha: 0.3),
                                                ),
                                                padding: EdgeInsets.zero,
                                                tooltip: canDelete ? 'Delete Status' : 'Cannot delete default or assigned status',
                                                onPressed: () => _confirmDelete(status),
                                              ),
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
                      ],
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 40),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required Color iconBg,
    required Color iconColor,
    required IconData icon,
    required String title,
    required Widget valueWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                valueWidget,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CREATE DIALOG (Separate from Edit)
// ============================================================================
class _CreateProjectStatusDialog extends StatefulWidget {
  final int existingCount;
  final VoidCallback onSuccess;

  const _CreateProjectStatusDialog({
    required this.existingCount,
    required this.onSuccess,
  });

  @override
  State<_CreateProjectStatusDialog> createState() => _CreateProjectStatusDialogState();
}

class _CreateProjectStatusDialogState extends State<_CreateProjectStatusDialog> {
  final MastersRepository _repository = MastersRepository();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _slugController = TextEditingController();
  final TextEditingController _orderController = TextEditingController();
  final TextEditingController _hexController = TextEditingController();

  String _selectedColor = '#3B82F6';
  bool _isDefault = false;
  bool _slugManuallyEdited = false;
  bool _isSubmitting = false;

  final List<String> _colorPresets = [
    '#3B82F6', '#6366F1', '#8B5CF6', '#EC4899', '#EF4444',
    '#F97316', '#F59E0B', '#10B981', '#14B8A6', '#06B6D4',
    '#64748B', '#1F2937',
  ];

  @override
  void initState() {
    super.initState();
    _hexController.text = _selectedColor;
    _orderController.text = '${widget.existingCount + 1}';

    _nameController.addListener(() {
      if (!_slugManuallyEdited) {
        _slugController.text = generateSlug(_nameController.text);
      }
      setState(() {});
    });

    _slugController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _orderController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status name is required'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final slug = _slugController.text.trim().isNotEmpty ? _slugController.text.trim() : generateSlug(name);
    final order = int.tryParse(_orderController.text.trim()) ?? (widget.existingCount + 1);

    setState(() => _isSubmitting = true);

    try {
      await _repository.createProjectStatus(
        name: name,
        slug: slug,
        color: _selectedColor,
        orderIndex: order,
        isDefault: _isDefault,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status "$name" created successfully'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final currentColor = parseHexColor(_selectedColor, fallback: AppColors.info);
    final displayName = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : 'Preview Status';

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create Project Status',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Add a new project status workflow bucket.',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: secondaryTextColor,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge Preview
                      Text(
                        'BADGE PREVIEW',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: currentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: currentColor.withValues(alpha: 0.4), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: currentColor, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  displayName,
                                  style: TextStyle(color: currentColor, fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Status Name *
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          children: const [
                            TextSpan(text: 'STATUS NAME '),
                            TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. Planning, In Development, QA',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Slug (Identifier)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'SLUG (IDENTIFIER)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Auto-generated if empty',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _slugController,
                        onChanged: (_) => _slugManuallyEdited = true,
                        style: GoogleFonts.robotoMono(fontSize: 12, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. planning',
                          hintStyle: GoogleFonts.robotoMono(fontSize: 12, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Color Token
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'COLOR TOKEN',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                          Text(_selectedColor.toUpperCase(), style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _colorPresets.map((hex) {
                          final color = parseHexColor(hex);
                          final isSel = _selectedColor.toLowerCase() == hex.toLowerCase();
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColor = hex;
                                _hexController.text = hex;
                              });
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSel ? primaryTextColor : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: isSel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: currentColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _hexController,
                              style: GoogleFonts.robotoMono(fontSize: 12, color: primaryTextColor),
                              decoration: InputDecoration(
                                hintText: '#3B82F6',
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onChanged: (val) {
                                if (val.startsWith('#') && (val.length == 7 || val.length == 9)) {
                                  setState(() => _selectedColor = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Default Status Switch
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Default Status',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryTextColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Apply to new projects automatically',
                                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isDefault,
                              onChanged: (v) => setState(() => _isDefault = v),
                              activeThumbColor: AppColors.success,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Order Index
                      Text(
                        'ORDER INDEX',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _orderController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: '1',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),
            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
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
                      backgroundColor: AppColors.primary, // Amber yellow
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.warning, width: 1),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                        : const Text('Create Status', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// EDIT DIALOG (Separate from Create)
// ============================================================================
class _EditProjectStatusDialog extends StatefulWidget {
  final ProjectStatus status;
  final VoidCallback onSuccess;

  const _EditProjectStatusDialog({
    required this.status,
    required this.onSuccess,
  });

  @override
  State<_EditProjectStatusDialog> createState() => _EditProjectStatusDialogState();
}

class _EditProjectStatusDialogState extends State<_EditProjectStatusDialog> {
  final MastersRepository _repository = MastersRepository();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _slugController;
  late TextEditingController _orderController;
  late TextEditingController _hexController;

  late String _selectedColor;
  late bool _isDefault;
  bool _isSubmitting = false;

  final List<String> _colorPresets = [
    '#3B82F6', '#6366F1', '#8B5CF6', '#EC4899', '#EF4444',
    '#F97316', '#F59E0B', '#10B981', '#14B8A6', '#06B6D4',
    '#64748B', '#1F2937',
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.status.color;
    _isDefault = widget.status.isDefault;

    _nameController = TextEditingController(text: widget.status.name);
    _slugController = TextEditingController(text: widget.status.slug);
    _orderController = TextEditingController(text: '${widget.status.orderIndex}');
    _hexController = TextEditingController(text: _selectedColor);

    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _orderController.dispose();
    _hexController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status name is required'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final slug = _slugController.text.trim().isNotEmpty ? _slugController.text.trim() : generateSlug(name);
    final order = int.tryParse(_orderController.text.trim()) ?? widget.status.orderIndex;

    setState(() => _isSubmitting = true);

    try {
      await _repository.updateProjectStatus(
        widget.status.id,
        name: name,
        slug: slug,
        color: _selectedColor,
        orderIndex: order,
        isDefault: _isDefault,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status "$name" updated successfully'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final currentColor = parseHexColor(_selectedColor, fallback: AppColors.info);
    final displayName = _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : widget.status.name;

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Project Status',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Update project status properties and color indicator.',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: secondaryTextColor,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge Preview
                      Text(
                        'BADGE PREVIEW',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: currentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: currentColor.withValues(alpha: 0.4), width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: currentColor, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  displayName,
                                  style: TextStyle(color: currentColor, fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Status Name *
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          children: const [
                            TextSpan(text: 'STATUS NAME '),
                            TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. Planning, In Development, QA',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Slug (Identifier)
                      Text(
                        'SLUG (IDENTIFIER)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _slugController,
                        style: GoogleFonts.robotoMono(fontSize: 12, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. planning',
                          hintStyle: GoogleFonts.robotoMono(fontSize: 12, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Color Token
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'COLOR TOKEN',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                          Text(_selectedColor.toUpperCase(), style: GoogleFonts.robotoMono(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _colorPresets.map((hex) {
                          final color = parseHexColor(hex);
                          final isSel = _selectedColor.toLowerCase() == hex.toLowerCase();
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColor = hex;
                                _hexController.text = hex;
                              });
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSel ? primaryTextColor : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: isSel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: currentColor,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _hexController,
                              style: GoogleFonts.robotoMono(fontSize: 12, color: primaryTextColor),
                              decoration: InputDecoration(
                                hintText: '#3B82F6',
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              onChanged: (val) {
                                if (val.startsWith('#') && (val.length == 7 || val.length == 9)) {
                                  setState(() => _selectedColor = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Default Status Switch
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Default Status',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryTextColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Apply to new projects automatically',
                                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isDefault,
                              onChanged: (v) => setState(() => _isDefault = v),
                              activeThumbColor: AppColors.success,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Order Index
                      Text(
                        'ORDER INDEX',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _orderController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: '1',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),
            // Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
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
                      backgroundColor: AppColors.primary, // Amber yellow
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.warning, width: 1),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                        : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
