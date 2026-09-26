import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/reference_components.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/assignment_model.dart';
import '../../shared/models/user_model.dart';
import 'assignments_repository.dart';
import 'widgets/assignment_form_dialog.dart';
import 'widgets/delete_assignment_dialog.dart';
import 'widgets/submissions_review_dialog.dart';
import 'widgets/submit_assignment_dialog.dart';

// Exports for backward compatibility
export '../../shared/models/assignment_model.dart';

class AssignmentsScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const AssignmentsScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  final AssignmentsRepository _repository = AssignmentsRepository();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounceTimer;
  bool _isLoading = false;
  String? _errorMessage;

  AssignmentListResponse? _response;
  int _currentPage = 1;
  static const int _pageSize = 20;

  // Filter state
  String _searchQuery = '';
  String _selectedStatus = 'all'; // all | active | draft | closed | archived
  int? _selectedProjectId; // null = all projects

  List<AssignmentPickerOption> _projectFilterOptions = [];

  @override
  void initState() {
    super.initState();
    _loadProjectFilterOptions();
    _fetchAssignments();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectFilterOptions() async {
    try {
      final projs = await _repository.getProjectOptions();
      if (mounted) {
        setState(() => _projectFilterOptions = projs);
      }
    } catch (_) {}
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = value;
          _currentPage = 1;
        });
        _fetchAssignments();
      }
    });
  }

  void _onStatusFilterChanged(String? status) {
    if (status != null && status != _selectedStatus) {
      setState(() {
        _selectedStatus = status;
        _currentPage = 1;
      });
      _fetchAssignments();
    }
  }

  void _onProjectFilterChanged(int? projectId) {
    if (projectId != _selectedProjectId) {
      setState(() {
        _selectedProjectId = projectId;
        _currentPage = 1;
      });
      _fetchAssignments();
    }
  }

  Future<void> _fetchAssignments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _repository.getAssignments(
        page: _currentPage,
        pageSize: _pageSize,
        search: _searchQuery,
        status: _selectedStatus,
        projectId: _selectedProjectId,
      );

      if (mounted) {
        setState(() {
          _response = res;
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

  void _goToPage(int page) {
    if (page < 1 || (_response != null && page > _response!.totalPages)) return;
    setState(() => _currentPage = page);
    _fetchAssignments();
  }

  void _openCreateDialog() {
    AssignmentFormDialog.show(
      context,
      onSuccess: () => _fetchAssignments(),
    );
  }

  void _openEditDialog(AssignmentItem assignment) {
    AssignmentFormDialog.show(
      context,
      assignment: assignment,
      onSuccess: () => _fetchAssignments(),
    );
  }

  void _openDeleteDialog(AssignmentItem assignment) {
    DeleteAssignmentDialog.show(
      context,
      assignment: assignment,
      onSuccess: () => _fetchAssignments(),
    );
  }

  void _openSubmitDialog(AssignmentItem assignment) {
    SubmitAssignmentDialog.show(
      context,
      assignment: assignment,
      onSuccess: () => _fetchAssignments(),
    );
  }

  void _openSubmissionsDialog(AssignmentItem assignment) {
    SubmissionsReviewDialog.show(
      context,
      assignment: assignment,
      onDataChanged: () => _fetchAssignments(),
    );
  }

  Future<void> _downloadBrief(AssignmentItem assignment) async {
    try {
      await _repository.downloadBrief(assignment);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to download brief: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase().trim()) {
      case 'active':
        bg = AppColors.successSoft;
        fg = AppColors.successInk;
        label = 'Active';
        break;
      case 'draft':
        bg = AppColors.surfaceMuted;
        fg = AppColors.textSecondary;
        label = 'Draft';
        break;
      case 'closed':
        bg = AppColors.warningSoft;
        fg = AppColors.warningInk;
        label = 'Closed';
        break;
      case 'archived':
      default:
        bg = AppColors.border;
        fg = AppColors.textSecondary;
        label = 'Archived';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildSubmissionBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status.toLowerCase().trim()) {
      case 'approved':
        bg = AppColors.successSoft;
        fg = AppColors.successInk;
        label = 'Approved';
        break;
      case 'submitted':
        bg = AppColors.infoSoft;
        fg = AppColors.infoInk;
        label = 'Submitted';
        break;
      case 'under_review':
        bg = AppColors.lavender;
        fg = AppColors.lavenderInk;
        label = 'Under Review';
        break;
      case 'resubmitted':
      case 'needs_revision':
        bg = AppColors.warningSoft;
        fg = AppColors.warningInk;
        label = 'Needs Revision';
        break;
      case 'rejected':
        bg = AppColors.dangerSoft;
        fg = AppColors.dangerInk;
        label = 'Rejected';
        break;
      case 'not_submitted':
      default:
        bg = AppColors.surfaceMuted;
        fg = AppColors.textSecondary;
        label = 'Not Submitted';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor)),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(color: secondaryTextColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final role = user.role;

    final canManage = role == UserRole.admin || role == UserRole.mentor;
    final isIntern = role == UserRole.intern;

    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final assignments = _response?.items ?? [];
    final total = _response?.total ?? 0;
    final totalPages = _response?.totalPages ?? 1;

    // Metrics calculations matching web formulas:
    final int card1Value = total;
    int card2Value = 0;
    int card3Value = 0;
    int card4Value = 0;

    if (isIntern) {
      // Intern: Submitted, Pending Review, Graded/Approved
      final submittedCount = assignments.where((a) => a.isSubmitted || a.mySubmission != null).length;
      final approvedCount = assignments.where((a) => a.mySubmission?.status.toLowerCase() == 'approved').length;
      card2Value = submittedCount;
      card3Value = (submittedCount - approvedCount).clamp(0, 999999);
      card4Value = approvedCount;
    } else {
      // Staff: Active Tasks, Submissions, Pending Reviews
      card2Value = assignments.where((a) => a.status.toLowerCase() == 'active').length;
      card3Value = assignments.fold(0, (sum, a) => sum + a.submissionCount);
      card4Value = assignments.fold(0, (sum, a) => sum + a.pendingReviewCount);
    }

    final card1Title = isIntern ? 'Assigned Work' : 'Total Assignments';
    final card2Title = isIntern ? 'Submitted' : 'Active Tasks';
    final card3Title = isIntern ? 'Pending Review' : 'Submissions';
    final card4Title = isIntern ? 'Graded / Approved' : 'Pending Reviews';

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchAssignments,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Top Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageHeader(
                        title: 'Assignments',
                        subtitle: canManage
                            ? 'Create, assign, track and grade work'
                            : isIntern
                                ? 'Briefs, submissions and grades'
                                : 'Homework and project tasks',
                        showBack: widget.showBackButton && Navigator.canPop(context),
                        padding: const EdgeInsets.only(bottom: 16),
                        actions: [
                          if (canManage)
                            CircularIconButton(
                              icon: Icons.add_rounded,
                              backgroundColor: AppColors.primary,
                              iconColor: AppColors.onPrimary,
                              onTap: _openCreateDialog,
                            ),
                        ],
                      ),

                      // Metrics Cards (4 in a row / grid)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 700;
                          return GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: isWide ? 4 : 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: isWide ? 1.6 : 1.3,
                            children: [
                              _buildMetricCard(
                                title: card1Title,
                                value: '$card1Value',
                                icon: Icons.description_outlined,
                                iconColor: AppColors.warningInk,
                                iconBg: AppColors.warningSoft,
                                cardBg: cardBg,
                                borderColor: borderColor,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                              ),
                              _buildMetricCard(
                                title: card2Title,
                                value: '$card2Value',
                                icon: Icons.check_circle_outline_rounded,
                                iconColor: AppColors.successInk,
                                iconBg: AppColors.successSoft,
                                cardBg: cardBg,
                                borderColor: borderColor,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                              ),
                              _buildMetricCard(
                                title: card3Title,
                                value: '$card3Value',
                                icon: Icons.groups_outlined,
                                iconColor: AppColors.info,
                                iconBg: AppColors.infoSoft,
                                cardBg: cardBg,
                                borderColor: borderColor,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                              ),
                              _buildMetricCard(
                                title: card4Title,
                                value: '$card4Value',
                                icon: Icons.military_tech_outlined,
                                iconColor: AppColors.primary,
                                iconBg: AppColors.lavender,
                                cardBg: cardBg,
                                borderColor: borderColor,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Filter Bar
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 700;

                            final searchWidget = TextField(
                              controller: _searchController,
                              onChanged: _onSearchChanged,
                              style: TextStyle(color: primaryTextColor, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Search assignments by title or project...',
                                hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                                prefixIcon: Icon(Icons.search_rounded, size: 18, color: secondaryTextColor),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear_rounded, size: 16, color: secondaryTextColor),
                                        onPressed: () {
                                          _searchController.clear();
                                          _onSearchChanged('');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: AppColors.surfaceMuted,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                              ),
                            );

                            final statusWidget = Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedStatus,
                                  isExpanded: true,
                                  dropdownColor: cardBg,
                                  style: TextStyle(color: primaryTextColor, fontSize: 13),
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                                    DropdownMenuItem(value: 'active', child: Text('Active')),
                                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                                    DropdownMenuItem(value: 'archived', child: Text('Archived')),
                                  ],
                                  onChanged: _onStatusFilterChanged,
                                ),
                              ),
                            );

                            final projectWidget = Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int?>(
                                  value: _selectedProjectId,
                                  isExpanded: true,
                                  dropdownColor: cardBg,
                                  style: TextStyle(color: primaryTextColor, fontSize: 13),
                                  hint: const Text('All Projects', style: TextStyle(fontSize: 13)),
                                  items: [
                                    const DropdownMenuItem<int?>(value: null, child: Text('All Projects')),
                                    ..._projectFilterOptions.map(
                                      (p) => DropdownMenuItem<int?>(
                                        value: p.id,
                                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                                      ),
                                    ),
                                  ],
                                  onChanged: _onProjectFilterChanged,
                                ),
                              ),
                            );

                            final totalCounter = Text(
                              '$total assignment${total == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryTextColor),
                            );

                            if (isWide) {
                              return Row(
                                children: [
                                  Expanded(flex: 4, child: searchWidget),
                                  const SizedBox(width: 10),
                                  statusWidget,
                                  const SizedBox(width: 10),
                                  projectWidget,
                                  const SizedBox(width: 12),
                                  totalCounter,
                                ],
                              );
                            } else {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  searchWidget,
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(child: statusWidget),
                                      const SizedBox(width: 10),
                                      Expanded(child: projectWidget),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Align(alignment: Alignment.centerRight, child: totalCounter),
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

              // Content Area: Loading / Error / Empty State / List
              if (_isLoading && _response == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                )
              else if (_errorMessage != null && _response == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
                        const SizedBox(height: 12),
                        Text('Failed to load assignments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor)),
                        const SizedBox(height: 6),
                        Text(_errorMessage!, style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchAssignments,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.ink),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (assignments.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment_outlined, size: 64, color: AppColors.textTertiary),
                          const SizedBox(height: 16),
                          Text(
                            'No assignments found',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No assignments match your search "$_searchQuery".'
                                : canManage
                                    ? 'Create your first assignment module to assign homework or tasks.'
                                    : 'No assignments have been assigned to your cohort yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: secondaryTextColor),
                          ),
                          if (canManage) ...[
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _openCreateDialog,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Create Assignment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.onPrimary,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final a = assignments[index];
                        final sub = a.mySubmission;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: AppShadows.soft,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: Status badge & project/cohort chips
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                runSpacing: 6,
                                children: [
                                  _buildStatusBadge(a.status),
                                  const SizedBox(width: 8),
                                  if (a.projectName?.isNotEmpty == true) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceMuted,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.folder_outlined, size: 12, color: secondaryTextColor),
                                          const SizedBox(width: 4),
                                          Text(a.projectName!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryTextColor)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  if (a.cohortName?.isNotEmpty == true) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceMuted,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.groups_outlined, size: 12, color: secondaryTextColor),
                                          const SizedBox(width: 4),
                                          Text(a.cohortName!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: primaryTextColor)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const Spacer(),
                                  // Due date & points
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today_outlined, size: 13, color: secondaryTextColor),
                                      const SizedBox(width: 5),
                                      Text(a.formattedDueDate, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: secondaryTextColor)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.warningSoft,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${a.maxScore?.toInt() ?? 100} pts',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.warningInk),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Title
                              Text(
                                a.title,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // Description
                              Text(
                                a.description?.trim().isNotEmpty == true
                                    ? a.description!.trim()
                                    : 'No description provided.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: a.description?.trim().isNotEmpty == true ? AppColors.textSecondary : secondaryTextColor.withValues(alpha: 0.7),
                                  fontStyle: a.description?.trim().isNotEmpty == true ? FontStyle.normal : FontStyle.italic,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Intern specific submission info
                              if (isIntern) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      Text('Your Submission: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryTextColor)),
                                      _buildSubmissionBadge(a.effectiveSubmissionStatus),
                                      if (sub?.score != null) ...[
                                        const SizedBox(width: 10),
                                        Text(
                                          'Score: ${sub!.score! % 1 == 0 ? sub.score!.toInt() : sub.score} / ${a.maxScore?.toInt() ?? 100}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.successInk),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Mentor feedback banner if present
                                if (sub?.feedback?.trim().isNotEmpty == true) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningSoft.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.rate_review_outlined, size: 16, color: AppColors.warningInk),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Mentor Feedback: "${sub!.feedback!.trim()}"',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.warningInk,
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                              ] else ...[
                                // Staff submission stats
                                Row(
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 14, color: secondaryTextColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${a.submissionCount} submissions • ${a.pendingReviewCount} pending • ${a.reviewedCount} reviewed',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryTextColor),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],

                              Divider(height: 1, color: borderColor),
                              const SizedBox(height: 12),

                              // Bottom action buttons
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  // Download brief button (if has attachment)
                                  if (a.hasAttachment)
                                    OutlinedButton.icon(
                                      onPressed: () => _downloadBrief(a),
                                      icon: const Icon(Icons.attach_file_rounded, size: 15),
                                      label: const Text('Download Brief', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryTextColor,
                                        side: BorderSide(color: borderColor),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                    ),


                                  // Role based action buttons
                                  if (isIntern)
                                    ElevatedButton(
                                      onPressed: () => _openSubmitDialog(a),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: AppColors.onPrimary,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                        ),
                                      ),
                                      child: Text(
                                        (a.isSubmitted || a.mySubmission != null) ? 'Resubmit Solution' : 'Submit Solution',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    )
                                  else if (canManage) ...[
                                    OutlinedButton.icon(
                                      onPressed: () => _openSubmissionsDialog(a),
                                      icon: const Icon(Icons.assignment_turned_in_outlined, size: 15),
                                      label: Text(
                                        'Review Submissions (${a.submissionCount})',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: primaryTextColor,
                                        side: BorderSide(color: borderColor),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    IconButton(
                                      onPressed: () => _openEditDialog(a),
                                      icon: const Icon(Icons.edit_outlined, size: 19),
                                      color: secondaryTextColor,
                                      tooltip: 'Edit Assignment',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 14),
                                    IconButton(
                                      onPressed: () => _openDeleteDialog(a),
                                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                      color: AppColors.danger.withValues(alpha: 0.85),
                                      tooltip: 'Delete Assignment',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                      childCount: assignments.length,
                    ),
                  ),
                ),

              // Pagination
              if (totalPages > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Previous'),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Page $_currentPage of $totalPages',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _currentPage < totalPages ? () => _goToPage(_currentPage + 1) : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryTextColor,
                            side: BorderSide(color: borderColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Next'),
                        ),
                      ],
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
