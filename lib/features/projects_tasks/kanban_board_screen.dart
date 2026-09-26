import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/avatar_stack.dart';
import 'task_detail_screen.dart';
import 'create_task_bottom_sheet.dart';

class KanbanBoardScreen extends ConsumerStatefulWidget {
  const KanbanBoardScreen({super.key});

  @override
  ConsumerState<KanbanBoardScreen> createState() => _KanbanBoardScreenState();
}

class _KanbanBoardScreenState extends ConsumerState<KanbanBoardScreen> {
  KanbanStatus _activeColumn = KanbanStatus.inProgress;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final tasks = state.tasks;

    final columnTasks = tasks.where((t) => t.status == _activeColumn).toList();

    return Column(
      children: [
        // Column Selector Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
          child: Row(
            children: [
              _buildColumnPill(KanbanStatus.todo, 'To Do', tasks),
              const SizedBox(width: 8),
              _buildColumnPill(KanbanStatus.inProgress, 'In Progress', tasks),
              const SizedBox(width: 8),
              _buildColumnPill(KanbanStatus.inReview, 'In Review', tasks),
              const SizedBox(width: 8),
              _buildColumnPill(KanbanStatus.completed, 'Completed', tasks),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Task Cards in active Kanban Column
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => ref.read(appStateProvider.notifier).fetchTasks(),
            child: columnTasks.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.task_alt_rounded, size: 54, color: AppColors.textSecondary),
                            const SizedBox(height: 12),
                            Text(
                              'No tasks in ${_activeColumn.name.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const CreateTaskBottomSheet(),
                                );
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('New Task'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(left: 20, right: 20, bottom: 120, top: 4),
                    itemCount: columnTasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final task = columnTasks[index];
                      return _buildKanbanCard(task);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnPill(KanbanStatus status, String title, List<TaskModel> allTasks) {
    final isSelected = _activeColumn == status;
    final count = allTasks.where((t) => t.status == status).length;

    return GestureDetector(
      onTap: () => setState(() => _activeColumn = status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.surface : AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppColors.ink : AppColors.primaryInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKanbanCard(TaskModel task) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TaskDetailScreen(task: task)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatusChip.fromPriority(task.priority),
                PopupMenuButton<KanbanStatus>(
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  onSelected: (newStatus) {
                    ref.read(appStateProvider.notifier).updateTaskStatus(task.id, newStatus);
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: KanbanStatus.todo,
                      child: Text('Move to To Do'),
                    ),
                    const PopupMenuItem(
                      value: KanbanStatus.inProgress,
                      child: Text('Move to In Progress'),
                    ),
                    const PopupMenuItem(
                      value: KanbanStatus.inReview,
                      child: Text('Move to In Review'),
                    ),
                    const PopupMenuItem(
                      value: KanbanStatus.completed,
                      child: Text('Move to Completed'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            Text(
              task.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              task.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Checklist & Assignees footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (task.checklist.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.primaryInk),
                      const SizedBox(width: 4),
                      Text(
                        '${task.checklist.where((c) => c.isCompleted).length}/${task.checklist.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                else
                  const SizedBox.shrink(),
                if (task.assigneeAvatars.isNotEmpty)
                  AvatarStack(avatarUrls: task.assigneeAvatars, size: 28),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
