import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/reference_components.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/performance_review_model.dart';
import '../../shared/models/user_model.dart';
import 'performance_repository.dart';
import 'widgets/delete_review_dialog.dart';
import 'widgets/performance_review_dialog.dart';
import 'widgets/review_detail_modal.dart';

// Exports for backward compatibility
export '../../shared/models/performance_review_model.dart';

class PerformanceDashboardScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const PerformanceDashboardScreen({super.key, this.showBackButton = false});

  @override
  ConsumerState<PerformanceDashboardScreen> createState() => _PerformanceDashboardScreenState();
}

// Alias for ReviewsScreen
typedef ReviewsScreen = PerformanceDashboardScreen;

class _PerformanceDashboardScreenState extends ConsumerState<PerformanceDashboardScreen> {
  final PerformanceRepository _repository = PerformanceRepository();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounceTimer;
  bool _isLoading = false;
  String? _errorMessage;

  ReviewListResponse? _response;
  int _currentPage = 1;
  static const int _pageSize = 20;

  // Filters
  String _searchQuery = '';
  int? _selectedRating; // null = all, 1..5
  int? _selectedProjectId; // null = all
  String? _selectedProjectTitle;

  // Projects list for dropdown filter
  List<ReviewSelectOption> _projectOptions = [];

