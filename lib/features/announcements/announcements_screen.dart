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
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/app_avatar.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const AnnouncementsScreen({super.key, this.showBackButton = true});

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
          _errorMessage = apiErrorMessage(e);
        });
      }
    }
  }

  void _openCreateDialog() async {
    final result = await AnnouncementDialog.show(context);
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Announcement posted')));
      _fetchAnnouncements();
    }
  }

  /// The server lets admins edit or delete any announcement, and others only their own.
  bool _canManage(Announcement item, UserModel user) =>
      user.isAdmin || item.authorId.toString() == user.id;

  void _openEditDialog(Announcement item) async {
    final result = await AnnouncementDialog.show(context, announcement: item);
    if (result == true && mounted) {
      _fetchAnnouncements();
    }
  }

  void _openDeleteDialog(Announcement item) async {
    final result = await DeleteAnnouncementDialog.show(context, item);
    if (result == true && mounted) {
      _fetchAnnouncements();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Announcement deleted')),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Section
                _buildHeaderRow(context, canPost),
                const SizedBox(height: 18),

                // Search & Filter Tabs
                _buildSearchAndFilters(totalCount),
                const SizedBox(height: 18),

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
                else if (_errorMessage != null && items.isEmpty)
                  LoadErrorView(title: "Couldn't load announcements", message: _errorMessage!, onRetry: _fetchAnnouncements, compact: true)
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
                      return _buildAnnouncementCard(context, item, _canManage(item, currentUser));
                    },
                  ),
                  const SizedBox(height: 16),

                  PaginationBar(
                    page: _currentPage,
                    totalPages: totalPages,
                    totalItems: totalCount,
                    itemLabel: 'announcements',
                    isLoading: _isLoading,
                    onPageChanged: _goToPage,
                  ),
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
      subtitle: 'Updates for your team',
      showBack: widget.showBackButton && Navigator.canPop(context),
      padding: const EdgeInsets.only(bottom: 8),
      actions: [
        if (canPost)
          HeaderAction(icon: Icons.add_rounded, tooltip: 'New announcement', onTap: _openCreateDialog),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: AppTypography.body.copyWith(color: AppColors.ink),
        decoration: InputDecoration(
          hintText: 'Search announcements, authors, topics...',
          hintStyle: AppTypography.caption.copyWith(color: AppColors.textSecondary),
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
    final index = _pinnedFilter == true ? 1 : 0;
    return PillFilter(
      options: [
        index == 0 && totalCount > 0 ? 'All ($totalCount)' : 'All',
        index == 1 && totalCount > 0 ? 'Pinned ($totalCount)' : 'Pinned',
      ],
      selectedIndex: index,
      onSelected: (i) => _setFilter(i == 1 ? true : null),
    );
  }

  /// Empty State Container
  Widget _buildEmptyState(bool canPost) {
    final hasActiveFilter = _searchQuery.isNotEmpty || _pinnedFilter != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                color: AppColors.warningInk,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasActiveFilter ? 'No matching announcements' : 'No announcements yet',
            style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Text(
            hasActiveFilter
                ? 'Try another search or show all.'
                : 'Team updates will appear here.',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
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
              label: const Text('Show all'),
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
              label: const Text('New announcement'),
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

  Widget _pill(String text, {IconData? icon, Color bg = AppColors.surfaceMuted, Color fg = AppColors.textSecondary}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.label.copyWith(color: fg, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  List<Widget> _badges(Announcement item) => [
        if (item.isPinned) _pill('Pinned', icon: Icons.push_pin_rounded, bg: AppColors.primarySoft, fg: AppColors.primaryInk),
        _pill(item.authorRoleFormatted),
        if (item.projectName != null && item.projectName!.trim().isNotEmpty)
          _pill(item.projectName!, icon: Icons.folder_outlined, bg: AppColors.infoSoft, fg: AppColors.infoInk),
      ];

  Widget _authorLine(Announcement item) {
    return Row(
      children: [
        AppAvatar(fallbackText: item.authorName ?? 'Staff', size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${item.authorName ?? 'Staff'} · ${item.formattedCreatedAt}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption,
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementCard(BuildContext context, Announcement item, bool canManage) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.soft),
      child: Material(
        color: item.isPinned ? AppColors.warningSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _openDetailSheet(item, canManage),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 6, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(spacing: 6, runSpacing: 6, children: _badges(item)),
                      ),
                    ),
                    if (canManage)
                      PopupMenuButton<String>(
                        tooltip: 'Actions for this announcement',
                        icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                        onSelected: (v) => v == 'edit' ? _openEditDialog(item) : _openDeleteDialog(item),
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
                      const SizedBox(width: 12),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 12),
                      _authorLine(item),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Full announcement in a sheet. Edit/Delete use this screen's context after the sheet closes.
  void _openDetailSheet(Announcement item, bool canManage) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(child: Wrap(spacing: 6, runSpacing: 6, children: _badges(item))),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textSecondary,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(item.title, style: AppTypography.title.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      _authorLine(item),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      SelectableText(item.body, style: AppTypography.body.copyWith(height: 1.6, color: AppColors.ink)),
                      if (canManage) ...[
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openEditDialog(item);
                              },
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Edit'),
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.ink, minimumSize: const Size(0, 44)),
                            ),
                            const SizedBox(width: 10),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _openDeleteDialog(item);
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 16),
                              label: const Text('Delete'),
                              style: TextButton.styleFrom(foregroundColor: AppColors.dangerInk, minimumSize: const Size(0, 44)),
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
}
