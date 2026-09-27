import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_config.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import 'blog_repository.dart';
import 'models/blog_models.dart';
import 'widgets/safe_html_view.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/app_tag.dart';
import '../../shared/widgets/page_header.dart';

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
            _errorMessage = e.toString();
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Move article to Recycle Bin?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(
            'Are you sure you want to delete "${_post?.title}"? You can restore it later from the Recycle Bin.',
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

    if (confirmed == true && _post != null) {
      try {
        await _repository.deleteBlog(_post!.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Article moved to Recycle Bin'),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true); // Return true indicating deletion
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

  /// Public page of this article on the InternHub site (served from the API host).
  String get _articleUrl => '${ApiConfig.baseUrl}/blogs/${widget.slug}';

  void _shareCopyUrl() {
    final url = _articleUrl;
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Article link copied to clipboard!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _shareTwitter() async {
    final url = _articleUrl;
    final text = Uri.encodeComponent('Check out "${_post?.title ?? 'this article'}" on InternHub:');
    final twitterUrl = Uri.parse('https://twitter.com/intent/tweet?text=$text&url=${Uri.encodeComponent(url)}');
    if (await canLaunchUrl(twitterUrl)) {
      await launchUrl(twitterUrl, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareLinkedIn() async {
    final url = _articleUrl;
    final linkedInUrl = Uri.parse('https://www.linkedin.com/sharing/share-offsite/?url=${Uri.encodeComponent(url)}');
    if (await canLaunchUrl(linkedInUrl)) {
      await launchUrl(linkedInUrl, mode: LaunchMode.externalApplication);
    }
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

    if (_isLoading && _post == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: pageAppBar(context, title: 'Loading article'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null && _post == null) {
      return Scaffold(
        backgroundColor: bgColor,
        appBar: pageAppBar(context, title: 'Article not found'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.article_outlined, size: 60, color: secondaryTextColor.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text(
                  'Article not found or unavailable.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryTextColor),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Return to Articles'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final post = _post!;
    final readTime = calculateReadingTime(post.content ?? post.excerpt);
    final displayDate = formatShortDate(post.publishedAt ?? post.createdAt);
    final initials = getInitials(post.authorName);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: pageAppBar(
        context,
        title: 'Article',
        actions: [
          if (canManage) ...[
            if (post.isDraft)
              const AppTag(
                label: 'Draft',
                color: AppColors.warningInk,
                background: AppColors.warningSoft,
              ),
            HeaderAction(
              icon: Icons.delete_outline_rounded,
              color: AppColors.danger,
              tooltip: 'Move to Bin',
              onTap: _confirmDelete,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Primary Tag Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      post.primaryTag.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.info,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    post.title,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                      color: primaryTextColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),

                  // Excerpt (if present)
                  if (post.excerpt != null && post.excerpt!.trim().isNotEmpty) ...[
                    Text(
                      post.excerpt!,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: secondaryTextColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Meta Row (Author, Date, Read Time)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        post.authorName,
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryTextColor),
                      ),
                      const SizedBox(width: 8),
                      Text('•', style: TextStyle(color: secondaryTextColor)),
                      const SizedBox(width: 8),
                      Text(displayDate, style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                      const SizedBox(width: 8),
                      Text('•', style: TextStyle(color: secondaryTextColor)),
                      const SizedBox(width: 8),
                      Text(readTime, style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Cover Image (or placeholder)
                  if (post.coverImageUrl != null && post.coverImageUrl!.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.network(
                        post.coverImageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 380,
                        errorBuilder: (context, error, stackTrace) => _buildPlaceholderCover(cardBg, borderColor, secondaryTextColor),
                      ),
                    )
                  else
                    _buildPlaceholderCover(cardBg, borderColor, secondaryTextColor),
                  const SizedBox(height: 32),

                  // Body Content (SafeHtmlView)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: (post.content != null && post.content!.trim().isNotEmpty)
                        ? SafeHtmlView(html: post.content!)
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                'No extended content available for this article.',
                                style: TextStyle(color: secondaryTextColor, fontSize: 14),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 32),

                  // Topics / Tags Section
                  if (post.tags.isNotEmpty) ...[
                    const Divider(height: 1),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'TOPICS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: secondaryTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: post.tags.map((tag) {
                          return ActionChip(
                            label: Text(tag),
                            backgroundColor: cardBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: borderColor),
                            ),
                            onPressed: () {
                              Navigator.pop(context, tag.toLowerCase().trim());
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 28),
                  ],

                  // Author & Share Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.info,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Written by ${post.authorName}',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryTextColor),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Contributing to InternHub publications & resources.',
                                style: TextStyle(fontSize: 12, color: secondaryTextColor),
                              ),
                            ],
                          ),
                        ),
                        // Share Buttons
                        IconButton(
                          icon: const Icon(Icons.link_rounded, size: 20),
                          tooltip: 'Copy Link',
                          onPressed: _shareCopyUrl,
                        ),
                        IconButton(
                          icon: const Icon(Icons.tag_rounded, size: 20),
                          tooltip: 'Share on X / Twitter',
                          onPressed: _shareTwitter,
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_rounded, size: 20),
                          tooltip: 'Share on LinkedIn',
                          onPressed: _shareLinkedIn,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Bottom CTA Banner to Dashboard
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ready to scale your internship programs?',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Explore automated workflows, tasks, evaluations, and attendance tracking.',
                                style: TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.ink,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Open Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderCover(Color cardBg, Color borderColor, Color secondaryTextColor) {
    return Container(
      width: double.infinity,
      height: 240,
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
            const SizedBox(height: 8),
            Text(
              'InternHub Publications',
              style: TextStyle(fontSize: 12, color: secondaryTextColor, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
