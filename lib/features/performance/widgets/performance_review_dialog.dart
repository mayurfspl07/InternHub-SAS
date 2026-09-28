import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/performance_review_model.dart';
import '../performance_repository.dart';
import 'star_rating.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

class PerformanceReviewDialog extends StatefulWidget {
  final PerformanceReview? review; // If provided, edit mode

  const PerformanceReviewDialog({super.key, this.review});

  static Future<bool?> show(BuildContext context, {PerformanceReview? review}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PerformanceReviewDialog(review: review),
    );
  }

  @override
  State<PerformanceReviewDialog> createState() => _PerformanceReviewDialogState();
}

class _PerformanceReviewDialogState extends State<PerformanceReviewDialog> {
  final PerformanceRepository _repository = PerformanceRepository();

  // Create mode state
  int? _selectedInternId;
  String? _selectedInternName;
  int? _selectedProjectId;
  String? _selectedProjectName;
  late final TextEditingController _periodController;

  // Ratings
  // Overall rating starts unset for a new review so a score is never pre-filled.
  int? _rating;
  // Optional sub-ratings: null until the reviewer picks a value (never invented).
  int? _technicalRating;
  int? _communicationRating;
  int? _initiativeRating;

  // Text inputs
  late final TextEditingController _feedbackController;
  late final TextEditingController _strengthsController;
  late final TextEditingController _improvementsController;

  bool _isSubmitting = false;
  String? _periodError;
  String? _feedbackError;
  String? _strengthsError;
  String? _improvementsError;
  String? _internError;
  String? _ratingError;
  String? _submitError;

  bool get isEditing => widget.review != null;

  @override
  void initState() {
    super.initState();
    final r = widget.review;

    if (isEditing) {
      _selectedInternId = r!.internId;
      _selectedInternName = r.internDisplayName;
      _selectedProjectId = r.projectId;
      _selectedProjectName = r.projectName;
      _periodController = TextEditingController(text: r.period ?? '');
      _rating = r.rating;
      _technicalRating = r.technicalRating;
      _communicationRating = r.communicationRating;
      _initiativeRating = r.initiativeRating;
      _feedbackController = TextEditingController(text: r.feedback ?? '');
      _strengthsController = TextEditingController(text: r.strengths ?? '');
      _improvementsController = TextEditingController(text: r.improvements ?? '');
    } else {
      _periodController = TextEditingController();
      _rating = null;
      _technicalRating = null;
      _communicationRating = null;
      _initiativeRating = null;
      _feedbackController = TextEditingController();
      _strengthsController = TextEditingController();
      _improvementsController = TextEditingController();
    }

    _periodController.addListener(() => setState(() {}));
    _feedbackController.addListener(() => setState(() {}));
    _strengthsController.addListener(() => setState(() {}));
    _improvementsController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _periodController.dispose();
    _feedbackController.dispose();
    _strengthsController.dispose();
    _improvementsController.dispose();
    super.dispose();
  }

