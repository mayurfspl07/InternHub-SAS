import 'package:flutter/material.dart';
import '../blog_repository.dart';
import '../models/blog_models.dart';
import 'safe_html_view.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

class BlogEditorDialog extends StatefulWidget {
  final BlogPost? post; // If null, create mode; otherwise edit mode
  final Function(BlogPost savedPost) onSaved;

  const BlogEditorDialog({
    super.key,
    this.post,
    required this.onSaved,
  });

  @override
  State<BlogEditorDialog> createState() => _BlogEditorDialogState();
}

class _BlogEditorDialogState extends State<BlogEditorDialog> with SingleTickerProviderStateMixin {
  final BlogRepository _repository = BlogRepository();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _slugController;
  late TextEditingController _tagsController;
  late TextEditingController _excerptController;
  late TextEditingController _coverUrlController;
  late TextEditingController _contentController;

  late TabController _tabController;
  bool _isPublished = false;
  String? _formError;
  bool _slugManuallyEdited = false;
  bool _isSubmitting = false;

  bool get isEdit => widget.post != null;

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    _titleController = TextEditingController(text: p?.title ?? '');
    _slugController = TextEditingController(text: p?.slug ?? '');
    _tagsController = TextEditingController(text: p?.tags.join(', ') ?? '');
    _excerptController = TextEditingController(text: p?.excerpt ?? '');
    _coverUrlController = TextEditingController(text: p?.coverImageUrl ?? '');
    _contentController = TextEditingController(text: p?.content ?? '');
    // New articles start as drafts; publishing is a deliberate switch.
    _isPublished = p != null ? p.isPublished : false;

    _tabController = TabController(length: 2, vsync: this);

    _titleController.addListener(() {
      if (!isEdit && !_slugManuallyEdited) {
        _slugController.text = generateBlogSlug(_titleController.text);
      }
      setState(() {});
    });

