import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/standup_model.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import 'standup_feed_screen.dart';

class StandupScreen extends ConsumerStatefulWidget {
  const StandupScreen({super.key});

  @override
  ConsumerState<StandupScreen> createState() => _StandupScreenState();
}

class _StandupScreenState extends ConsumerState<StandupScreen> {
  late TextEditingController _yesterdayController;
  late TextEditingController _todayController;
  late TextEditingController _blockersController;
  StandupMood _selectedMood = StandupMood.productive;
  bool _isLoading = false;

  final List<Map<String, dynamic>> _moodOptions = [
    {'mood': StandupMood.crushingIt, 'emoji': '🔥', 'label': 'Crushing It'},
    {'mood': StandupMood.productive, 'emoji': '😊', 'label': 'Productive'},
    {'mood': StandupMood.neutral, 'emoji': '😐', 'label': 'Neutral'},
    {'mood': StandupMood.blocked, 'emoji': '😫', 'label': 'Blocked'},
    {'mood': StandupMood.exhausted, 'emoji': '😴', 'label': 'Exhausted'},
  ];

  @override
  void initState() {
    super.initState();
    final today = ref.read(appStateProvider).todayStandup;
    _yesterdayController = TextEditingController(text: today?.yesterdayWork ?? '');
    _todayController = TextEditingController(text: today?.todayPlan ?? '');
    _blockersController = TextEditingController(text: today?.blockers ?? '');
    if (today != null) {
      _selectedMood = today.mood;
    }
  }

  @override
  void dispose() {
    _yesterdayController.dispose();
    _todayController.dispose();
    _blockersController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_yesterdayController.text.trim().isEmpty || _todayController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please share what you did and your plan for today.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(appStateProvider.notifier).submitStandup(
            did: _yesterdayController.text.trim(),
            plan: _todayController.text.trim(),
            blockers: _blockersController.text.trim(),
            mood: _selectedMood,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Standup Posted Successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StandupFeedScreen()),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUpdate = state.todayStandup != null;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Daily Standup 📝', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StandupFeedScreen()),
              );
            },
            child: const Text('Team Feed', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.p20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How are you feeling today?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 12),

              // 5 Mood Emoji Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _moodOptions.map((item) {
                  final isSelected = _selectedMood == item['mood'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedMood = item['mood']),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : (isDark ? AppColors.surfaceDark : Colors.white),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : (isDark ? AppColors.borderDark : AppColors.borderLight),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(item['emoji'], style: const TextStyle(fontSize: 24)),
                          const SizedBox(height: 4),
                          Text(
                            item['label'],
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? AppColors.primary : (isDark ? Colors.white60 : Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              CustomTextField(
                label: 'What did you accomplish yesterday / recently?',
                hintText: 'e.g. Completed API integration, resolved 3 tickets...',
                controller: _yesterdayController,
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              CustomTextField(
                label: 'What are you planning to work on today?',
                hintText: 'e.g. Implement camera preview, conduct test walkthrough...',
                controller: _todayController,
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              CustomTextField(
                label: 'Any blockers or challenges?',
                hintText: 'Mention dependencies, permissions, or questions...',
                controller: _blockersController,
                maxLines: 2,
              ),
              const SizedBox(height: 28),

              CustomButton(
                text: isUpdate ? 'Update Standup' : 'Submit Standup',
                isLoading: _isLoading,
                onPressed: _handleSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
