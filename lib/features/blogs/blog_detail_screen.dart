import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_config.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import 'blog_repository.dart';
import 'models/blog_models.dart';
import 'widgets/safe_html_view.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/app_tag.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_avatar.dart';

class BlogDetailScreen extends ConsumerStatefulWidget {
  final String slug;
  final BlogPost? initialPost;

  const BlogDetailScreen({
    super.key,
    required this.slug,
    this.initialPost,
  });

  @override
  ConsumerState<BlogDetailScreen> createState() => _BlogDetailScreenState();
}

class _BlogDetailScreenState extends ConsumerState<BlogDetailScreen> {
  final BlogRepository _repository = BlogRepository();

  BlogPost? _post;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _post = widget.initialPost;
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = _post == null;
      _errorMessage = null;
    });

    try {
      final post = await _repository.getBlogBySlug(widget.slug);
      if (mounted) {
        setState(() {
          _post = post;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (_post == null) {
            _errorMessage = apiErrorMessage(e);
          }
        });
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Move article to Recycle Bin?', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
          content: Text(
            'Are you sure you want to delete "${_post?.title}"? You can restore it later from the Recycle Bin.',
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
              child: const Text('Move to Bin'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && _post != null) {
      try {
        await _repository.deleteBlog(_post!.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Article moved to the recycle bin')),
          );
          Navigator.pop(context, true); // Return true indicating deletion
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

  /// Public page of this article on the InternHub site (served from the API host).
  String get _articleUrl => '${ApiConfig.baseUrl}/blogs/${widget.slug}';

  Future<void> _share() async {
    final title = _post?.title ?? 'this article';
    try {
      await Share.share('$title\n$_articleUrl', subject: title);
    } catch (_) {
      // No share sheet available: fall back to copying the link.
      await Clipboard.setData(ClipboardData(text: _articleUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final canManage = canManageBlogs(user);

    final bgColor = AppColors.canvas;

    if (_isLoading && _post == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: pageAppBar(context, title: 'Article'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && _post == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: pageAppBar(context, title: 'Article'),
        body: LoadErrorView(title: "Couldn't open this article", message: _errorMessage!, onRetry: _fetchDetail),
      );
    }

    final post = _post!;
    final readTime = calculateReadingTime(post.content ?? post.excerpt);
    final displayDate = formatShortDate(post.publishedAt ?? post.createdAt);
    final cover = post.coverImageUrl?.trim();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: pageAppBar(
        context,
        title: 'Article',
        actions: [
          if (!post.isDraft) HeaderAction(icon: Icons.share_rounded, tooltip: 'Share', onTap: _share),
          if (canManage)
            HeaderAction(
              icon: Icons.delete_outline_rounded,
              color: AppColors.dangerInk,
              tooltip: 'Delete article',
              onTap: _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      AppTag(label: humanize(post.primaryTag), color: AppColors.infoInk, background: AppColors.infoSoft),
                      if (post.isDraft) const AppTag(label: 'Draft', color: AppColors.warningInk, background: AppColors.warningSoft),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(post.title, style: AppTypography.headline.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                  if (post.excerpt != null && post.excerpt!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(post.excerpt!.trim(), style: AppTypography.body.copyWith(height: 1.5, color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      AppAvatar(fallbackText: post.authorName, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(post.authorName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                            Text('$displayDate · $readTime', style: AppTypography.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (cover != null && cover.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          ApiConfig.mediaUrl(cover),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: AppColors.surfaceMuted,
                            child: const Icon(Icons.broken_image_outlined, color: AppColors.textTertiary),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  (post.content != null && post.content!.trim().isNotEmpty)
                      ? SafeHtmlView(html: post.content!)
                      : Text('This article has no body yet.', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
                  if (post.tags.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text('Topics', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in post.tags)
                          ActionChip(
                            label: Text(tag),
                            tooltip: 'Show articles tagged $tag',
                            onPressed: () => Navigator.pop(context, tag.toLowerCase().trim()),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
