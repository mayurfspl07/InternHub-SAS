import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/assignment_model.dart';
import '../../shared/models/user_model.dart';
import 'assignments_repository.dart';
import 'widgets/assignment_form_dialog.dart';
import 'widgets/delete_assignment_dialog.dart';
import 'widgets/submissions_review_dialog.dart';
import 'widgets/submit_assignment_dialog.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/pagination_bar.dart';

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
    } catch (e) {
      // The project filter is optional; the list still loads without it.
      if (mounted) showApiError(context, e, prefix: 'Project filter unavailable');
    }
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
          _errorMessage = apiErrorMessage(e);
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
        showApiError(context, e, prefix: "Couldn't download the brief");
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
        style: AppTypography.label.copyWith(color: fg, fontWeight: FontWeight.w700),
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
        label = 'Under review';
        break;
      case 'resubmitted':
        bg = AppColors.infoSoft;
        fg = AppColors.infoInk;
        label = 'Resubmitted';
        break;
      case 'needs_revision':
        bg = AppColors.warningSoft;
        fg = AppColors.warningInk;
        label = 'Needs revision';
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
        label = 'Not submitted';
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
        style: AppTypography.label.copyWith(color: fg, fontWeight: FontWeight.w700),
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

    // Metric cards use the server's totals across every page, not just this page.
    final counts = _response?.counts ?? const <String, int>{};
    final metrics = <(String, int, IconData, Color, Color)>[
      (isIntern ? 'Assigned to you' : 'Assignments', counts['all'] ?? total, Icons.description_outlined, AppColors.warningInk, AppColors.warningSoft),
      ('Active', counts['active'] ?? 0, Icons.check_circle_outline_rounded, AppColors.successInk, AppColors.successSoft),
      ('Closed', counts['closed'] ?? 0, Icons.lock_outline_rounded, AppColors.textSecondary, AppColors.surfaceMuted),
      // Pending reviews is an organization-wide number, so only staff see it.
      if (!isIntern) ('Waiting for review', counts['pending_reviews'] ?? 0, Icons.rate_review_outlined, AppColors.infoInk, AppColors.infoSoft),
    ];

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchAssignments,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PageHeader(
                              title: isIntern ? 'Assignments' : 'Intern assignments',
                              subtitle: canManage ? 'Create, track and grade work' : 'Briefs, submissions and grades',
                              showBack: widget.showBackButton && Navigator.canPop(context),
                              padding: const EdgeInsets.only(bottom: 16),
                              actions: [
                                if (canManage) HeaderAction(icon: Icons.add_rounded, tooltip: 'New assignment', onTap: _openCreateDialog),
                              ],
                            ),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final cols = constraints.maxWidth > 700 ? 4 : 2;
                                final w = (constraints.maxWidth - 12 * (cols - 1)) / cols;
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final m in metrics)
                                      SizedBox(
                                        width: w,
                                        child: _buildMetricCard(
                                          title: m.$1,
                                          value: '${m.$2}',
                                          icon: m.$3,
                                          iconColor: m.$4,
                                          iconBg: m.$5,
                                          cardBg: cardBg,
                                          borderColor: borderColor,
                                          primaryTextColor: primaryTextColor,
                                          secondaryTextColor: secondaryTextColor,
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _searchController,
                              onChanged: (v) {
                                setState(() {});
                                _onSearchChanged(v);
                              },
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Search by title or project',
                                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'Clear search',
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          _onSearchChanged('');
                                        },
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _selectedStatus,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Status', isDense: true),
                                    items: [
                                      const DropdownMenuItem(value: 'all', child: Text('All')),
                                      const DropdownMenuItem(value: 'active', child: Text('Active')),
                                      // Interns never see drafts.
                                      if (!isIntern) const DropdownMenuItem(value: 'draft', child: Text('Draft')),
                                      const DropdownMenuItem(value: 'closed', child: Text('Closed')),
                                      const DropdownMenuItem(value: 'archived', child: Text('Archived')),
                                    ],
                                    onChanged: _onStatusFilterChanged,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<int?>(
                                    initialValue: _selectedProjectId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(labelText: 'Project', isDense: true),
                                    items: [
                                      const DropdownMenuItem<int?>(value: null, child: Text('All')),
                                      ..._projectFilterOptions.map(
                                        (p) => DropdownMenuItem<int?>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                                      ),
                                    ],
                                    onChanged: _onProjectFilterChanged,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isLoading && _response != null)
                      const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
                    if (_isLoading && _response == null)
                      const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                    else if (_errorMessage != null && _response == null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: LoadErrorView(title: "Couldn't load assignments", message: _errorMessage!, onRetry: _fetchAssignments),
                      )
                    else if (assignments.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 32),
                          child: Column(
                            children: [
                              const Icon(Icons.assignment_outlined, size: 56, color: AppColors.textTertiary),
                              const SizedBox(height: 14),
                              Text(
                                _searchQuery.isNotEmpty ? 'No assignments match "$_searchQuery"' : 'No assignments yet',
                                textAlign: TextAlign.center,
                                style: AppTypography.section.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                canManage ? 'Create one to give interns a brief and collect their work.' : 'Work your mentors assign shows up here.',
                                textAlign: TextAlign.center,
                                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                              ),
                              if (canManage && _searchQuery.isEmpty) ...[
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: _openCreateDialog,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('New assignment'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 4, AppSpacing.p20, 24),
                        sliver: SliverList.separated(
                          itemCount: assignments.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 14),
                          itemBuilder: (context, index) => _assignmentCard(assignments[index], isIntern: isIntern, canManage: canManage),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            PaginationBar(
              page: _currentPage,
              totalPages: totalPages,
              totalItems: total,
              itemLabel: 'assignments',
              isLoading: _isLoading,
              onPageChanged: _goToPage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.label.copyWith(color: AppColors.ink))),
        ],
      ),
    );
  }

  Widget _assignmentCard(AssignmentItem a, {required bool isIntern, required bool canManage}) {
    final sub = a.mySubmission;
    final maxScore = a.maxScore?.toInt() ?? 100;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24), boxShadow: AppShadows.soft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  a.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: 'Actions for ${a.title}',
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                  onSelected: (v) => v == 'edit' ? _openEditDialog(a) : _openDeleteDialog(a),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), contentPadding: EdgeInsets.zero),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded, color: AppColors.dangerInk),
                        title: Text('Delete', style: TextStyle(color: AppColors.dangerInk)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                )
              else
                const SizedBox(width: 10),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!isIntern) _buildStatusBadge(a.status),
                _chip(Icons.calendar_today_outlined, a.dueDate == null ? 'No due date' : 'Due ${formatDate(a.dueDate)}'),
                _chip(Icons.emoji_events_outlined, '$maxScore pts'),
                if (a.projectName?.isNotEmpty == true) _chip(Icons.folder_outlined, a.projectName!),
                if (a.cohortName?.isNotEmpty == true) _chip(Icons.groups_outlined, a.cohortName!),
              ],
            ),
          ),
          if (a.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                a.description!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isIntern) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildSubmissionBadge(a.effectiveSubmissionStatus),
                if (sub?.score != null)
                  Text(
                    'Score ${sub!.score! % 1 == 0 ? sub.score!.toInt() : sub.score} / $maxScore',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.successInk),
                  ),
              ],
            ),
            if (sub?.feedback?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  'Feedback: ${sub!.feedback!.trim()}',
                  style: AppTypography.caption.copyWith(color: AppColors.warningInk, height: 1.35),
                ),
              ),
            ],
          ] else
            Text(
              '${plural(a.submissionCount, 'submission')} · ${a.pendingReviewCount} to review · ${a.reviewedCount} reviewed',
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (a.hasAttachment)
                  OutlinedButton.icon(
                    onPressed: () => _downloadBrief(a),
                    icon: const Icon(Icons.attach_file_rounded, size: 16),
                    label: const Text('Brief'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: AppColors.ink),
                  ),
                if (isIntern)
                  ElevatedButton(
                    onPressed: () => _openSubmitDialog(a),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: Text((a.isSubmitted || a.mySubmission != null) ? 'Resubmit' : 'Submit work'),
                  )
                else if (canManage)
                  ElevatedButton.icon(
                    onPressed: () => _openSubmissionsDialog(a),
                    icon: const Icon(Icons.assignment_turned_in_outlined, size: 16),
                    label: Text('Review (${a.submissionCount})'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
