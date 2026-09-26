import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/reference_components.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/cohort_model.dart';
import '../../shared/models/user_model.dart';
import 'cohorts_repository.dart';
import 'widgets/cohort_detail_modal.dart';
import 'widgets/cohort_dialog.dart';
import 'widgets/delete_cohort_dialog.dart';

// Exports for backward compatibility
export '../../shared/models/cohort_model.dart';

class CohortManagementScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const CohortManagementScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<CohortManagementScreen> createState() => _CohortManagementScreenState();
}

// Alias for CohortsScreen
typedef CohortsScreen = CohortManagementScreen;

class _CohortManagementScreenState extends ConsumerState<CohortManagementScreen> {
  final CohortsRepository _repository = CohortsRepository();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounceTimer;
  bool _isLoading = false;
  String? _errorMessage;

  CohortListResponse? _response;
  int _currentPage = 1;
  static const int _pageSize = 20;
  String _statusFilter = 'Active';
  String _searchQuery = '';

  Widget _buildSegmentedTab(String label, String value) {
    final isSelected = _statusFilter == value;
    return GestureDetector(
      onTap: () {
        if (_statusFilter != value) {
          setState(() {
            _statusFilter = value;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchCohorts();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = value;
          _currentPage = 1; // Resets page to 1 on search change
        });
        _fetchCohorts();
      }
    });
  }

  Future<void> _fetchCohorts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _repository.getCohorts(
        page: _currentPage,
        pageSize: _pageSize,
        search: _searchQuery,
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
    _fetchCohorts();
  }

  void _openCreateDialog() {
    CohortDialog.show(
      context,
      onSuccess: () {
        _fetchCohorts();
        ref.read(appStateProvider.notifier).fetchCohorts();
      },
    );
  }

  void _openEditDialog(Cohort cohort) {
    CohortDialog.show(
      context,
      cohort: cohort,
      onSuccess: () {
        _fetchCohorts();
        ref.read(appStateProvider.notifier).fetchCohorts();
      },
    );
  }

  void _openDeleteDialog(Cohort cohort) {
    DeleteCohortDialog.show(
      context,
      cohort: cohort,
      onSuccess: () {
        _fetchCohorts();
        ref.read(appStateProvider.notifier).fetchCohorts();
      },
    );
  }

  void _openDetailModal(Cohort cohort, UserModel currentUser) {
    CohortDetailModal.show(
      context,
      cohort: cohort,
      currentUser: currentUser,
      onDataChanged: () {
        _fetchCohorts();
        ref.read(appStateProvider.notifier).fetchCohorts();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final currentUser = state.currentUser;
    final canManage = canManageCohorts(currentUser);

    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final rawCohorts = _response?.items ?? [];
    final cohorts = rawCohorts.where((c) {
      if (_statusFilter == 'Active') {
        return c.statusLabel != 'Completed';
      } else if (_statusFilter == 'Completed') {
        return c.statusLabel == 'Completed';
      }
      return true;
    }).toList();
    final totalPages = _response?.totalPages ?? 1;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _fetchCohorts();
            await ref.read(appStateProvider.notifier).fetchCohorts();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header Sliver
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Back (if any), Title, and "+ New Cohort"
                      PageHeader(
                        title: 'Cohorts',
                        showBack: widget.showBackButton && Navigator.canPop(context),
                        padding: EdgeInsets.zero,
                        actions: [
                          if (canManage) CircularIconButton(icon: Icons.add_rounded, backgroundColor: AppColors.primary, iconColor: AppColors.onPrimary, onTap: _openCreateDialog),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Segmented Tab Row: [Active] [Completed] [All]
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildSegmentedTab('Active', 'Active'),
                                _buildSegmentedTab('Completed', 'Completed'),
                                _buildSegmentedTab('All', 'All'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Search bar
                      TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: TextStyle(color: primaryTextColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search cohorts...',
                          hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                          prefixIcon: Icon(Icons.search_rounded, size: 20, color: secondaryTextColor),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded, size: 18, color: secondaryTextColor),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: cardBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
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
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
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
                        Text(
                          'Failed to load cohorts',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 6),
                        Text(_errorMessage!, style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchCohorts,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.ink,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (cohorts.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.border,
                          style: BorderStyle.solid,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.diversity_3_outlined,
                            size: 64,
                            color: AppColors.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No cohorts found',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No cohorts match your search "$_searchQuery".'
                                : 'Create your first batch cohort to group incoming interns.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: secondaryTextColor,
                            ),
                          ),
                          if (canManage) ...[
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _openCreateDialog,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text(
                                'Create First Cohort',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
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
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final cohort = cohorts[index];
                        final memberCount = cohort.totalMembers;

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
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Left side: Title, Subtitle, and Avatar Stack
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          cohort.name,
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                            color: primaryTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$memberCount Intern${memberCount == 1 ? '' : 's'} • ${cohort.statusLabel}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: secondaryTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        // Overlapping mini avatar circles
                                        Row(
                                          children: [
                                            for (int i = 0; i < (memberCount > 4 ? 4 : (memberCount > 0 ? memberCount : 3)); i++)
                                              Align(
                                                widthFactor: 0.75,
                                                child: Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: [
                                                      AppColors.primary,
                                                      AppColors.info,
                                                      AppColors.info,
                                                      AppColors.peachInk,
                                                    ][i % 4].withValues(alpha: 0.25),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: cardBg,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  alignment: Alignment.center,
                                                  child: Icon(
                                                    Icons.person_rounded,
                                                    size: 16,
                                                    color: [
                                                      AppColors.primary,
                                                      AppColors.info,
                                                      AppColors.info,
                                                      AppColors.peachInk,
                                                    ][i % 4],
                                                  ),
                                                ),
                                              ),
                                            if (memberCount > 4) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                '+${memberCount - 4}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                  color: secondaryTextColor,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Right side: "View" pill button and popup menu
                                  ElevatedButton(
                                    onPressed: () => _openDetailModal(cohort, currentUser),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.lavender,
                                      foregroundColor: AppColors.primaryInk,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                      ),
                                    ),
                                    child: const Text(
                                      'View',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (canManage) ...[
                                    const SizedBox(width: 4),
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert_rounded, size: 20, color: secondaryTextColor),
                                      color: cardBg,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: BorderSide(color: borderColor),
                                      ),
                                      onSelected: (val) {
                                        if (val == 'edit') {
                                          _openEditDialog(cohort);
                                        } else if (val == 'delete') {
                                          _openDeleteDialog(cohort);
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_outlined, size: 16, color: primaryTextColor),
                                              const SizedBox(width: 8),
                                              Text('Edit', style: TextStyle(color: primaryTextColor, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: const Row(
                                            children: [
                                              Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.danger),
                                              SizedBox(width: 8),
                                              Text('Delete', style: TextStyle(color: AppColors.danger, fontSize: 13)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              if (cohort.description != null && cohort.description!.trim().isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Text(
                                  cohort.description!.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondaryTextColor,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                      childCount: cohorts.length,
                    ),
                  ),
                ),

              // Pagination Controls
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
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                            ),
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
