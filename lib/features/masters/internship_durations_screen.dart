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

class InternshipDurationsScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const InternshipDurationsScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<InternshipDurationsScreen> createState() => _InternshipDurationsScreenState();
}

class _InternshipDurationsScreenState extends ConsumerState<InternshipDurationsScreen> {
  final MastersRepository _repository = MastersRepository();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;

  List<InternshipDuration> _allDurations = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchDurations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDurations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _repository.getInternshipDurations();
      if (mounted) {
        setState(() {
          _allDurations = list;
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

  List<InternshipDuration> get _filteredDurations {
    if (_searchQuery.isEmpty) return _allDurations;
    final q = _searchQuery.toLowerCase().trim();
    return _allDurations.where((d) {
      final titleMatch = d.title.toLowerCase().contains(q);
      final monthsMatch = '${d.durationMonths}'.contains(q);
      final daysMatch = '${d.durationDays}'.contains(q);
      final leavesMatch = '${d.leaves}'.contains(q);
      return titleMatch || monthsMatch || daysMatch || leavesMatch;
    }).toList();
  }

  int get _totalAssignedInterns {
    return _allDurations.fold(0, (sum, d) => sum + d.internCount);
  }

  InternshipDuration? get _defaultTier {
    try {
      return _allDurations.firstWhere((d) => d.isDefault);
    } catch (_) {
      return null;
    }
  }

  void _openCreateOrEditDialog({InternshipDuration? duration}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InternshipDurationDialog(
        duration: duration,
        existingCount: _allDurations.length,
        onSuccess: _fetchDurations,
      ),
    );
  }

  Future<void> _confirmDelete(InternshipDuration duration) async {
    final hasInterns = duration.internCount > 0;
    final isDefault = duration.isDefault;
    final isBlocked = hasInterns || isDefault;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            isBlocked ? 'Cannot Delete Duration Tier' : 'Delete Duration Tier?',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDefault)
                const Text(
                  '• This tier is currently set as the default onboarding duration. Assign another tier as default before deleting.',
                  style: TextStyle(fontSize: 14, color: AppColors.danger),
                ),
              if (hasInterns)
                Padding(
                  padding: EdgeInsets.only(top: isDefault ? 8.0 : 0.0),
                  child: Text(
                    '• There are ${duration.internCount} active interns enrolled under this duration tier. Reassign them before deleting.',
                    style: const TextStyle(fontSize: 14, color: AppColors.danger),
                  ),
                ),
              if (!isBlocked)
                Text(
                  'Are you sure you want to delete duration tier "${duration.title}"? This action cannot be undone.',
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
        await _repository.deleteInternshipDuration(duration.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Duration tier "${duration.title}" deleted successfully'),
              backgroundColor: AppColors.success,
            ),
          );
          _fetchDurations();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete duration: $e'), backgroundColor: AppColors.danger),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    if (!canManageInternshipDurations(user)) {
      return Scaffold(
        appBar: pageAppBar(context, title: 'Internship Durations'),
        body: const AccessRestrictedView(title: 'Internship Durations Access Restricted'),
      );
    }

    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final filtered = _filteredDurations;
    final defTier = _defaultTier;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchDurations,
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
                        title: 'Internship Durations',
                        subtitle: 'Program length options',
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
                            icon: Icons.access_time_rounded,
                            title: 'DURATION TIERS',
                            valueWidget: Text(
                              '${_allDurations.length}',
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
                            icon: Icons.people_outline_rounded,
                            title: 'ASSIGNED INTERNS',
                            valueWidget: Text(
                              '$_totalAssignedInterns',
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
                            title: 'DEFAULT TIER',
                            valueWidget: defTier != null
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppColors.warning, width: 1),
                                    ),
                                    child: Text(
                                      '${defTier.title} (${defTier.leaves} Leaves)',
                                      style: const TextStyle(
                                        color: AppColors.ink,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
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
                                          hintText: 'Search duration tiers...',
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
                              'Showing ${filtered.length} of ${_allDurations.length} duration tiers',
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
                                    onPressed: _fetchDurations,
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
                                  Icon(Icons.hourglass_empty_rounded, size: 48, color: secondaryTextColor.withValues(alpha: 0.5)),
                                  const SizedBox(height: 10),
                                  Text(
                                    _searchQuery.isNotEmpty ? 'No duration tiers match your search.' : 'No internship durations configured yet.',
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
                              constraints: const BoxConstraints(minWidth: 950),
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
                                  DataColumn(label: Text('DURATION TITLE')),
                                  DataColumn(label: Text('DURATION SPAN')),
                                  DataColumn(label: Text('LEAVES QUOTA')),
                                  DataColumn(label: Text('ASSIGNED INTERNS')),
                                  DataColumn(label: Text('DEFAULT')),
                                  DataColumn(label: Text('STATUS')),
                                  DataColumn(label: Text('ACTIONS')),
                                ],
                                rows: List.generate(filtered.length, (index) {
                                  final dur = filtered[index];
                                  final canDelete = !dur.isDefault && dur.internCount == 0;

                                  return DataRow(
                                    cells: [
                                      // SR. NO
                                      DataCell(
                                        Text(
                                          '${index + 1}',
                                          style: TextStyle(fontSize: 12, color: secondaryTextColor, fontWeight: FontWeight.w600),
                                        ),
                                      ),

                                      // DURATION TITLE (circular badge + title)
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                shape: BoxShape.circle,
                                                border: Border.all(color: AppColors.warning, width: 1.5),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  dur.shortBadgeLabel,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.ink,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              dur.title,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: primaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // DURATION SPAN
                                      DataCell(
                                        Text(
                                          dur.spanFormatted,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: primaryTextColor,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),

                                      // LEAVES QUOTA (green badge)
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.successSoft,
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.eco_outlined, size: 13, color: AppColors.success),
                                              const SizedBox(width: 5),
                                              Text(
                                                '${dur.leaves} Leaves',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.successInk,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      // ASSIGNED INTERNS
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceMuted,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: borderColor),
                                          ),
                                          child: Text(
                                            '${dur.internCount}',
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
                                        dur.isDefault
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

                                      // STATUS (ACTIVE / INACTIVE)
                                      DataCell(
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: dur.isActive ? AppColors.successSoft : AppColors.surfaceMuted,
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                              color: dur.isActive ? AppColors.successSoft : AppColors.border,
                                            ),
                                          ),
                                          child: Text(
                                            dur.isActive ? 'ACTIVE' : 'INACTIVE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.5,
                                              color: dur.isActive ? AppColors.successInk : AppColors.textSecondary,
                                            ),
                                          ),
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
                                                tooltip: 'Edit Duration',
                                                onPressed: () => _openCreateOrEditDialog(duration: dur),
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
                                                tooltip: canDelete ? 'Delete Duration' : 'Cannot delete default or assigned duration tier',
                                                onPressed: () => _confirmDelete(dur),
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
// CREATE / EDIT DURATION DIALOG
// ============================================================================
class _InternshipDurationDialog extends StatefulWidget {
  final InternshipDuration? duration;
  final int existingCount;
  final VoidCallback onSuccess;

  const _InternshipDurationDialog({
    this.duration,
    required this.existingCount,
    required this.onSuccess,
  });

  @override
  State<_InternshipDurationDialog> createState() => _InternshipDurationDialogState();
}

class _InternshipDurationDialogState extends State<_InternshipDurationDialog> {
  final MastersRepository _repository = MastersRepository();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _monthsController;
  late TextEditingController _daysController;
  late TextEditingController _leavesController;

  bool _isDefault = false;
  bool _isActive = true;
  bool _daysAutoCalculated = true;
  bool _isSubmitting = false;

  bool get isEdit => widget.duration != null;

  @override
  void initState() {
    super.initState();
    final d = widget.duration;
    if (d != null) {
      _titleController = TextEditingController(text: d.title);
      _monthsController = TextEditingController(text: '${d.durationMonths}');
      _daysController = TextEditingController(text: '${d.durationDays}');
      _leavesController = TextEditingController(text: '${d.leaves}');
      _isDefault = d.isDefault;
      _isActive = d.isActive;
      _daysAutoCalculated = false;
    } else {
      // Defaults on create: months=3, days=90, leaves=5, is_active=true
      _titleController = TextEditingController(text: '3 Months');
      _monthsController = TextEditingController(text: '3');
      _daysController = TextEditingController(text: '90');
      _leavesController = TextEditingController(text: '5');
      _isDefault = false;
      _isActive = true;
      _daysAutoCalculated = true;
    }

    _monthsController.addListener(_onMonthsChanged);
    _daysController.addListener(_onDaysChanged);
  }

  void _onMonthsChanged() {
    if (!isEdit && _daysAutoCalculated) {
      final m = int.tryParse(_monthsController.text.trim());
      if (m != null && m > 0) {
        _daysController.text = '${m * 30}';

        // Auto-title "{n} Month(s)" when title is empty or ends with Month/Months
        final currentTitle = _titleController.text.trim();
        if (currentTitle.isEmpty || RegExp(r'^\d+\s*Months?$', caseSensitive: false).hasMatch(currentTitle)) {
          _titleController.text = '$m Month${m == 1 ? "" : "s"}';
        }
      }
    }
  }

  void _onDaysChanged() {
    // If user types directly in days, stop auto calculation
    if (_daysController.selection.baseOffset >= 0 && _daysController.text.isNotEmpty) {
      _daysAutoCalculated = false;
    }
  }

  @override
  void dispose() {
    _monthsController.removeListener(_onMonthsChanged);
    _daysController.removeListener(_onDaysChanged);
    _titleController.dispose();
    _monthsController.dispose();
    _daysController.dispose();
    _leavesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tier title is required'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final months = int.tryParse(_monthsController.text.trim());
    if (months == null || months < 1 || months > 36) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Months must be a valid number between 1 and 36'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final days = int.tryParse(_daysController.text.trim());
    if (days == null || days < 1 || days > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Days must be a valid number between 1 and 1000'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final leaves = int.tryParse(_leavesController.text.trim());
    if (leaves == null || leaves < 0 || leaves > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leaves quota must be between 0 and 100'), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (isEdit) {
        await _repository.updateInternshipDuration(
          widget.duration!.id,
          title: title,
          durationMonths: months,
          durationDays: days,
          leaves: leaves,
          isDefault: _isDefault,
          isActive: _isActive,
        );
      } else {
        await _repository.createInternshipDuration(
          title: title,
          durationMonths: months,
          durationDays: days,
          leaves: leaves,
          isDefault: _isDefault,
          isActive: _isActive,
          orderIndex: widget.existingCount + 1,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Duration tier "$title" ${isEdit ? "updated" : "created"} successfully'),
            backgroundColor: AppColors.success,
          ),
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
                          isEdit ? 'Edit Internship Duration' : 'Add Internship Duration',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Define duration in months, total calendar days, and leave entitlement.',
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
                      // Tier Title *
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          children: const [
                            TextSpan(text: 'TIER TITLE '),
                            TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _titleController,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. 3 Months, 6 Months Fast-Track',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Months and Days Row
                      Row(
                        children: [
                          // Months *
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                                    children: const [
                                      TextSpan(text: 'MONTHS '),
                                      TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _monthsController,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(fontSize: 13, color: primaryTextColor),
                                  decoration: InputDecoration(
                                    hintText: '3',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Days *
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text.rich(
                                  TextSpan(
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                                    children: const [
                                      TextSpan(text: 'DAYS '),
                                      TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _daysController,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(fontSize: 13, color: primaryTextColor),
                                  decoration: InputDecoration(
                                    hintText: '90',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Leaves Allocation *
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          children: const [
                            TextSpan(text: 'LEAVES ALLOCATION (DAYS) '),
                            TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _leavesController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: '5',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Number of paid / approved leaves granted to interns enrolling in this duration.',
                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 20),

                      // Set as Default Tier Switch
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
                                    'Set as Default Tier',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryTextColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'New interns onboarding will automatically default to this tier.',
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
                      const SizedBox(height: 14),

                      // Active Status Switch
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
                                    'Active Status',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryTextColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Available for selection in onboarding invite links and intern forms.',
                                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isActive,
                              onChanged: (v) => setState(() => _isActive = v),
                              activeThumbColor: AppColors.success,
                            ),
                          ],
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
                        : Text(isEdit ? 'Save Changes' : 'Create Duration', style: const TextStyle(fontWeight: FontWeight.bold)),
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
