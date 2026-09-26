import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/performance_review_model.dart';
import '../../../shared/models/user_model.dart';
import 'performance_review_dialog.dart';
import 'delete_review_dialog.dart';

class ReviewDetailModal extends StatelessWidget {
  final PerformanceReview review;
  final UserModel currentUser;
  final VoidCallback onDataChanged;

  const ReviewDetailModal({
    super.key,
    required this.review,
    required this.currentUser,
    required this.onDataChanged,
  });

  static void show(
    BuildContext context, {
    required PerformanceReview review,
    required UserModel currentUser,
    required VoidCallback onDataChanged,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReviewDetailModal(
        review: review,
        currentUser: currentUser,
        onDataChanged: onDataChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canManage = canManageReview(review, currentUser);
    final borderColor = AppColors.border;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          '${review.rating} / 5 Rating',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (review.projectName != null && review.projectName!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.infoSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.infoSoft,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 11,
                            color: AppColors.info,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            review.projectName!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.info,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Scrollable body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Intern Info Card
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            review.internInitials,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                review.internDisplayName,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.3,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Reviewed by ${review.reviewerDisplayName} • ${review.formattedCreatedAt}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              if (review.period != null && review.period!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Period: ${review.period}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Category ratings breakdown
                    if (review.hasCategoryRatings) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            if (review.technicalRating != null)
                              Expanded(
                                child: _buildCategoryPill('Technical', review.technicalRating!),
                              ),
                            if (review.communicationRating != null)
                              Expanded(
                                child: _buildCategoryPill('Communication', review.communicationRating!),
                              ),
                            if (review.initiativeRating != null)
                              Expanded(
                                child: _buildCategoryPill('Initiative', review.initiativeRating!),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    // Detailed Feedback
                    if (review.feedback != null && review.feedback!.trim().isNotEmpty) ...[
                      Text(
                        'Detailed Feedback',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: SelectableText(
                          review.feedback!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Key Strengths
                    if (review.strengths != null && review.strengths!.trim().isNotEmpty) ...[
                      Text(
                        'Key Strengths',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                        ),
                        child: SelectableText(
                          review.strengths!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.successInk,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Areas for Improvement
                    if (review.improvements != null && review.improvements!.trim().isNotEmpty) ...[
                      Text(
                        'Areas for Improvement',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.warning,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
                        ),
                        child: SelectableText(
                          review.improvements!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.warningInk,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Actions if canManage
                    if (canManage) ...[
                      Wrap(
                        alignment: WrapAlignment.end,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              final res = await PerformanceReviewDialog.show(context, review: review);
                              if (res == true) {
                                onDataChanged();
                              }
                            },
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.ink,
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              final res = await DeleteReviewDialog.show(context, review);
                              if (res == true) {
                                onDataChanged();
                              }
                            },
                            icon: const Icon(Icons.delete_outline_rounded, size: 16),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.dangerInk,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPill(String label, int rating) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
            const SizedBox(width: 3),
            Text(
              '$rating / 5',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
