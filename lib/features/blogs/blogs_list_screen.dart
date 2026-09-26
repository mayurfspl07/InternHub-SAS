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
          _errorMessage = e.toString();
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Move article to Recycle Bin?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(
            'Are you sure you want to delete "${post.title}"? You can restore it later from the Recycle Bin.',
            style: const TextStyle(fontSize: 14),
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
                foregroundColor: Colors.white,
              ),
              child: const Text('Move to Bin'),
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
            const SnackBar(
              content: Text('Article moved to Recycle Bin'),
              backgroundColor: AppColors.success,
            ),
          );
          _fetchBlogs();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: AppColors.danger),
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

    final bgColor = AppColors.canvas;
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final totalPages = (_totalCount / _perPage).ceil().clamp(1, 999999);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchBlogs,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageHeader(
                        title: 'Blogs',
                        subtitle: 'Guides, product notes and stories',
                        showBack: widget.showBackButton && Navigator.canPop(context),
                        padding: const EdgeInsets.only(bottom: 14),
                        actions: [
                          if (canManage)
                            CircularIconButton(
                              icon: Icons.add_rounded,
                              backgroundColor: AppColors.primary,
                              iconColor: AppColors.onPrimary,
                              onTap: () => _openEditorDialog(),
                            ),
                        ],
                      ),

                      // Controls Bar (Search Form + Admin Tabs)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 700;

                          final searchBar = Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: Row(
                                    children: [
                                      Icon(Icons.search, size: 18, color: secondaryTextColor),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _searchController,
                                          onSubmitted: (_) => _onSearchSubmit(),
                                          style: TextStyle(fontSize: 13, color: primaryTextColor),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            border: InputBorder.none,
                                            filled: false,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            hintText: 'Search articles by title, topic, or content...',
                                            hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                                          ),
                                        ),
                                      ),
                                      if (_searchController.text.isNotEmpty)
                                        GestureDetector(
                                          onTap: () {
                                            _searchController.clear();
                                            _onSearchSubmit();
                                          },
                                          child: Icon(Icons.close, size: 16, color: secondaryTextColor),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _onSearchSubmit,
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 42),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                ),
                                child: const Text('Search', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          );

                          final adminTabs = canManage
                              ? Container(
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
                                  padding: const EdgeInsets.all(3),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildViewTab('published', 'Published'),
                                      _buildViewTab('admin_all', 'All & Drafts'),
                                    ],
                                  ),
                                )
                              : const SizedBox.shrink();

                          if (isWide) {
                            return Row(
                              children: [
                                Expanded(child: searchBar),
                                if (canManage) ...[
                                  const SizedBox(width: 14),
                                  adminTabs,
                                ],
                              ],
                            );
                          } else {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                searchBar,
                                if (canManage) ...[
                                  const SizedBox(height: 12),
                                  adminTabs,
                                ],
                              ],
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      // Popular Tag Pills
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: popularTags.map((tag) {
                            final isAll = tag == 'All';
                            final isSelected = isAll
                                ? (_selectedTag == 'all' || _selectedTag.isEmpty)
                                : (_selectedTag == tag.toLowerCase());

                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: GestureDetector(
                                onTap: () => _onTagSelected(isAll ? 'all' : tag),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? AppColors.primary : cardBg,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isSelected ? Colors.transparent : borderColor,
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? AppColors.onPrimary : secondaryTextColor,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Content / Cards Grid
              if (_isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_errorMessage != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: AppSpacing.p20),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, size: 36, color: AppColors.danger),
                          const SizedBox(height: 8),
                          Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _fetchBlogs,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_posts.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 30),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.menu_book_rounded, size: 48, color: secondaryTextColor.withValues(alpha: 0.4)),
                            const SizedBox(height: 14),
                            Text(
                              'No articles found',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _searchQuery.isNotEmpty || _selectedTag != 'all'
                                  ? 'Try adjusting your search terms or selecting another tag.'
                                  : 'No articles have been published yet.',
                              style: TextStyle(fontSize: 13, color: secondaryTextColor),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                // 3-Column Responsive Grid
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      int crossAxisCount = 1;
                      if (width > 1050) {
                        crossAxisCount = 3;
                      } else if (width > 680) {
                        crossAxisCount = 2;
                      }

                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 440,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final post = _posts[index];
                            return _buildBlogCard(
                              post: post,
                              canManage: canManage,
                              cardBg: cardBg,
                              borderColor: borderColor,
                              primaryTextColor: primaryTextColor,
                              secondaryTextColor: secondaryTextColor,
                            );
                          },
                          childCount: _posts.length,
                        ),
                      );
                    },
                  ),
                ),

              // Pagination Footer
              if (totalPages > 1 && !_isLoading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 20, AppSpacing.p20, 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
                          icon: const Icon(Icons.chevron_left_rounded, size: 18),
                          label: const Text('Previous'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Page $_currentPage of $totalPages',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _currentPage < totalPages ? () => _goToPage(_currentPage + 1) : null,
                          icon: const Icon(Icons.chevron_right_rounded, size: 18),
                          label: const Text('Next'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewTab(String mode, String label) {
    final isSelected = _viewMode == mode;
    return GestureDetector(
      onTap: () => _onViewModeChanged(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildBlogCard({
    required BlogPost post,
    required bool canManage,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    final readTime = calculateReadingTime(post.content ?? post.excerpt);
    final displayDate = formatShortDate(post.publishedAt ?? post.createdAt);
    final initials = getInitials(post.authorName);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover Image with Draft & Tag Badges
          InkWell(
            onTap: () => _navigateToDetail(post),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
                  child: Container(
                    height: 180,
                    width: double.infinity,
                    color: AppColors.surfaceMuted,
                    child: (post.coverImageUrl != null && post.coverImageUrl!.trim().isNotEmpty)
                        ? Image.network(
                            post.coverImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _buildCardPlaceholder(secondaryTextColor),
                          )
                        : _buildCardPlaceholder(secondaryTextColor),
                  ),
                ),

                // Draft badge
                if (post.isDraft)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.warningSoft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primarySoft),
                      ),
                      child: const Text(
                        'DRAFT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.warningInk,
                        ),
                      ),
                    ),
                  ),

                // Read time badge
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      readTime,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First tag
                  Text(
                    post.primaryTag.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Title
                  InkWell(
                    onTap: () => _navigateToDetail(post),
                    child: Text(
                      post.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Excerpt (3 lines clamp)
                  if (post.excerpt != null && post.excerpt!.trim().isNotEmpty)
                    Expanded(
                      child: Text(
                        post.excerpt!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: secondaryTextColor,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),

                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),

                  // Footer: Author info + Actions or "Read →"
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              post.authorName,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryTextColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              displayDate,
                              style: TextStyle(fontSize: 10, color: secondaryTextColor),
                            ),
                          ],
                        ),
                      ),
                      if (canManage) ...[
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          color: secondaryTextColor,
                          tooltip: 'Edit Article',
                          onPressed: () => _openEditorDialog(post: post),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          color: AppColors.danger,
                          tooltip: 'Move to Bin',
                          onPressed: () => _confirmDelete(post),
                        ),
                      ] else ...[
                        InkWell(
                          onTap: () => _navigateToDetail(post),
                          child: const Row(
                            children: [
                              Text(
                                'Read',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.info,
                                ),
                              ),
                              SizedBox(width: 2),
                              Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.info),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPlaceholder(Color secondaryTextColor) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_rounded, size: 36, color: secondaryTextColor.withValues(alpha: 0.3)),
          const SizedBox(height: 4),
          Text(
            'InternHub Blog',
            style: TextStyle(fontSize: 11, color: secondaryTextColor.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}
