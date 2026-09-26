import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/reference_components.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/announcement_model.dart';
import '../../shared/models/user_model.dart';
import 'announcements_repository.dart';
import 'widgets/announcement_dialog.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const AnnouncementsScreen({super.key, this.showBackButton = false});

  @override
  ConsumerState<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  final AnnouncementsRepository _repository = AnnouncementsRepository();
  final TextEditingController _searchController = TextEditingController();

  Timer? _debounceTimer;
  bool _isLoading = false;
  String? _errorMessage;

  AnnouncementListResponse? _response;
  int _currentPage = 1;
  static const int _pageSize = 20;

  // Filter: null = All Updates, true = Pinned
  bool? _pinnedFilter;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final trimmed = query.trim();
      if (trimmed != _searchQuery) {
        setState(() {
          _searchQuery = trimmed;
          _currentPage = 1; // Reset to page 1 on search
        });
        _fetchAnnouncements();
      }
    });
  }

  void _setFilter(bool? pinned) {
    if (_pinnedFilter == pinned) return;
    setState(() {
      _pinnedFilter = pinned;
      _currentPage = 1; // Reset to page 1 on filter change
    });
    _fetchAnnouncements();
  }

  Future<void> _fetchAnnouncements() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _repository.getAnnouncements(
        page: _currentPage,
        pageSize: _pageSize,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        pinned: _pinnedFilter,
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
    final result = await AnnouncementDialog.show(context);
    if (result == true && mounted) {
      _fetchAnnouncements();
      ref.read(appStateProvider.notifier).fetchAnnouncements();
    }
  }

  void _openEditDialog(Announcement item) async {
    final result = await AnnouncementDialog.show(context, announcement: item);
    if (result == true && mounted) {
      _fetchAnnouncements();
      ref.read(appStateProvider.notifier).fetchAnnouncements();
    }
  }

  void _openDeleteDialog(Announcement item) async {
    final result = await DeleteAnnouncementDialog.show(context, item);
    if (result == true && mounted) {
      _fetchAnnouncements();
      ref.read(appStateProvider.notifier).fetchAnnouncements();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Announcement deleted successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _goToPage(int page) {
    if (page < 1 || (_response != null && page > _response!.totalPages)) return;
    setState(() => _currentPage = page);
    _fetchAnnouncements();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(appStateProvider).currentUser;

    // canPost / canManage: role == "admin" OR "mentor" OR "superadmin"
    final canPost = currentUser.role == UserRole.admin ||
        currentUser.role == UserRole.mentor ||
        currentUser.role == UserRole.superadmin;

    final items = _response?.items ?? [];
    final totalCount = _response?.total ?? 0;
    final totalPages = _response?.totalPages ?? 1;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchAnnouncements,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Section
                _buildHeaderRow(context, canPost),
                const SizedBox(height: 18),

                // Search & Filter Tabs
                _buildSearchAndFilters(totalCount),
                const SizedBox(height: 18),

                // Error Message if any
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
                          onPressed: _fetchAnnouncements,
                        ),
                      ],
                    ),
                  ),

                // Content: Loading / Empty / List
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
                  _buildEmptyState(canPost)
                else ...[
                  // Announcement Cards
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildAnnouncementCard(context, item, canPost);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Pagination controls
                  _buildPaginationControls(totalPages, totalCount),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Page header: back, centered title, amber "+" to post (when allowed)
  Widget _buildHeaderRow(
    BuildContext context,
    bool canPost,
  ) {
    return PageHeader(
      title: 'Announcements',
      subtitle: 'Broadcast updates, milestones and notices',
      showBack: widget.showBackButton ? null : false,
      padding: const EdgeInsets.only(bottom: 8),
      actions: [
        if (canPost)
          CircularIconButton(
            icon: Icons.add_rounded,
            backgroundColor: AppColors.primary,
            iconColor: AppColors.onPrimary,
            onTap: _openCreateDialog,
          ),
      ],
    );
  }

  /// Search Bar + Filter Tabs (All Updates / Pinned)
  Widget _buildSearchAndFilters(int totalCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchBar(),
        const SizedBox(height: 12),
        _buildFilterTabs(totalCount),
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
          hintText: 'Search announcements, authors, topics...',
          hintStyle: TextStyle(
            fontSize: 13.5,
            color: AppColors.textSecondary,
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

  /// Filter Tabs (All Updates vs Pinned)
  Widget _buildFilterTabs(int totalCount) {
    final isAll = _pinnedFilter == null;
    final isPinned = _pinnedFilter == true;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // All Updates
          InkWell(
            onTap: () => _setFilter(null),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: isAll
                    ? AppColors.ink
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isAll
                      ? AppColors.ink
                      : AppColors.border,
                  width: 1.2,
                ),
                boxShadow: isAll
                    ? [
                        BoxShadow(
                          color: (Colors.black).withValues(alpha: 0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                isAll && totalCount > 0 ? 'All Updates ($totalCount)' : 'All Updates',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isAll
                      ? Colors.white
                      : AppColors.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Pinned
          InkWell(
            onTap: () => _setFilter(true),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(
                color: isPinned
                    ? AppColors.ink
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isPinned
                      ? AppColors.ink
                      : AppColors.border,
                  width: 1.2,
                ),
                boxShadow: isPinned
                    ? [
                        BoxShadow(
                          color: (Colors.black).withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.push_pin_rounded,
                    size: 14,
                    color: isPinned
                        ? Colors.white
                        : AppColors.ink,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isPinned && totalCount > 0 ? 'Pinned ($totalCount)' : 'Pinned',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isPinned
                          ? Colors.white
                          : AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Empty State Container
  Widget _buildEmptyState(bool canPost) {
    final hasActiveFilter = _searchQuery.isNotEmpty || _pinnedFilter != null;

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
            child: Center(
              child: Icon(
                Icons.campaign_rounded,
                size: 36,
                color: AppColors.warning,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasActiveFilter ? 'No matching announcements' : 'No announcements found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasActiveFilter
                ? 'No broadcast announcements match your search or filter.'
                : 'No broadcast announcements have been published yet.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          if (hasActiveFilter)
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
                _setFilter(null);
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(
                'Reset Filters',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              ),
            )
          else if (canPost)
            ElevatedButton.icon(
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Post First Announcement',
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Individual Announcement Card
  Widget _buildAnnouncementCard(
    BuildContext context,
    Announcement item,
    bool canPost,
  ) {
    final isPinned = item.isPinned;

    // Highlighted card background & border when pinned
    final cardBg = isPinned
        ? AppColors.warningSoft
        : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openDetailSheet(item, canPost),
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
              // Top Row: Pinned badge + Role chip + Project chip + (Edit/Delete icons if canPost)
              Row(
                children: [
                  // Pinned Badge
                  if (isPinned) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.push_pin_rounded, size: 12, color: Colors.black),
                          const SizedBox(width: 4),
                          Text(
                            'Pinned',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Role chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.border,
                      ),
                    ),
                    child: Text(
                      item.authorRoleFormatted,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),

                  // Project Chip (if present)
                  if (item.projectName != null && item.projectName!.trim().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.infoSoft,
                        borderRadius: BorderRadius.circular(14),
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

                  const Spacer(),

                  // Edit / Delete action buttons for canPost roles
                  if (canPost) ...[
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: 'Edit',
                      onPressed: () => _openEditDialog(item),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      tooltip: 'Delete',
                      onPressed: () => _openDeleteDialog(item),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // Title (line clamp ~2)
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),

              // Body (whitespace preserved, line clamp ~4)
              Text(
                item.body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),

              // Bottom author & date row
              Row(
                children: [
                  // Author Initials Avatar
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      item.authorInitials,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Author Name
                  Text(
                    item.authorName ?? 'Staff',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Dot
                  Text(
                    '•',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Formatted Created At date+time
                  Text(
                    item.formattedCreatedAt,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),

                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textSecondary.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Detail Bottom Sheet for reading full announcement
  void _openDetailSheet(Announcement item, bool canPost) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Sheet header: Badges + Close button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    if (item.isPinned) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.push_pin_rounded, size: 12, color: Colors.black),
                            const SizedBox(width: 4),
                            Text(
                              'Pinned',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.border,
                        ),
                      ),
                      child: Text(
                        item.authorRoleFormatted,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (item.projectName != null && item.projectName!.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.infoSoft,
                          borderRadius: BorderRadius.circular(14),
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
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22),
                      color: AppColors.textSecondary,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Scrollable content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      SelectableText(
                        item.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Author & Date row
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              item.authorInitials,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.authorName ?? 'Staff',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.formattedCreatedAt,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(
                        color: AppColors.border,
                        height: 1,
                      ),
                      const SizedBox(height: 16),

                      // Body
                      SelectableText(
                        item.body,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Edit / Delete buttons if canPost
                      if (canPost) ...[
                        Wrap(
                          alignment: WrapAlignment.end,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openEditDialog(item);
                              },
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.ink,
                                side: BorderSide(
                                  color: AppColors.border,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openDeleteDialog(item);
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: const Text('Delete'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.dangerInk,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pagination Controls: Previous, Page X of Y, Next
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
