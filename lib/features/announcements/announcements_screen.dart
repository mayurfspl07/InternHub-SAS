import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/announcement_model.dart';
import '../../shared/models/user_model.dart';
import 'announcements_repository.dart';
import 'widgets/announcement_dialog.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(appStateProvider).currentUser;

    // canPost / canManage: role == "admin" OR "mentor" OR "superadmin"
    final canPost = currentUser.role == UserRole.admin ||
        currentUser.role == UserRole.mentor ||
        currentUser.role == UserRole.superadmin;

    final canPop = Navigator.canPop(context);
    final items = _response?.items ?? [];
    final totalCount = _response?.total ?? 0;
    final totalPages = _response?.totalPages ?? 1;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchAnnouncements,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Row
                _buildHeaderRow(context, isDark, canPop, canPost),
                const SizedBox(height: 20),

                // Search & Filter Tabs
                _buildSearchAndFilters(isDark, totalCount),
                const SizedBox(height: 20),

                // Error Message if any
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.red),
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
                        color: isDark ? AppColors.cardYellow : Colors.black,
                      ),
                    ),
                  )
                else if (items.isEmpty)
                  _buildEmptyState(isDark, canPost)
                else ...[
                  // Announcement Cards
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _buildAnnouncementCard(context, item, isDark, canPost);
                    },
                  ),
                  const SizedBox(height: 20),

                  // Pagination controls
                  _buildPaginationControls(isDark, totalPages, totalCount),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Top Header Row matching web design
  Widget _buildHeaderRow(
    BuildContext context,
    bool isDark,
    bool canPop,
    bool canPost,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (canPop) ...[
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: isDark ? Colors.white : AppColors.textPrimaryLight,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
        ],

        // Megaphone Icon in rounded yellow container
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.cardYellow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Icon(
              Icons.campaign_rounded,
              color: Colors.black,
              size: 28,
            ),
          ),
        ),
        const SizedBox(width: 14),

        // Title and subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Announcements',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Stay informed with broadcast updates, team milestones, and important notices.',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),

        // Action button: + New Announcement (if canPost)
        if (canPost) ...[
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _openCreateDialog,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(
              'New Announcement',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cardYellow,
              foregroundColor: Colors.black,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Search Bar + Filter Tabs (All Updates / Pinned)
  Widget _buildSearchAndFilters(bool isDark, int totalCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return Row(
            children: [
              Expanded(child: _buildSearchBar(isDark)),
              const SizedBox(width: 16),
              _buildFilterTabs(isDark, totalCount),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSearchBar(isDark),
            const SizedBox(height: 12),
            _buildFilterTabs(isDark, totalCount),
          ],
        );
      },
    );
  }

  /// Search Input Bar
  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFF0F172A),
          width: 1.2,
        ),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: GoogleFonts.outfit(
          fontSize: 14,
          color: isDark ? Colors.white : AppColors.textPrimaryLight,
        ),
        decoration: InputDecoration(
          hintText: 'Search announcements, authors, topics...',
          hintStyle: GoogleFonts.outfit(
            fontSize: 14,
            color: isDark ? Colors.white38 : AppColors.textSecondaryLight,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  /// Filter Tabs (All Updates vs Pinned)
  Widget _buildFilterTabs(bool isDark, int totalCount) {
    final isAll = _pinnedFilter == null;
    final isPinned = _pinnedFilter == true;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // All Updates
        InkWell(
          onTap: () => _setFilter(null),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isAll
                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isAll
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark ? AppColors.borderDark : const Color(0xFFE2E8F0)),
                width: 1.2,
              ),
            ),
            child: Text(
              isAll && totalCount > 0 ? 'All Updates ($totalCount)' : 'All Updates',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isAll
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white70 : AppColors.textPrimaryLight),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Pinned
        InkWell(
          onTap: () => _setFilter(true),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isPinned
                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isPinned
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark ? AppColors.borderDark : const Color(0xFFE2E8F0)),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.push_pin_rounded,
                  size: 14,
                  color: isPinned
                      ? (isDark ? Colors.black : Colors.white)
                      : (isDark ? Colors.white70 : AppColors.textPrimaryLight),
                ),
                const SizedBox(width: 6),
                Text(
                  isPinned && totalCount > 0 ? 'Pinned ($totalCount)' : 'Pinned',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isPinned
                        ? (isDark ? Colors.black : Colors.white)
                        : (isDark ? Colors.white70 : AppColors.textPrimaryLight),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Empty State Container matching web screenshot
  Widget _buildEmptyState(bool isDark, bool canPost) {
    final hasActiveFilter = _searchQuery.isNotEmpty || _pinnedFilter != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFCBD5E1),
          style: BorderStyle.solid,
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 56,
            color: isDark ? Colors.white30 : AppColors.textSecondaryLight.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            'No announcements found',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasActiveFilter
                ? 'No broadcast announcements match your search or filter.'
                : 'No broadcast announcements have been published yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
            ),
          ),
          const SizedBox(height: 20),
          if (hasActiveFilter)
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
                _setFilter(null);
              },
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                side: BorderSide(color: isDark ? Colors.white38 : Colors.black87),
              ),
              child: Text(
                'Reset Filters',
                style: GoogleFonts.outfit(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (canPost)
            ElevatedButton.icon(
              onPressed: _openCreateDialog,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Post First Announcement',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cardYellow,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
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
    bool isDark,
    bool canPost,
  ) {
    final isPinned = item.isPinned;

    // Highlighted card background & border when pinned
    final cardBg = isPinned
        ? (isDark ? const Color(0xFF262115) : const Color(0xFFFFFBEB))
        : (isDark ? AppColors.surfaceDark : Colors.white);

    final borderColor = isPinned
        ? (isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A))
        : (isDark ? AppColors.borderDark : AppColors.borderLight);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.cardYellow.withValues(alpha: isDark ? 0.25 : 0.9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.push_pin_rounded, size: 12, color: Colors.black),
                      const SizedBox(width: 4),
                      Text(
                        'Pinned',
                        style: GoogleFonts.outfit(
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white24 : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  item.authorRoleFormatted,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                  ),
                ),
              ),

              // Project Chip (if present)
              if (item.projectName != null && item.projectName!.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blue.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.blue.withValues(alpha: 0.3) : const Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 11,
                        color: isDark ? Colors.blue.shade300 : const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.projectName!,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.blue.shade300 : const Color(0xFF2563EB),
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
                    color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
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
                    color: Colors.redAccent,
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
            style: GoogleFonts.outfit(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 8),

          // Body (whitespace preserved, line clamp ~4)
          Text(
            item.body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 13.5,
              height: 1.5,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 16),

          // Bottom author & date row
          Row(
            children: [
              // Author Initials Avatar
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.cardYellow,
                child: Text(
                  item.authorInitials,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Author Name
              Text(
                item.authorName ?? 'Staff',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(width: 8),

              // Dot
              Text(
                '•',
                style: TextStyle(
                  color: isDark ? Colors.white38 : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(width: 8),

              // Formatted Created At date+time
              Text(
                item.formattedCreatedAt,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pagination Controls: Previous, Page X of Y, Next
  Widget _buildPaginationControls(bool isDark, int totalPages, int total) {
    final canPrev = _currentPage > 1;
    final canNext = _currentPage < totalPages;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Total items count
          Text(
            'Showing ${((_currentPage - 1) * _pageSize) + 1}–${(_currentPage * _pageSize).clamp(0, total)} of $total',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
            ),
          ),

          // Previous and Next buttons
          Row(
            children: [
              OutlinedButton(
                onPressed: canPrev ? () => _goToPage(_currentPage - 1) : null,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  side: BorderSide(
                    color: canPrev
                        ? (isDark ? Colors.white38 : Colors.black54)
                        : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chevron_left_rounded, size: 18),
                    const SizedBox(width: 2),
                    Text('Previous', style: GoogleFonts.outfit(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              Text(
                '$_currentPage / $totalPages',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(width: 8),

              OutlinedButton(
                onPressed: canNext ? () => _goToPage(_currentPage + 1) : null,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  side: BorderSide(
                    color: canNext
                        ? (isDark ? Colors.white38 : Colors.black54)
                        : (isDark ? Colors.white12 : Colors.black12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Next', style: GoogleFonts.outfit(fontSize: 12)),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