  void _openInternPicker() async {

    final selected = await showModalBottomSheet<ReviewSelectOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SearchPickerSheet(
        title: 'Choose an intern',
        loadOptions: (query) => _repository.getInternOptions(search: query),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedInternId = selected.id;
        _selectedInternName = selected.label;
        _internError = null;
      });
    }
  }

  void _openProjectPicker() async {

    final selected = await showModalBottomSheet<ReviewSelectOption?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SearchPickerSheet(
        title: 'Choose a project',
        showNoneOption: true,
        noneLabel: 'No project',
        loadOptions: (query) => _repository.getProjectOptions(search: query),
      ),
    );

    // Dismissing the sheet (null) keeps the current choice; only "No project" (id 0) clears it.
    if (mounted && selected != null) {
      setState(() {
        if (selected.id == 0) {
          _selectedProjectId = null;
          _selectedProjectName = null;
        } else {
          _selectedProjectId = selected.id;
          _selectedProjectName = selected.label;
        }
      });
    }
  }

  bool _validateForm() {
    bool hasError = false;

    // Shown inline: a snackbar would sit behind this dialog.
    if (!isEditing && (_selectedInternId == null || _selectedInternId == 0)) {
      _internError = 'Choose who this review is for';
      hasError = true;
    } else {
      _internError = null;
    }
    if (_rating == null) {
      _ratingError = 'Pick an overall rating';
      hasError = true;
    } else {
      _ratingError = null;
    }

    if (_periodController.text.trim().length > 100) {
      _periodError = 'Use 100 characters or fewer';
      hasError = true;
    } else {
      _periodError = null;
    }

    if (_feedbackController.text.trim().length > 1000) {
      _feedbackError = 'Use 1000 characters or fewer';
      hasError = true;
    } else {
      _feedbackError = null;
    }

    if (_strengthsController.text.trim().length > 1000) {
      _strengthsError = 'Use 1000 characters or fewer';
      hasError = true;
    } else {
      _strengthsError = null;
    }

    if (_improvementsController.text.trim().length > 1000) {
      _improvementsError = 'Use 1000 characters or fewer';
      hasError = true;
    } else {
      _improvementsError = null;
    }

    setState(() {});
    return !hasError;
  }

  Future<void> _handleSubmit() async {
    if (!_validateForm()) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      if (isEditing) {
        await _repository.updateReview(
          id: widget.review!.id,
          rating: _rating!,
          technicalRating: _technicalRating,
          communicationRating: _communicationRating,
          initiativeRating: _initiativeRating,
          feedback: _feedbackController.text.trim(),
          strengths: _strengthsController.text.trim(),
          improvements: _improvementsController.text.trim(),
        );
      } else {
        await _repository.createReview(
          internId: _selectedInternId!,
          projectId: _selectedProjectId,
          period: _periodController.text.trim(),
          rating: _rating!,
          technicalRating: _technicalRating,
          communicationRating: _communicationRating,
          initiativeRating: _initiativeRating,
          feedback: _feedbackController.text.trim(),
          strengths: _strengthsController.text.trim(),
          improvements: _improvementsController.text.trim(),
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
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row: Title + Close Button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit review' : 'New review',
                      style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.ink),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Edit Mode Read-Only Banner
              if (isEditing) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          widget.review!.internInitials,
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.onPrimary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.review!.internDisplayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                            ),
                            if (widget.review!.period != null && widget.review!.period!.isNotEmpty)
                              Text(
                                'Period: ${widget.review!.period}',
                                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                      if (widget.review!.projectName != null) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.infoSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.review!.projectName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.label.copyWith(color: AppColors.infoInk),
                          ),
                        ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ] else ...[
                // INTERN * & PROJECT (OPTIONAL) Selectors
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 460;
                    if (isNarrow) {
                      return Column(
                        children: [
                          _buildInternPickerField(borderColor),
                          const SizedBox(height: 14),
                          _buildProjectPickerField(borderColor),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildInternPickerField(borderColor)),
                        const SizedBox(width: 12),
                        Expanded(child: _buildProjectPickerField(borderColor)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // EVALUATION PERIOD
                _buildFieldLabel('Period (optional)'),
                const SizedBox(height: 6),
                TextField(
                  controller: _periodController,
                  maxLength: 100,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                  style: AppTypography.body.copyWith(color: AppColors.ink),
                  decoration: _buildInputDecoration(
                    hint: 'e.g. Q3 2026',
                    borderColor: _periodError != null ? AppColors.danger : borderColor,
                  ),
                ),
                _buildCharCounter(_periodController.text.length, 100, _periodError),
                const SizedBox(height: 16),
              ],

              // OVERALL RATING *
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.warningSoft.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _ratingError != null ? AppColors.danger : AppColors.primarySoft,
                    width: 1.2,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Overall rating', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
                        Text(
                          _rating == null ? 'Not rated' : '$_rating / 5',
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.warningInk),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: StarRating(
                        rating: _rating ?? 0,
                        size: 32,
                        onRatingChanged: (val) => setState(() {
                          _rating = val;
                          _ratingError = null;
                        }),
                      ),
                    ),
                    if (_ratingError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(_ratingError!, style: AppTypography.label.copyWith(color: AppColors.dangerInk)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // CATEGORY RATINGS: Technical, Communication, Initiative
              LayoutBuilder(
                builder: (context, constraints) {
                  final isSmall = constraints.maxWidth < 480;
                  final cards = [
                    _buildCategoryStarBox('Technical', _technicalRating, (v) => setState(() => _technicalRating = v), borderColor),
                    _buildCategoryStarBox('Communication', _communicationRating, (v) => setState(() => _communicationRating = v), borderColor),
                    _buildCategoryStarBox('Initiative', _initiativeRating, (v) => setState(() => _initiativeRating = v), borderColor),
                  ];

                  if (isSmall) {
                    return Column(
                      children: [
                        cards[0],
                        const SizedBox(height: 10),
                        cards[1],
                        const SizedBox(height: 10),
                        cards[2],
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 8),
                      Expanded(child: cards[1]),
                      const SizedBox(width: 8),
                      Expanded(child: cards[2]),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

              // DETAILED FEEDBACK
              _buildFieldLabel('Feedback'),
              const SizedBox(height: 6),
              TextField(
                controller: _feedbackController,
                minLines: 3,
                maxLines: 5,
                maxLength: 1000,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: AppTypography.body.copyWith(color: AppColors.ink),
                decoration: _buildInputDecoration(
                  hint: 'What went well, what they delivered, how they grew',
                  borderColor: _feedbackError != null ? AppColors.danger : borderColor,
                ),
              ),
              _buildCharCounter(_feedbackController.text.length, 1000, _feedbackError),
              const SizedBox(height: 14),

              // KEY STRENGTHS
              _buildFieldLabel('Strengths'),
              const SizedBox(height: 6),
              TextField(
                controller: _strengthsController,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: AppTypography.body.copyWith(color: AppColors.ink),
                decoration: _buildInputDecoration(
                  hint: 'e.g. Clean APIs, helps teammates',
                  borderColor: _strengthsError != null ? AppColors.danger : borderColor,
                ),
              ),
              _buildCharCounter(_strengthsController.text.length, 1000, _strengthsError),
              const SizedBox(height: 14),

              // AREAS FOR IMPROVEMENT
              _buildFieldLabel('To improve'),
              const SizedBox(height: 6),
              TextField(
                controller: _improvementsController,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: AppTypography.body.copyWith(color: AppColors.ink),
                decoration: _buildInputDecoration(
                  hint: 'e.g. More tests, clearer docs',
                  borderColor: _improvementsError != null ? AppColors.danger : borderColor,
                ),
              ),
              _buildCharCounter(_improvementsController.text.length, 1000, _improvementsError),
              if (_submitError != null) ...[
                const SizedBox(height: 8),
                Text(_submitError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
              ],
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: BorderSide(color: borderColor, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      minimumSize: const Size(0, 44),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                          )
                        : Text(isEditing ? 'Save' : 'Submit review'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Row(
      children: [
        Text(label, style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
      ],
    );
  }

  Widget _buildInternPickerField(Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('Intern'),
        const SizedBox(height: 6),
        InkWell(
          onTap: _openInternPicker,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _internError != null ? AppColors.danger : borderColor, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedInternName ?? 'Choose an intern',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyStrong.copyWith(color: _selectedInternName != null
                          ? AppColors.ink
                          : (AppColors.textSecondary.withValues(alpha: 0.6))),
                  ),
                ),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_internError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_internError!, style: AppTypography.label.copyWith(color: AppColors.dangerInk)),
          ),
      ],
    );
  }

  Widget _buildProjectPickerField(Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('Project (optional)'),
        const SizedBox(height: 6),
        InkWell(
          onTap: _openProjectPicker,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedProjectName ?? 'No project',
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyStrong.copyWith(color: _selectedProjectName != null
                          ? AppColors.ink
                          : AppColors.textSecondary),
                  ),
                ),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryStarBox(
    String title,
    int? rating,
    ValueChanged<int> onChanged,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title (optional)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                rating == null ? 'Not rated' : '$rating / 5',
                style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.warningInk),
              ),
            ],
          ),
          const SizedBox(height: 6),
          StarRating(
            rating: rating ?? 0,
            size: 20,
            onRatingChanged: onChanged,
          ),
        ],
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    required Color borderColor,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.caption.copyWith(color: AppColors.textSecondary.withValues(alpha: 0.6)),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.all(14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
    );
  }

  Widget _buildCharCounter(int current, int max, String? error) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (error != null)
            Flexible(child: Text(error, style: AppTypography.label.copyWith(color: AppColors.dangerInk)))
          else
            const SizedBox.shrink(),
          Text(
            '$current/$max',
            style: AppTypography.label.copyWith(color: current > max ? AppColors.dangerInk : AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Searchable Picker Sheet for Interns / Projects
class _SearchPickerSheet extends StatefulWidget {
  final String title;
  final bool showNoneOption;
  final String noneLabel;
  final Future<List<ReviewSelectOption>> Function(String query) loadOptions;

  const _SearchPickerSheet({
    required this.title,
    this.showNoneOption = false,
    this.noneLabel = 'None',
    required this.loadOptions,
  });

  @override
  State<_SearchPickerSheet> createState() => _SearchPickerSheetState();
}

class _SearchPickerSheetState extends State<_SearchPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<ReviewSelectOption> _options = [];
  bool _isLoading = true;
  String? _error;
  Timer? _debounce;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final query = _searchCtrl.text.trim();
    _activeQuery = query;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.loadOptions(query);
      if (mounted && query == _activeQuery) {
        setState(() {
          _options = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && query == _activeQuery) {
        setState(() {
          _isLoading = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Shrink above the keyboard so the results stay visible while typing.
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
      constraints: BoxConstraints(
        maxHeight: (media.size.height * 0.75 - media.viewInsets.bottom).clamp(240.0, media.size.height),
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), _fetch);
                },
                style: AppTypography.body.copyWith(color: AppColors.ink),
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppColors.border,
                    ),
                  ),
                ),
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? LoadErrorView(title: "Couldn't load the list", message: _error!, onRetry: _fetch, compact: true)
                  : ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        if (widget.showNoneOption)
                          ListTile(
                            leading: const Icon(Icons.block_rounded, size: 20),
                            title: Text(widget.noneLabel, style: AppTypography.bodyStrong),
                            onTap: () => Navigator.pop(context, const ReviewSelectOption(id: 0, label: 'None')),
                          ),
                        if (_options.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: Text(
                                'Nothing matches that search',
                                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                          )
                        else
                          ..._options.map((opt) {
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 15,
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  opt.label.isNotEmpty ? opt.label[0].toUpperCase() : '?',
                                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.onPrimary),
                                ),
                              ),
                              title: Text(opt.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                              subtitle: opt.subtitle != null
                                  ? Text(opt.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption)
                                  : null,
                              onTap: () => Navigator.pop(context, opt),
                            );
                          }),
                      ],
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
