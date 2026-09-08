import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/assignment_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/status_chip.dart';

class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() => _isLoading = true);
    await ref.read(appStateProvider.notifier).fetchAssignments();
    if (mounted) setState(() => _isLoading = false);
  }

  void _showSubmitDialog(AssignmentModel assignment) {
    final textController = TextEditingController();
    final githubController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Submit: ${assignment.title}',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Solution Summary / Notes',
                  hintText: 'Describe what you accomplished...',
                  controller: textController,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  label: 'GitHub / Demo URL (Optional)',
                  hintText: 'https://github.com/...',
                  prefixIcon: Icons.link_rounded,
                  controller: githubController,
                ),
                const SizedBox(height: 20),
                CustomButton(
                  text: 'Submit Solution',
                  isLoading: isSubmitting,
                  onPressed: () async {
                    if (textController.text.trim().isEmpty && githubController.text.trim().isEmpty) {
                      return;
                    }
                    setModalState(() => isSubmitting = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final nav = Navigator.of(ctx);
                      try {
                        await ApiClient().post('/api/assignments/${assignment.id}/submit', body: {
                          'submission_text': textController.text.trim(),
                          'github_url': githubController.text.trim(),
                        });
                        nav.pop();
                      if (mounted) {
                        _loadAssignments();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Assignment submitted successfully!'), backgroundColor: AppColors.success),
                        );
                      }
                    } catch (_) {
                      setModalState(() => isSubmitting = false);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCreateAssignmentDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    bool isCreating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Create New Assignment',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Assignment Title',
                  hintText: 'e.g. Build REST API Integration',
                  controller: titleController,
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  label: 'Instructions & Requirements',
                  hintText: 'Detailed requirements for interns...',
                  controller: descController,
                  maxLines: 4,
                ),
                const SizedBox(height: 20),
                CustomButton(
                  text: 'Create Assignment',
                  isLoading: isCreating,
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) return;
                    setModalState(() => isCreating = true);
                    final nav = Navigator.of(ctx);
                    try {
                      await ApiClient().post('/api/assignments', body: {
                        'title': titleController.text.trim(),
                        'description': descController.text.trim(),
                        'due_date': DateTime.now().add(const Duration(days: 7)).toIso8601String().substring(0, 10),
                      });
                      nav.pop();
                      if (mounted) {
                        _loadAssignments();
                      }
                    } catch (_) {
                      setModalState(() => isCreating = false);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isManager = state.currentUser.role == UserRole.admin || state.currentUser.role == UserRole.mentor;
    final assignments = state.assignments;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Intern Assignments',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          if (isManager)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
              onPressed: _showCreateAssignmentDialog,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAssignments,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : assignments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.assignment_turned_in_outlined, size: 56, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('No assignments found', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          isManager ? 'Tap + to publish an assignment for your interns.' : 'You have no pending assignments right now.',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: assignments.length,
                    itemBuilder: (context, i) {
                      final a = assignments[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    a.title,
                                    style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                StatusChip(
                                  label: a.status.toUpperCase(),
                                  statusType: a.status == 'active' ? StatusType.success : StatusType.neutral,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              a.description,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (a.dueDate != null)
                                  Row(
                                    children: [
                                      const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Due: ${a.dueDate!.toIso8601String().substring(0, 10)}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                if (!isManager)
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    ),
                                    onPressed: () => _showSubmitDialog(a),
                                    child: const Text('Submit Solution', style: TextStyle(fontSize: 12)),
                                  )
                                else
                                  Text(
                                    '${a.submissions.length} Submissions',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
