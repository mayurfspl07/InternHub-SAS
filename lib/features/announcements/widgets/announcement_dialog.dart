import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/announcement_model.dart';
import '../announcements_repository.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

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
  String? _submitError;
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
      return 'Enter a title';
    }
    if (trimmed.length > 100) {
      return 'Use 100 characters or fewer';
    }
    return null;
  }

  String? _validateBody(String val) {
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      return 'Write the message';
    }
    if (trimmed.length > 3000) {
      return 'Use 3000 characters or fewer';
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

    // The field errors already show under each field.
    if (titleErr != null || bodyErr != null) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

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
        setState(() {
          _isSubmitting = false;
          _submitError = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleLength = _titleController.text.length;
    final bodyLength = _bodyController.text.length;

    final borderColor = AppColors.border;
    final cardBg = AppColors.surface;

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
                children: [
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit announcement' : 'New announcement',
                      style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ANNOUNCEMENT TITLE *
              Text('Title', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                maxLength: 100,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: AppTypography.body.copyWith(color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'e.g., Q3 Project Showcase Schedule',
                  hintStyle: AppTypography.body.copyWith(color: AppColors.textSecondary.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _titleError != null ? AppColors.danger : borderColor,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: _titleError != null ? AppColors.danger : AppColors.butter,
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
                        style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
                      )
                    else
                      const SizedBox.shrink(),
                    Text(
                      '$titleLength/100',
                      style: AppTypography.caption.copyWith(color: titleLength > 100 ? AppColors.dangerInk : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // MESSAGE CONTENT *
              Text('Message', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _bodyController,
                minLines: 5,
                maxLines: 8,
                maxLength: 3000,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: AppTypography.body.copyWith(color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'Provide detailed information, instructions, or links...',
                  hintStyle: AppTypography.body.copyWith(color: AppColors.textSecondary.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.all(16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _bodyError != null ? AppColors.danger : borderColor,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: _bodyError != null ? AppColors.danger : AppColors.butter,
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
                        style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
                      )
                    else
                      const SizedBox.shrink(),
                    Text(
                      '$bodyLength/3000',
                      style: AppTypography.caption.copyWith(color: bodyLength > 3000 ? AppColors.dangerInk : AppColors.textSecondary),
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
                            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Keep this announcement highlighted at the top of the feed',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: _isPinned,
                      activeThumbColor: AppColors.ink,
                      activeTrackColor: AppColors.primary,
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
                color: AppColors.border,
                height: 1,
              ),
              const SizedBox(height: 20),

              if (_submitError != null) ...[
                Text(_submitError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: BorderSide(
                        color: borderColor,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      minimumSize: const Size(0, 44),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.onPrimary),
                            ),
                          )
                        : Text(isEditing ? 'Save' : 'Post'),
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
            content: Text(apiErrorMessage(e)),
            backgroundColor: AppColors.dangerInk,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.dangerSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: AppColors.dangerInk, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Delete announcement?',
              style: AppTypography.section.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: Text(
        '"${widget.announcement.title}" disappears for everyone. You can restore it from the recycle bin.',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.ink),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: _isDeleting ? null : _handleDelete,
          child: _isDeleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
}
