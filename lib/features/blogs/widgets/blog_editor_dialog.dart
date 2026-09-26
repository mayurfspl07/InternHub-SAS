import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../blog_repository.dart';
import '../models/blog_models.dart';
import 'safe_html_view.dart';
import '../../../core/constants/app_colors.dart';

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
  bool _isPublished = true;
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
    _isPublished = p != null ? p.isPublished : true;

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

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title must be at least 3 characters long'), backgroundColor: AppColors.danger),
      );
      return;
    }
    if (title.length > 150) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title cannot exceed 150 characters'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final slug = _slugController.text.trim();
    if (slug.isNotEmpty && !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Slug may only contain lowercase letters, numbers, and single hyphens'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (tags.length > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximum 5 tags allowed'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final excerpt = _excerptController.text.trim();
    if (excerpt.length > 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excerpt cannot exceed 300 characters'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content is required'), backgroundColor: AppColors.danger),
      );
      return;
    }

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
          SnackBar(
            content: Text(isEdit ? 'Article updated successfully' : 'Article created successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSaved(saved);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save article: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final titleLen = _titleController.text.length;
    final titleOverWarning = titleLen > 100;

    return Dialog(
      backgroundColor: cardBg,
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
                          isEdit ? 'Edit Article' : 'Write New Article',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isEdit
                              ? 'Update publication content, tags, and status.'
                              : 'Draft and publish insights to the InternHub blog feed.',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
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
                padding: const EdgeInsets.all(24),
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
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: secondaryTextColor,
                              ),
                              children: const [
                                TextSpan(text: 'ARTICLE TITLE '),
                                TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                              ],
                            ),
                          ),
                          Text(
                            '$titleLen/100',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: titleOverWarning ? AppColors.danger : secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _titleController,
                        maxLength: 150,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: TextStyle(fontSize: 14, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. 5 Common Financial Mistakes to Avoid',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
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
                            'CUSTOM SLUG (OPTIONAL)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: secondaryTextColor,
                            ),
                          ),
                          Text(
                            'Auto-generated from title',
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _slugController,
                        onChanged: (_) => _slugManuallyEdited = true,
                        style: GoogleFonts.robotoMono(fontSize: 12, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. 5-common-financial-mistakes',
                          hintStyle: GoogleFonts.robotoMono(fontSize: 12, color: secondaryTextColor),
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
                            'TAGS (COMMA-SEPARATED)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: secondaryTextColor,
                            ),
                          ),
                          Text(
                            'Max 5 tags (e.g. Engineering, Guide)',
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _tagsController,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'e.g. Engineering, Product, News',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
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
                            'EXCERPT (OPTIONAL)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: secondaryTextColor,
                            ),
                          ),
                          Text(
                            '${_excerptController.text.length}/300',
                            style: TextStyle(fontSize: 11, color: secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _excerptController,
                        maxLines: 2,
                        maxLength: 300,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'Brief summary of the article...',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Cover Image URL
                      Text(
                        'COVER IMAGE URL (OPTIONAL)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _coverUrlController,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'https://images.unsplash.com/...',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
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
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryTextColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isPublished
                                        ? 'Article will be immediately visible to all readers'
                                        : 'Article saved as draft; visible to administrators only',
                                    style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isPublished,
                              activeThumbColor: AppColors.success,
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
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: secondaryTextColor,
                              ),
                              children: const [
                                TextSpan(text: 'CONTENT '),
                                TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
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
                              style: TextStyle(fontSize: 13.5, height: 1.5, color: primaryTextColor),
                              decoration: InputDecoration(
                                hintText: '<p>Write your article content here (HTML supported)...</p>',
                                hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
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
                                            style: TextStyle(color: secondaryTextColor, fontSize: 13),
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
            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.warning, width: 1),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink),
                          )
                        : Text(
                            isEdit ? 'Save Changes' : 'Publish Article',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
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
