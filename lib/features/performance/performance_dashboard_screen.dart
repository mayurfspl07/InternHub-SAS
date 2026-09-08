import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import 'create_review_bottom_sheet.dart';

class PerformanceDashboardScreen extends ConsumerWidget {
  const PerformanceDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reviews = state.reviews;
    final user = state.currentUser;
    final isMentorOrAdmin = user.role == UserRole.admin || user.role == UserRole.mentor;

    final rating = user.performanceRating;

    return Scaffold(
      appBar: AppBar(
        title: const Text('360 Performance ⭐', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(appStateProvider.notifier).fetchReviews(),
          ),
          if (isMentorOrAdmin)
            IconButton(
              icon: const Icon(Icons.rate_review_outlined),
              tooltip: 'New Review',
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  builder: (_) => const CreateReviewBottomSheet(),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchReviews(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.p20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero Rating Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardYellow,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.cardYellow.withValues(alpha: 0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Overall Rating',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            ),
                            child: const Text('Evaluation Metric', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            '⭐ ${rating.toStringAsFixed(1)}',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '/ 5.0',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.bio != null && user.bio!.isNotEmpty
                            ? user.bio!
                            : 'Engineering performance, milestone updates, and mentor feedback summary.',
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Skill Competencies Breakdown
                Text(
                  'Skill Competencies',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 14),

                if (reviews.isNotEmpty && reviews.first.skills.isNotEmpty)
                  Column(
                    children: reviews.first.skills.map((skill) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? AppColors.borderDark : AppColors.borderLight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  skill.skillName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                  ),
                                ),
                                Text(
                                  '${skill.score.toStringAsFixed(1)} / 5.0',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (skill.score / 5.0).clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: isDark ? const Color(0xFF2C3142) : const Color(0xFFF3F4F6),
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                else
                  _buildDefaultSkills(isDark),
                const SizedBox(height: 24),

                // Mentor Reviews Timeline
                Text(
                  'Milestone Reviews History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 14),

                if (reviews.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? AppColors.borderDark : AppColors.borderLight,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.star_outline_rounded, size: 48, color: isDark ? Colors.white38 : AppColors.textSecondaryLight),
                        const SizedBox(height: 12),
                        Text(
                          'No reviews published yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mentor milestone reviews will appear here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: reviews.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final review = reviews[index];
                      final dateStr = DateFormat('MMM d, yyyy').format(review.reviewDate);

                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark ? AppColors.borderDark : AppColors.borderLight,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                      backgroundImage: review.mentorAvatar.isNotEmpty ? NetworkImage(review.mentorAvatar) : null,
                                      child: review.mentorAvatar.isEmpty
                                          ? Text(
                                              review.mentorName.isNotEmpty ? review.mentorName[0].toUpperCase() : 'M',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Evaluated by ${review.mentorName}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                          ),
                                        ),
                                        Text(
                                          '$dateStr • ${review.quarterLabel}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                  ),
                                  child: Text(
                                    '⭐ ${review.overallRating.toStringAsFixed(1)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF92400E)),
                                  ),
                                ),
                              ],
                            ),
                            if (review.strengths.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              const Text(
                                'Key Strengths:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                review.strengths,
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : AppColors.textSecondaryLight),
                              ),
                            ],
                            if (review.areasForImprovement.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Areas for Growth:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.cardOrange),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                review.areasForImprovement,
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : AppColors.textSecondaryLight),
                              ),
                            ],
                            if (review.generalFeedback.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'General Feedback:',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                review.generalFeedback,
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : AppColors.textSecondaryLight),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultSkills(bool isDark) {
    final defaultSkills = [
      {'name': 'Technical Proficiency', 'score': 4.5},
      {'name': 'Communication & Collaboration', 'score': 4.2},
      {'name': 'Initiative & Problem Solving', 'score': 4.6},
    ];

    return Column(
      children: defaultSkills.map((s) {
        final score = s['score'] as double;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    s['name'] as String,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimaryLight,
                    ),
                  ),
                  Text(
                    '${score.toStringAsFixed(1)} / 5.0',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: score / 5.0,
                  minHeight: 8,
                  backgroundColor: isDark ? const Color(0xFF2C3142) : const Color(0xFFF3F4F6),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
