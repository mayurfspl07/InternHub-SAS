import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/reference_components.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/status_chip.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/cohort_model.dart';
import '../../shared/models/user_model.dart';
import 'cohorts_repository.dart';
import 'widgets/cohort_detail_modal.dart';
import 'widgets/cohort_dialog.dart';
import 'widgets/delete_cohort_dialog.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';

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
  /// Tab label and the API `status` value (null = all).
  static const _filters = <(String, String?)>[
    ('Active', 'active'),
    ('Upcoming', 'upcoming'),
    ('Completed', 'completed'),
    ('All', null),
  ];

  final CohortsRepository _repository = CohortsRepository();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounceTimer;
  bool _isLoading = false;
  String? _errorMessage;

  CohortListResponse? _response;
  int _currentPage = 1;
  static const int _pageSize = 20;
  int _filter = 0;
  String _searchQuery = '';

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
      if (!mounted) return;
      setState(() {
        _searchQuery = value;
        _currentPage = 1;
      });
      _fetchCohorts();
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
        status: _filters[_filter].$2,
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
    _fetchCohorts();
  }

  void _setFilter(int i) {
    if (i == _filter) return;
    setState(() {
      _filter = i;
      _currentPage = 1;
    });
    _fetchCohorts();
  }

  void _openCreateDialog() => CohortDialog.show(context, onSuccess: _fetchCohorts);

  void _openEditDialog(Cohort cohort) => CohortDialog.show(context, cohort: cohort, onSuccess: _fetchCohorts);

  void _openDeleteDialog(Cohort cohort) => DeleteCohortDialog.show(context, cohort: cohort, onSuccess: _fetchCohorts);

  void _openDetailModal(Cohort cohort, UserModel currentUser) {
    CohortDetailModal.show(context, cohort: cohort, currentUser: currentUser, onDataChanged: _fetchCohorts);
  }

  String _emptyTitle() {
    if (_searchQuery.isNotEmpty) return 'No cohorts match "$_searchQuery"';
    return switch (_filters[_filter].$2) {
      'active' => 'No active cohorts',
      'upcoming' => 'No upcoming cohorts',
      'completed' => 'No completed cohorts yet',
      _ => 'No cohorts yet',
    };
  }

  Widget _cohortCard(Cohort cohort, UserModel currentUser, bool canManage) {
    final status = cohort.statusLabel;
    final statusType = switch (status) {
      'Active' => StatusType.success,
      'Upcoming' => StatusType.info,
      _ => StatusType.neutral,
    };
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: AppShadows.soft),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _openDetailModal(cohort, currentUser),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 6, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cohort.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusChip(label: status, statusType: statusType),
                          Text(plural(cohort.totalMembers, 'intern'), style: AppTypography.caption),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(cohort.dateRangeFormatted, style: AppTypography.caption),
                      if (cohort.description != null && cohort.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          cohort.description!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    tooltip: 'Actions for ${cohort.name}',
                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                    onSelected: (val) => val == 'edit' ? _openEditDialog(cohort) : _openDeleteDialog(cohort),
                    itemBuilder: (ctx) => const [
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
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 8),
                    child: Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final currentUser = state.currentUser;
    final canManage = canManageCohorts(currentUser);
    final cohorts = _response?.items ?? [];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchCohorts,
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
                              title: 'Cohorts',
                              showBack: widget.showBackButton && Navigator.canPop(context),
                              padding: EdgeInsets.zero,
                              actions: [
                                if (canManage) HeaderAction(icon: Icons.add_rounded, tooltip: 'New cohort', onTap: _openCreateDialog),
                              ],
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
                                hintText: 'Search cohorts',
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
                            const SizedBox(height: 12),
                            PillFilter(
                              options: [for (final f in _filters) f.$1],
                              selectedIndex: _filter,
                              onSelected: _setFilter,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isLoading && _response != null)
                      const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
                    if (_isLoading && _response == null)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_errorMessage != null && _response == null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: LoadErrorView(title: "Couldn't load cohorts", message: _errorMessage!, onRetry: _fetchCohorts),
                      )
                    else if (cohorts.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 32),
                          child: Column(
                            children: [
                              const Icon(Icons.diversity_3_outlined, size: 56, color: AppColors.textTertiary),
                              const SizedBox(height: 14),
                              Text(_emptyTitle(), textAlign: TextAlign.center, style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text(
                                canManage ? 'Cohorts group interns who start together.' : "You'll see your cohort here once you're added.",
                                textAlign: TextAlign.center,
                                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                              ),
                              if (canManage && _searchQuery.isEmpty) ...[
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: _openCreateDialog,
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: const Text('New cohort'),
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
                          itemCount: cohorts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => _cohortCard(cohorts[i], currentUser, canManage),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            PaginationBar(
              page: _currentPage,
              totalPages: _response?.totalPages ?? 1,
              totalItems: _response?.total,
              itemLabel: 'cohorts',
              isLoading: _isLoading,
              onPageChanged: _goToPage,
            ),
          ],
        ),
      ),
    );
  }
}