    _slugController.addListener(() => setState(() {}));
    _excerptController.addListener(() => setState(() {}));
    _contentController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _slugController.dispose();
    _tagsController.dispose();
    _excerptController.dispose();
    _coverUrlController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  /// First problem with the form, or null. Shown inside the dialog, not in a snackbar behind it.
  String? _problem(String title, String slug, List<String> tags, String excerpt, String content) {
    if (title.length < 3) return 'Give the article a title of at least 3 characters.';
    if (title.length > 150) return 'Keep the title to 150 characters.';
    if (slug.isNotEmpty && !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
      return 'Use lowercase letters, numbers and single hyphens in the link.';
    }
    if (tags.length > 5) return 'Use at most 5 tags.';
    if (excerpt.length > 300) return 'Keep the summary to 300 characters.';
    if (content.isEmpty) return 'Write the article body.';
    return null;
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final slug = _slugController.text.trim();
    final tags = _tagsController.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final excerpt = _excerptController.text.trim();
    final content = _contentController.text.trim();

    final problem = _problem(title, slug, tags, excerpt, content);
    setState(() => _formError = problem);
    if (problem != null) return;

    setState(() => _isSubmitting = true);

    try {
      BlogPost saved;
      if (isEdit) {
        saved = await _repository.updateBlog(
          widget.post!.id,
          title: title,
          content: content,
          slug: slug.isNotEmpty ? slug : null,
          excerpt: excerpt.isNotEmpty ? excerpt : null,
          coverImageUrl: _coverUrlController.text.trim().isNotEmpty ? _coverUrlController.text.trim() : null,
          tags: tags,
          status: _isPublished ? 'published' : 'draft',
        );
      } else {
        saved = await _repository.createBlog(
          title: title,
          content: content,
          slug: slug.isNotEmpty ? slug : null,
          excerpt: excerpt.isNotEmpty ? excerpt : null,
          coverImageUrl: _coverUrlController.text.trim().isNotEmpty ? _coverUrlController.text.trim() : null,
          tags: tags,
          status: _isPublished ? 'published' : 'draft',
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isPublished ? 'Article published' : 'Draft saved')),
        );
        widget.onSaved(saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _formError = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final titleLen = _titleController.text.length;
    final titleOverWarning = titleLen > 150;

    return Dialog(
      backgroundColor: cardBg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 700,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEdit ? 'Edit article' : 'New article',
                          style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isEdit
                              ? 'Update the text, tags or status.'
                              : 'Save a draft or publish it to everyone.',
                          style: AppTypography.caption.copyWith(color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: secondaryTextColor,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Article Title * (required; min 3; max 150; counter /100)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: AppTypography.bodyStrong.copyWith(fontSize: 13),
                              children: const [
                                TextSpan(text: 'Title'),
                              ],
                            ),
                          ),
                          Text(
                            '$titleLen/150',
                            style: AppTypography.label.copyWith(color: titleOverWarning ? AppColors.dangerInk : secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _titleController,
                        maxLength: 150,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: AppTypography.body.copyWith(color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. How we run code reviews',
                          hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Custom Slug (Optional)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Link (optional)',
                            style: AppTypography.bodyStrong.copyWith(fontSize: 13),
                          ),
                          Text(
                            'Made from the title if empty',
                            style: AppTypography.label.copyWith(color: secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _slugController,
                        onChanged: (_) => _slugManuallyEdited = true,
                        style: AppTypography.mono.copyWith(fontSize: 12, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. how-we-run-code-reviews',
                          hintStyle: AppTypography.mono.copyWith(fontSize: 12, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Tags (comma-separated, max 5)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tags',
                            style: AppTypography.bodyStrong.copyWith(fontSize: 13),
                          ),
                          Text(
                            'Up to 5, separated by commas',
                            style: AppTypography.label.copyWith(color: secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _tagsController,
                        style: AppTypography.caption.copyWith(color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. Engineering, Product, News',
                          hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Excerpt (Optional, max 300)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Summary (optional)',
                            style: AppTypography.bodyStrong.copyWith(fontSize: 13),
                          ),
                          Text(
                            '${_excerptController.text.length}/300',
                            style: AppTypography.label.copyWith(color: secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _excerptController,
                        maxLines: 2,
                        maxLength: 300,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: AppTypography.caption.copyWith(color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'One or two sentences shown on the article card',
                          hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Cover Image URL
                      Text(
                        'Cover image link (optional)',
                        style: AppTypography.bodyStrong.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _coverUrlController,
                        style: AppTypography.caption.copyWith(color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'https://…',
                          hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Status Toggle
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isPublished ? 'Published' : 'Draft',
                                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isPublished
                                        ? 'Everyone can read it as soon as you save'
                                        : 'Only people who manage blogs can see it',
                                    style: AppTypography.label.copyWith(color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isPublished,
                              activeThumbColor: AppColors.primary,
                              onChanged: (v) => setState(() => _isPublished = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Content * with Tabs (Edit | Preview)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: AppTypography.bodyStrong.copyWith(fontSize: 13),
                              children: const [
                                TextSpan(text: 'Body (HTML)'),
                              ],
                            ),
                          ),
                          Container(
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              isScrollable: true,
                              labelColor: AppColors.ink,
                              unselectedLabelColor: secondaryTextColor,
                              indicator: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              tabs: const [
                                Tab(text: 'Edit'),
                                Tab(text: 'Preview'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      SizedBox(
                        height: 260,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Edit Tab
                            TextFormField(
                              controller: _contentController,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              style: AppTypography.caption.copyWith(height: 1.5, color: primaryTextColor),
                              decoration: InputDecoration(
                                hintText: '<p>Write the article here. Basic HTML works.</p>',
                                hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                                contentPadding: const EdgeInsets.all(14),
                              ),
                            ),

                            // Preview Tab
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: borderColor),
                              ),
                              child: SingleChildScrollView(
                                child: _contentController.text.trim().isNotEmpty
                                    ? SafeHtmlView(html: _contentController.text)
                                    : Center(
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 80),
                                          child: Text(
                                            'Nothing to preview yet.',
                                            style: AppTypography.caption.copyWith(color: secondaryTextColor),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),
            if (_formError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(_formError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                          )
                        // The label says what the switch above will do.
                        : Text(_isPublished ? (isEdit && widget.post!.isPublished ? 'Save' : 'Publish') : 'Save draft'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
