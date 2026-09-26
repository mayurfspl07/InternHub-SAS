import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/performance_review_model.dart';
import '../performance_repository.dart';
import 'star_rating.dart';

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
  late int _rating;
  late int _technicalRating;
  late int _communicationRating;
  late int _initiativeRating;

  // Text inputs
  late final TextEditingController _feedbackController;
  late final TextEditingController _strengthsController;
  late final TextEditingController _improvementsController;

  bool _isSubmitting = false;
  String? _periodError;
  String? _feedbackError;
  String? _strengthsError;
  String? _improvementsError;

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
      _technicalRating = r.technicalRating ?? 5;
      _communicationRating = r.communicationRating ?? 4;
      _initiativeRating = r.initiativeRating ?? 5;
      _feedbackController = TextEditingController(text: r.feedback ?? '');
      _strengthsController = TextEditingController(text: r.strengths ?? '');
      _improvementsController = TextEditingController(text: r.improvements ?? '');
    } else {
      _periodController = TextEditingController();
      _rating = 5;
      _technicalRating = 5;
      _communicationRating = 4;
      _initiativeRating = 5;
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
        title: 'Select Intern',
        loadOptions: (query) => _repository.getInternOptions(search: query),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedInternId = selected.id;
        _selectedInternName = selected.label;
      });
    }
  }

  void _openProjectPicker() async {

    final selected = await showModalBottomSheet<ReviewSelectOption?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SearchPickerSheet(
        title: 'Select Project',
        showNoneOption: true,
        noneLabel: 'No project',
        loadOptions: (query) => _repository.getProjectOptions(search: query),
      ),
    );

    if (mounted) {
      setState(() {
        if (selected == null || selected.id == 0) {
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

    if (!isEditing && (_selectedInternId == null || _selectedInternId == 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an intern to review'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    if (_periodController.text.trim().length > 100) {
      _periodError = 'Evaluation period cannot exceed 100 characters';
      hasError = true;
    } else {
      _periodError = null;
    }

    if (_feedbackController.text.trim().length > 1000) {
      _feedbackError = 'Feedback cannot exceed 1000 characters';
      hasError = true;
    } else {
      _feedbackError = null;
    }

    if (_strengthsController.text.trim().length > 1000) {
      _strengthsError = 'Strengths cannot exceed 1000 characters';
      hasError = true;
    } else {
      _strengthsError = null;
    }

    if (_improvementsController.text.trim().length > 1000) {
      _improvementsError = 'Areas for improvement cannot exceed 1000 characters';
      hasError = true;
    } else {
      _improvementsError = null;
    }

    setState(() {});
    return !hasError;
  }

  Future<void> _handleSubmit() async {
    if (!_validateForm()) return;

    setState(() => _isSubmitting = true);

    try {
      if (isEditing) {
        await _repository.updateReview(
          id: widget.review!.id,
          rating: _rating,
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
          rating: _rating,
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
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
            backgroundColor: AppColors.dangerInk,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Performance Review' : 'Submit Performance Review',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: AppColors.ink,
                    ),
                  ),
                  InkWell(
                    onTap: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
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
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.review!.internDisplayName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            if (widget.review!.period != null && widget.review!.period!.isNotEmpty)
                              Text(
                                'Period: ${widget.review!.period}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (widget.review!.projectName != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.infoSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.review!.projectName!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.info,
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
                _buildFieldLabel('EVALUATION PERIOD'),
                const SizedBox(height: 6),
                TextField(
                  controller: _periodController,
                  maxLength: 100,
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                  style: TextStyle(fontSize: 14, color: AppColors.ink),
                  decoration: _buildInputDecoration(
                    hint: 'e.g., Q3 2026, Mid-Term Q3 2026',
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
                    color: AppColors.primarySoft,
                    width: 1.2,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'OVERALL RATING',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('*', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text(
                          '$_rating / 5',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: StarRating(
                        rating: _rating,
                        size: 32,
                        onRatingChanged: (val) => setState(() => _rating = val),
                      ),
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
                    _buildCategoryStarBox('TECHNICAL', _technicalRating, (v) => setState(() => _technicalRating = v), borderColor),
                    _buildCategoryStarBox('COMMUNICATION', _communicationRating, (v) => setState(() => _communicationRating = v), borderColor),
                    _buildCategoryStarBox('INITIATIVE', _initiativeRating, (v) => setState(() => _initiativeRating = v), borderColor),
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
              _buildFieldLabel('DETAILED FEEDBACK'),
              const SizedBox(height: 6),
              TextField(
                controller: _feedbackController,
                minLines: 3,
                maxLines: 5,
                maxLength: 1000,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: TextStyle(fontSize: 14, color: AppColors.ink),
                decoration: _buildInputDecoration(
                  hint: 'Provide detailed observations on performance, deliverables, and growth...',
                  borderColor: _feedbackError != null ? AppColors.danger : borderColor,
                ),
              ),
              _buildCharCounter(_feedbackController.text.length, 1000, _feedbackError),
              const SizedBox(height: 14),

              // KEY STRENGTHS
              _buildFieldLabel('KEY STRENGTHS'),
              const SizedBox(height: 6),
              TextField(
                controller: _strengthsController,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: TextStyle(fontSize: 14, color: AppColors.ink),
                decoration: _buildInputDecoration(
                  hint: 'e.g., Python, FastAPI, proactive collaboration, architecture...',
                  borderColor: _strengthsError != null ? AppColors.danger : borderColor,
                ),
              ),
              _buildCharCounter(_strengthsController.text.length, 1000, _strengthsError),
              const SizedBox(height: 14),

              // AREAS FOR IMPROVEMENT
              _buildFieldLabel('AREAS FOR IMPROVEMENT'),
              const SizedBox(height: 6),
              TextField(
                controller: _improvementsController,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                style: TextStyle(fontSize: 14, color: AppColors.ink),
                decoration: _buildInputDecoration(
                  hint: 'e.g., Continue expanding integration tests, system design documentation...',
                  borderColor: _improvementsError != null ? AppColors.danger : borderColor,
                ),
              ),
              _buildCharCounter(_improvementsController.text.length, 1000, _improvementsError),
              const SizedBox(height: 20),

              // Action Buttons Row: Cancel & Submit Review
              Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: BorderSide(color: borderColor, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shadowColor: AppColors.primary.withValues(alpha: 0.35),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : Text(
                            isEditing ? 'Save Changes' : 'Submit Review',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.textSecondary,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          const Text('*', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }

  Widget _buildInternPickerField(Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('INTERN', required: true),
        const SizedBox(height: 6),
        InkWell(
          onTap: _openInternPicker,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 1.2),
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
                    _selectedInternName ?? 'Select intern being reviewed...',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedInternName != null
                          ? AppColors.ink
                          : (AppColors.textSecondary.withValues(alpha: 0.6)),
                      fontWeight: _selectedInternName != null ? FontWeight.w600 : FontWeight.normal,
                    ),
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

  Widget _buildProjectPickerField(Color borderColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('PROJECT (OPTIONAL)'),
        const SizedBox(height: 6),
        InkWell(
          onTap: _openProjectPicker,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
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
                    style: TextStyle(
                      fontSize: 14,
                      color: _selectedProjectName != null
                          ? AppColors.ink
                          : AppColors.textSecondary,
                      fontWeight: _selectedProjectName != null ? FontWeight.w600 : FontWeight.normal,
                    ),
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
    int rating,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                '$rating / 5',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          StarRating(
            rating: rating,
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
      hintStyle: TextStyle(
        fontSize: 13.5,
        color: AppColors.textSecondary.withValues(alpha: 0.6),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.all(14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: borderColor, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.warning, width: 1.8),
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
            Text(error, style: const TextStyle(color: AppColors.danger, fontSize: 11))
          else
            const SizedBox.shrink(),
          Text(
            '$current/$max',
            style: TextStyle(
              fontSize: 11,
              color: current > max ? AppColors.danger : AppColors.textSecondary,
            ),
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

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    final res = await widget.loadOptions(_searchCtrl.text.trim());
    if (mounted) {
      setState(() {
        _options = res;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  IconButton(
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
                onChanged: (_) => _fetch(),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.ink,
                ),
                decoration: InputDecoration(
                  hintText: 'Search...',
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
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        if (widget.showNoneOption)
                          ListTile(
                            leading: const Icon(Icons.block_rounded, size: 20),
                            title: Text(widget.noneLabel, style: TextStyle(fontWeight: FontWeight.w600)),
                            onTap: () => Navigator.pop(context, const ReviewSelectOption(id: 0, label: 'None')),
                          ),
                        if (_options.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            child: Center(
                              child: Text(
                                'No matching results found',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                ),
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
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                                ),
                              ),
                              title: Text(opt.label, style: TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: opt.subtitle != null
                                  ? Text(opt.subtitle!, style: TextStyle(fontSize: 12))
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
    );
  }
}
