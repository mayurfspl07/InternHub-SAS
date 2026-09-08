import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/standup_model.dart';
import '../../shared/models/user_model.dart';
import 'standup_screen.dart';

class StandupFeedScreen extends ConsumerWidget {
  const StandupFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final standups = state.standups;
    final currentUser = state.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Standup Feed 💬', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(appStateProvider.notifier).fetchStandup(),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StandupScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchStandup(),
          child: standups.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.forum_outlined, size: 64, color: isDark ? Colors.white38 : AppColors.textSecondaryLight),
                          const SizedBox(height: 16),
                          Text(
                            'No standups yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Be the first to share your daily update!',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const StandupScreen()),
                              );
                            },
                            icon: const Icon(Icons.edit_note_rounded),
                            label: const Text('Submit Standup'),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.p20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: standups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final standup = standups[index];
                    final dateStr = DateFormat('MMM d, hh:mm a').format(standup.date);
                    final canDelete = currentUser.id == standup.userId ||
                        currentUser.role == UserRole.admin ||
                        currentUser.role == UserRole.mentor;

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
                          // Author Header & Mood
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                                      backgroundImage: standup.userAvatar.isNotEmpty ? NetworkImage(standup.userAvatar) : null,
                                      child: standup.userAvatar.isEmpty
                                          ? Text(
                                              standup.userName.isNotEmpty ? standup.userName[0].toUpperCase() : 'U',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            standup.userName,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            dateStr,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                    ),
                                    child: Text(
                                      _getMoodEmoji(standup.mood),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                                    ),
                                  ),
                                  if (canDelete) ...[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _confirmDelete(context, ref, standup.id),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          _buildAnswerBlock('Yesterday', standup.yesterdayWork, isDark),
                          const SizedBox(height: 10),
                          _buildAnswerBlock('Today', standup.todayPlan, isDark),
                          if (standup.blockers.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildAnswerBlock('Blockers', standup.blockers, isDark),
                          ],

                          if (standup.mentorFeedback.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF242A38) : const Color(0xFFEFF2FE),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('🧑‍🏫', style: TextStyle(fontSize: 16)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Feedback: ${standup.mentorFeedback.first}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Standup'),
        content: const Text('Are you sure you want to delete this standup entry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(appStateProvider.notifier).deleteStandup(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Standup deleted successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to delete: $e')),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _getMoodEmoji(StandupMood mood) {
    switch (mood) {
      case StandupMood.crushingIt:
        return '🔥 Crushing It';
      case StandupMood.productive:
        return '😊 Productive';
      case StandupMood.neutral:
        return '😐 Neutral';
      case StandupMood.blocked:
        return '😫 Blocked';
      case StandupMood.exhausted:
        return '😴 Exhausted';
    }
  }

  Widget _buildAnswerBlock(String title, String content, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          content,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
          ),
        ),
      ],
    );
  }
}
