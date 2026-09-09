import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/announcement_model.dart';
import '../announcements_repository.dart';

class AnnouncementDialog extends StatefulWidget {
  final Announcement? announcement; // If provided, edit mode

  const AnnouncementDialog({super.key, this.announcement});

  static Future<bool?> show(BuildContext context, {Announcement? announcement}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AnnouncementDialog(announcement: announcement),
    );
  }

  @override
  State<AnnouncementDialog> createState() => _AnnouncementDialogState();
}

class _AnnouncementDialogState extends State<AnnouncementDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late bool _isPinned;

  bool _isSubmitting = false;
  String? _titleError;
  String? _bodyError;

  bool get isEditing => widget.announcement != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.announcement?.title ?? '');
    _bodyController = TextEditingController(text: widget.announcement?.body ?? '');
    _isPinned = widget.announcement?.isPinned ?? false;

    _titleController.addListener(() {
      if (mounted) setState(() {});
    });
    _bodyController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  String? _validateTitle(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      return 'Title is required';
    }
    if (trimmed.length > 100) {
      return 'Title cannot exceed 100 characters';
    }
    return null;
  }

  String? _validateBody(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      return 'Body is required';
    }
    if (trimmed.length > 3000) {
      return 'Body cannot exceed 3000 characters';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    final titleErr = _validateTitle(_titleController.text);
    final bodyErr = _validateBody(_bodyController.text);

    setState(() {
      _titleError = titleErr;
      _bodyError = bodyErr;
    });

    if (titleErr != null || bodyErr != null) {
      final firstErr = titleErr ?? bodyErr;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(firstErr!),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo = AnnouncementsRepository();
      if (isEditing) {
        await repo.updateAnnouncement(
          id: widget.announcement!.id,
          title: _titleController.text,
          body: _bodyController.text,
          isPinned: _isPinned,
        );
      } else {
        await repo.createAnnouncement(
          title: _titleController.text,
          body: _bodyController.text,
          isPinned: _isPinned,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleLength = _titleController.text.length;
    final bodyLength = _bodyController.text.length;

    final borderColor = isDark ? AppColors.borderDark : const Color(0xFF1E293B);
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row: Title + Close Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Announcement' : 'New Announcement',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                  InkWell(
                    onTap: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppColors.borderDark : AppColors.borderLight,
                        ),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ANNOUNCEMENT TITLE *
              Row(
                children: [
                  Text(
                    'ANNOUNCEMENT TITLE',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '*',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                maxLength: 100,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g., Q3 Project Showcase Schedule',
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 14,
                    color: isDark ? Colors.white38 : AppColors.textSecondaryLight.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceDark : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _titleError != null ? Colors.red : borderColor,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _titleError != null ? Colors.red : AppColors.cardYellowDark,
                      width: 2,
                    ),
                  ),
                ),
              ),
              // Character counter & Error text
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_titleError != null)
                      Text(
                        _titleError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      )
                    else
                      const SizedBox.shrink(),
                    Text(
                      '$titleLength/100',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: titleLength > 100 ? Colors.red : (isDark ? Colors.white38 : AppColors.textSecondaryLight),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // MESSAGE CONTENT *
              Row(
                children: [
                  Text(
                    'MESSAGE CONTENT',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '*',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bodyController,
                minLines: 5,
                maxLines: 8,
                maxLength: 3000,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
                decoration: InputDecoration(
                  hintText: 'Provide detailed information, instructions, or links...',
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 14,
                    color: isDark ? Colors.white38 : AppColors.textSecondaryLight.withValues(alpha: 0.6),
                  ),
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceDark : Colors.white,
                  contentPadding: const EdgeInsets.all(16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _bodyError != null ? Colors.red : borderColor,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _bodyError != null ? Colors.red : AppColors.cardYellowDark,
                      width: 2,
                    ),
                  ),
                ),
              ),
              // Character counter & Error text
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_bodyError != null)
                      Text(
                        _bodyError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      )
                    else
                      const SizedBox.shrink(),
                    Text(
                      '$bodyLength/3000',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: bodyLength > 3000 ? Colors.red : (isDark ? Colors.white38 : AppColors.textSecondaryLight),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Pin to top Switch Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: borderColor,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pin to top',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Keep this announcement highlighted at the top of the feed',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: _isPinned,
                      activeThumbColor: Colors.black,
                      activeTrackColor: AppColors.cardYellow,
                      onChanged: _isSubmitting
                          ? null
                          : (val) {
                              setState(() => _isPinned = val);
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Divider
              Divider(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
                height: 1,
              ),
              const SizedBox(height: 20),

              // Action Buttons Row: Cancel & Publish
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                      side: BorderSide(
                        color: borderColor,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cardYellow,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : Text(
                            isEditing ? 'Save Changes' : 'Publish Announcement',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Delete Announcement Confirmation Dialog
class DeleteAnnouncementDialog extends StatefulWidget {
  final Announcement announcement;

  const DeleteAnnouncementDialog({super.key, required this.announcement});

  static Future<bool?> show(BuildContext context, Announcement announcement) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => DeleteAnnouncementDialog(announcement: announcement),
    );
  }

  @override
  State<DeleteAnnouncementDialog> createState() => _DeleteAnnouncementDialogState();
}

class _DeleteAnnouncementDialogState extends State<DeleteAnnouncementDialog> {
  bool _isDeleting = false;

  Future<void> _handleDelete() async {
    setState(() => _isDeleting = true);
    try {
      await AnnouncementsRepository().deleteAnnouncement(widget.announcement.id);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 24),
          ),
          const SizedBox(width: 12),
          Text(
            'Delete Announcement',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      content: Text(
        'Are you sure you want to delete "${widget.announcement.title}"? This action cannot be undone.',
        style: GoogleFonts.outfit(
          fontSize: 14,
          color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: GoogleFonts.outfit(color: isDark ? Colors.white70 : Colors.black87),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: _isDeleting ? null : _handleDelete,
          child: _isDeleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
}
