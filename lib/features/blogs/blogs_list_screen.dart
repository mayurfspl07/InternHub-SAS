import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/reference_components.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import 'blog_detail_screen.dart';
import 'blog_repository.dart';
import 'models/blog_models.dart';
import 'widgets/blog_editor_dialog.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/status_chip.dart';
import '../../core/api/api_config.dart';

class BlogsListScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  final String? initialTag;

  const BlogsListScreen({
    super.key,
    this.showBackButton = true,
    this.initialTag,
  });

  @override
  ConsumerState<BlogsListScreen> createState() => _BlogsListScreenState();
}

class _BlogsListScreenState extends ConsumerState<BlogsListScreen> {
  final BlogRepository _repository = BlogRepository();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedTag = 'all'; // all, product, guide, etc.
  String _viewMode = 'published'; // published | admin_all
  int _currentPage = 1;

  bool _isLoading = true;
  String? _errorMessage;

  List<BlogPost> _posts = [];
  int _totalCount = 0;
  int _perPage = 12;

  @override
  void initState() {
    super.initState();
    if (widget.initialTag != null && widget.initialTag!.isNotEmpty) {
      _selectedTag = widget.initialTag!.toLowerCase().trim();
    }
    _fetchBlogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchSubmit() {
    setState(() {
      _searchQuery = _searchController.text.trim();
      _currentPage = 1;
    });
    _fetchBlogs();
  }

  void _onTagSelected(String tag) {
    setState(() {
      _selectedTag = tag.toLowerCase().trim();
      _currentPage = 1;
    });
    _fetchBlogs();
  }

  void _onViewModeChanged(String newMode) {
    if (_viewMode == newMode) return;
    setState(() {
      _viewMode = newMode;
      _currentPage = 1;
    });
    _fetchBlogs();
  }

  void _goToPage(int page) {
    if (page < 1 || page == _currentPage) return;
    setState(() => _currentPage = page);
    _fetchBlogs();
  }

  Future<void> _fetchBlogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final state = ref.read(appStateProvider);
    final user = state.currentUser;
    final canManage = canManageBlogs(user);

    try {
      BlogListResponse res;
      if (canManage && _viewMode == 'admin_all') {
        res = await _repository.getAdminAllBlogs(
          page: _currentPage,
          perPage: _perPage,
          search: _searchQuery,
        );
      } else {
        res = await _repository.getPublishedBlogs(
          page: _currentPage,
          perPage: _perPage,
          tag: _selectedTag,
          search: _searchQuery,
        );
      }

      if (mounted) {
        setState(() {
          _posts = res.items;
          _totalCount = res.total;
          _perPage = res.perPage;
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

  void _openEditorDialog({BlogPost? post}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlogEditorDialog(
        post: post,
        onSaved: (savedPost) {
          _fetchBlogs();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlogDetailScreen(
                slug: savedPost.slug,
                initialPost: savedPost,
              ),
            ),
          ).then((_) => _fetchBlogs());
        },
      ),
    );
  }

  Future<void> _confirmDelete(BlogPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Delete this article?', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
          content: Text(
            '"${post.title}" moves to the recycle bin. You can restore it from there.',
            style: AppTypography.body.copyWith(color: AppColors.ink),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.surface,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _repository.deleteBlog(post.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Article moved to the recycle bin')),
          );
          _fetchBlogs();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Couldn't delete: ${apiErrorMessage(e)}")),
          );
        }
      }
    }
  }

  void _navigateToDetail(BlogPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlogDetailScreen(
          slug: post.slug,
          initialPost: post,
        ),
      ),
    ).then((tagFromDetail) {
      if (tagFromDetail != null && tagFromDetail is String) {
        _onTagSelected(tagFromDetail);
      } else {
        _fetchBlogs();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final canManage = canManageBlogs(user);


    final totalPages = (_totalCount / _perPage).ceil().clamp(1, 999999);

    // The "All & drafts" list comes from an admin endpoint that doesn't filter by tag.
    final showTags = !(canManage && _viewMode == 'admin_all');
    final tagIndex = popularTags.indexWhere((tag) =>
        tag == 'All' ? (_selectedTag == 'all' || _selectedTag.isEmpty) : _selectedTag == tag.toLowerCase());

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchBlogs,
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
                              title: 'Blogs',
                              subtitle: 'Guides, product notes and stories',
                              showBack: widget.showBackButton && Navigator.canPop(context),
                              padding: const EdgeInsets.only(bottom: 14),
                              actions: [
                                if (canManage) HeaderAction(icon: Icons.add_rounded, tooltip: 'New article', onTap: () => _openEditorDialog()),
                              ],
                            ),
                            TextField(
                              controller: _searchController,
                              onSubmitted: (_) => _onSearchSubmit(),
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                hintText: 'Search articles',
                                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        tooltip: 'Clear search',
                                        icon: const Icon(Icons.clear_rounded, size: 18),
                                        onPressed: () {
                                          _searchController.clear();
                                          _onSearchSubmit();
                                        },
                                      )
                                    : null,
                              ),
                            ),
                            if (canManage) ...[
                              const SizedBox(height: 12),
                              PillFilter(
                                options: const ['Published', 'All & drafts'],
                                selectedIndex: _viewMode == 'admin_all' ? 1 : 0,
                                onSelected: (i) => _onViewModeChanged(i == 1 ? 'admin_all' : 'published'),
                              ),
                            ],
                            if (showTags) ...[
                              const SizedBox(height: 12),
                              PillFilter(
                                options: popularTags,
                                selectedIndex: tagIndex,
                                onSelected: (i) => _onTagSelected(popularTags[i] == 'All' ? 'all' : popularTags[i]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_isLoading && _posts.isEmpty)
                      const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                    else if (_errorMessage != null && _posts.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: LoadErrorView(title: "Couldn't load articles", message: _errorMessage!, onRetry: _fetchBlogs),
                      )
                    else if (_posts.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 32),
                          child: Column(
                            children: [
                              const Icon(Icons.menu_book_rounded, size: 48, color: AppColors.textTertiary),
                              const SizedBox(height: 14),
                              Text('No articles found', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text(
                                _searchQuery.isNotEmpty || (showTags && _selectedTag != 'all')
                                    ? 'Try another search or tag.'
                                    : 'Articles appear here once they are published.',
                                style: AppTypography.caption,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      if (_isLoading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 8, AppSpacing.p20, 24),
                        sliver: SliverList.separated(
                          itemCount: _posts.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 16),
                          itemBuilder: (context, index) => _buildBlogCard(post: _posts[index], canManage: canManage),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            PaginationBar(
              page: _currentPage,
              totalPages: totalPages,
              totalItems: _totalCount,
              itemLabel: 'articles',
              isLoading: _isLoading,
              onPageChanged: _goToPage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlogCard({required BlogPost post, required bool canManage}) {
    final readTime = calculateReadingTime(post.content ?? post.excerpt);
    final displayDate = formatShortDate(post.publishedAt ?? post.createdAt);
    final cover = post.coverImageUrl?.trim();

    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppSpacing.r24), boxShadow: AppShadows.soft),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _navigateToDetail(post),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: AppColors.surfaceMuted,
                      child: (cover != null && cover.isNotEmpty)
                          ? Image.network(
                              ApiConfig.mediaUrl(cover),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => _buildCardPlaceholder(),
                            )
                          : _buildCardPlaceholder(),
                    ),
                    if (post.isDraft)
                      const Positioned(
                        top: 10,
                        left: 10,
                        child: StatusChip(label: 'Draft', statusType: StatusType.warning),
                      ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.ink.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(8)),
                        child: Text(readTime, style: AppTypography.label.copyWith(color: AppColors.surface)),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 6, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(humanize(post.primaryTag), style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.infoInk)),
                          const SizedBox(height: 6),
                          Text(
                            post.title,
                            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (post.excerpt != null && post.excerpt!.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              post.excerpt!.trim(),
                              style: AppTypography.caption.copyWith(height: 1.4),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        AppAvatar(fallbackText: post.authorName, size: 28),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${post.authorName} · $displayDate',
                            style: AppTypography.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (canManage)
                          PopupMenuButton<String>(
                            tooltip: 'Actions for this article',
                            icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                            onSelected: (v) => v == 'edit' ? _openEditorDialog(post: post) : _confirmDelete(post),
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
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardPlaceholder() {
    return const Center(child: Icon(Icons.menu_book_rounded, size: 36, color: AppColors.textTertiary));
  }
}