  @override
  void initState() {
    super.initState();
    final role = ref.read(appStateProvider).currentUser.role;
    if (role == UserRole.intern) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      });
      return;
    }
    _loadProjectOptions();
    _fetchReviews();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectOptions() async {
    final projects = await _repository.getProjectOptions();
    if (mounted) {
      setState(() {
        _projectOptions = projects;
      });
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final trimmed = query.trim();
      if (trimmed != _searchQuery) {
        setState(() {
          _searchQuery = trimmed;
          _currentPage = 1;
        });
        _fetchReviews();
      }
    });
  }

  void _setRatingFilter(int? rating) {
    if (_selectedRating == rating) return;
    setState(() {
      _selectedRating = rating;
      _currentPage = 1;
    });
    _fetchReviews();
  }

  void _setProjectFilter(int? projectId, String? projectTitle) {
    if (_selectedProjectId == projectId) return;
    setState(() {
      _selectedProjectId = projectId;
      _selectedProjectTitle = projectTitle;
      _currentPage = 1;
    });
    _fetchReviews();
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedRating = null;
      _selectedProjectId = null;
      _selectedProjectTitle = null;
      _currentPage = 1;
    });
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _repository.getReviews(
        page: _currentPage,
        pageSize: _pageSize,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        rating: _selectedRating,
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
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  void _openCreateDialog() async {
    final result = await PerformanceReviewDialog.show(context);
    if (result == true && mounted) {
      _fetchReviews();
    }
  }

  void _openEditDialog(PerformanceReview item) async {
    final result = await PerformanceReviewDialog.show(context, review: item);
    if (result == true && mounted) {
      _fetchReviews();
    }
  }

  void _openDeleteDialog(PerformanceReview item) async {
    final result = await DeleteReviewDialog.show(context, item);
    if (result == true && mounted) {
      _fetchReviews();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Performance review deleted successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _goToPage(int page) {
    if (page < 1 || (_response != null && page > _response!.totalPages)) return;
    setState(() => _currentPage = page);
    _fetchReviews();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(appStateProvider).currentUser;
    if (currentUser.role == UserRole.intern) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final canCreate = canCreateReview(currentUser);

    final items = _response?.items ?? [];
    final totalCount = _response?.total ?? 0;
    final totalPages = _response?.totalPages ?? 1;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchReviews,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Section
                _buildHeaderRow(context, canCreate),
                const SizedBox(height: 18),

                // Filters Section: Search + Rating Pills + Project Dropdown
                _buildFiltersSection(),
                const SizedBox(height: 18),

                // Error Message banner if any
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: AppColors.danger, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.danger),
                          onPressed: _fetchReviews,
                        ),
                      ],
                    ),
                  ),

                // Content Section: Loading / Empty / List
                if (_isLoading && _response == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                  )
                else if (items.isEmpty)
                  _buildEmptyState(canCreate)
                else ...[
                  // Review Cards
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final serialIndex = ((_currentPage - 1) * _pageSize) + index + 1;
                      return _buildReviewCard(context, item, serialIndex, currentUser);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Pagination Controls
                  _buildPaginationControls(totalPages, totalCount),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Page header: back, centered title, amber "+" for a new review
  Widget _buildHeaderRow(BuildContext context, bool canCreate) {
    return PageHeader(
      title: 'Reviews',
      subtitle: 'Performance evaluations',
      showBack: widget.showBackButton ? null : false,
      padding: EdgeInsets.zero,
      actions: [
        if (canCreate)
          CircularIconButton(
            icon: Icons.add_rounded,
            backgroundColor: AppColors.primary,
            iconColor: AppColors.onPrimary,
            onTap: _openCreateDialog,
          ),
      ],
    );
  }

  /// Filters Section: Search input, Rating dropdown/pills, Project picker, Reset
  Widget _buildFiltersSection() {
    final hasActiveFilter =
        _searchQuery.isNotEmpty || _selectedRating != null || _selectedProjectId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search Input
        _buildSearchBar(),
        const SizedBox(height: 12),

        // Rating & Project Filter Controls
        Row(
          children: [
            // Rating Filter Selector
            Expanded(
              child: _buildRatingDropdown(),
            ),
            const SizedBox(width: 10),

            // Project Filter Selector
            Expanded(
              child: _buildProjectDropdown(),
            ),

            // Reset Button if active filter
            if (hasActiveFilter) ...[
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Reset Filters',
                icon: const Icon(Icons.filter_alt_off_rounded, size: 20),
                color: AppColors.textSecondary,
                onPressed: _resetFilters,
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Search Input Bar
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: TextStyle(
          fontSize: 14,
          color: AppColors.ink,
        ),
        decoration: InputDecoration(
          hintText: 'Search by intern, reviewer, project, period..',
          hintStyle: TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary.withValues(alpha: 0.8),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: AppColors.textSecondary,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          filled: false,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
      ),
    );
  }

  /// Rating Filter Dropdown Menu
  Widget _buildRatingDropdown() {
    final borderColor = AppColors.border;
    final ratingLabel = _selectedRating != null ? '$_selectedRating Stars' : 'All Ratings';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _selectedRating != null ? AppColors.warning : borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _selectedRating,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 13,
            fontWeight: _selectedRating != null ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.ink,
          ),
          hint: Text(
            ratingLabel,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.ink,
            ),
          ),
          items: const [
            DropdownMenuItem<int?>(value: null, child: Text('All Ratings')),
            DropdownMenuItem<int?>(value: 5, child: Text('⭐ 5 Stars')),
            DropdownMenuItem<int?>(value: 4, child: Text('⭐ 4 Stars')),
            DropdownMenuItem<int?>(value: 3, child: Text('⭐ 3 Stars')),
            DropdownMenuItem<int?>(value: 2, child: Text('⭐ 2 Stars')),
            DropdownMenuItem<int?>(value: 1, child: Text('⭐ 1 Star')),
          ],
          onChanged: _setRatingFilter,
        ),
      ),
    );
  }

  /// Project Filter Dropdown Menu
  Widget _buildProjectDropdown() {
    final borderColor = AppColors.border;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _selectedProjectId != null ? AppColors.info : borderColor,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _selectedProjectId,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down_rounded),
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(16),
          style: TextStyle(
            fontSize: 13,
            fontWeight: _selectedProjectId != null ? FontWeight.w700 : FontWeight.w500,
            color: AppColors.ink,
          ),
          hint: Text(
            _selectedProjectTitle ?? 'All Projects',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.ink,
            ),
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.folder_outlined, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('All Projects', overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            ..._projectOptions.map((p) {
              return DropdownMenuItem<int?>(
                value: p.id,
                child: Row(
                  children: [
                    const Icon(Icons.folder_outlined, size: 16, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(child: Text(p.label, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            }),
          ],
          onChanged: (val) {
            String? title;
            if (val != null) {
              final match = _projectOptions.where((p) => p.id == val);
              if (match.isNotEmpty) title = match.first.label;
            }
            _setProjectFilter(val, title);
          },
        ),
      ),
    );
  }

  /// Empty State Container matching web
  Widget _buildEmptyState(bool canCreate) {
    final hasActiveFilter =
        _searchQuery.isNotEmpty || _selectedRating != null || _selectedProjectId != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.star_outline_rounded,
                size: 38,
                color: AppColors.warning,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasActiveFilter ? 'No matching reviews' : 'No performance reviews found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasActiveFilter
                ? 'No evaluations match your search or filter criteria.'
                : 'No performance evaluations have been published yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          if (hasActiveFilter)
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                'Reset Filters',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
            )
          else if (canCreate)
            ElevatedButton.icon(
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Submit First Review',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rPill)),
              ),
            ),
        ],
      ),
    );
  }

  /// Individual Performance Review Card
  Widget _buildReviewCard(
    BuildContext context,
    PerformanceReview item,
    int serialIndex,
    UserModel currentUser,
  ) {
    final canManage = canManageReview(item, currentUser);
    final cardBg = Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ReviewDetailModal.show(
          context,
          review: item,
          currentUser: currentUser,
          onDataChanged: _fetchReviews,
        ),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Intern Avatar + Name + Serial + Rating Badge + Edit/Delete buttons
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      item.internInitials,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.internDisplayName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#$serialIndex',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Reviewed by ${item.reviewerDisplayName} • ${item.formattedCreatedAt}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Rating Badge (e.g. ⭐ 5/5)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          '${item.rating}/5',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Edit & Delete buttons if canManage
                  if (canManage) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: 'Edit Review',
                      onPressed: () => _openEditDialog(item),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      tooltip: 'Delete Review',
                      onPressed: () => _openDeleteDialog(item),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // Subheader Tags: Period + Project Tag
              if ((item.period != null && item.period!.isNotEmpty) ||
                  (item.projectName != null && item.projectName!.isNotEmpty)) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (item.period != null && item.period!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warningSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.primarySoft,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 11, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Text(
                              item.period!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (item.projectName != null && item.projectName!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.infoSoft,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.infoSoft,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 11,
                              color: AppColors.info,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              item.projectName!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Category Ratings Row (if any)
              if (item.hasCategoryRatings) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.spaceAround,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (item.technicalRating != null)
                        _buildCategoryBadge('Technical', item.technicalRating!),
                      if (item.communicationRating != null)
                        _buildCategoryBadge('Communication', item.communicationRating!),
                      if (item.initiativeRating != null)
                        _buildCategoryBadge('Initiative', item.initiativeRating!),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Feedback snippet
              if (item.feedback != null && item.feedback!.trim().isNotEmpty) ...[
                Text(
                  item.feedback!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
              ],

              // Bottom row: "View Details" hint
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View Details',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryInk,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: AppColors.primaryInk,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(String title, int score) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$title: ',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
        const Icon(Icons.star_rounded, size: 12, color: AppColors.warning),
        const SizedBox(width: 2),
        Text(
          '$score/5',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }

  /// Pagination Controls matching announcements pattern
  Widget _buildPaginationControls(int totalPages, int total) {
    final canPrev = _currentPage > 1;
    final canNext = _currentPage < totalPages;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Total items count
          Flexible(
            child: Text(
              'Showing ${((_currentPage - 1) * _pageSize) + 1}–${(_currentPage * _pageSize).clamp(0, total)} of $total',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Previous and Next compact buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: canPrev ? () => _goToPage(_currentPage - 1) : null,
                icon: Icon(
                  Icons.chevron_left_rounded,
                  size: 22,
                  color: canPrev
                      ? AppColors.ink
                      : Colors.black26,
                ),
                tooltip: 'Previous',
              ),
              const SizedBox(width: 4),

              Text(
                '$_currentPage / $totalPages',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 4),

              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: canNext ? () => _goToPage(_currentPage + 1) : null,
                icon: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: canNext
                      ? AppColors.ink
                      : Colors.black26,
                ),
                tooltip: 'Next',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
