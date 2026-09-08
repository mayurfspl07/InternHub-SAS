import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/cohort_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/avatar_stack.dart';

class CohortManagementScreen extends ConsumerWidget {
  const CohortManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cohorts = state.cohorts;
    final isAdmin = state.currentUser.role == UserRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cohorts & Batches 🏛️', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(appStateProvider.notifier).fetchCohorts(),
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              tooltip: 'New Cohort',
              onPressed: () => _showCohortDialog(context, ref),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchCohorts(),
          child: cohorts.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.diversity_3_outlined, size: 64, color: isDark ? Colors.white38 : AppColors.textSecondaryLight),
                          const SizedBox(height: 16),
                          Text(
                            'No cohorts found',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create a cohort batch to group your interns.',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                            ),
                          ),
                          if (isAdmin) ...[
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () => _showCohortDialog(context, ref),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Create Cohort'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.p20),
                  itemCount: cohorts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final cohort = cohorts[index];
                    final startStr = DateFormat('MMM yyyy').format(cohort.startDate);
                    final endStr = DateFormat('MMM yyyy').format(cohort.endDate);

                    return Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: index == 0 ? AppColors.cardPurple : (isDark ? AppColors.surfaceDark : Colors.white),
                        borderRadius: BorderRadius.circular(28),
                        border: index != 0
                            ? Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight)
                            : null,
                        boxShadow: index == 0
                            ? [
                                BoxShadow(
                                  color: AppColors.cardPurple.withValues(alpha: 0.3),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: index == 0 ? Colors.white24 : AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                ),
                                child: Text(
                                  cohort.batchSeason,
                                  style: TextStyle(
                                    color: index == 0 ? Colors.white : AppColors.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  Text(
                                    '$startStr - $endStr',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: index == 0 ? Colors.white70 : (isDark ? Colors.white60 : Colors.black54),
                                    ),
                                  ),
                                  if (isAdmin) ...[
                                    const SizedBox(width: 6),
                                    PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert,
                                        size: 18,
                                        color: index == 0 ? Colors.white70 : (isDark ? Colors.white60 : Colors.black54),
                                      ),
                                      onSelected: (val) {
                                        if (val == 'edit') {
                                          _showCohortDialog(context, ref, cohort: cohort);
                                        } else if (val == 'delete') {
                                          _confirmDelete(context, ref, cohort.id);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'edit', child: Text('Edit Cohort')),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete Cohort', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Text(
                            cohort.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: index == 0 ? Colors.white : (isDark ? Colors.white : AppColors.textPrimaryLight),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Lead Mentor: ${cohort.leadMentorName}',
                            style: TextStyle(
                              fontSize: 13,
                              color: index == 0 ? Colors.white70 : (isDark ? Colors.white60 : AppColors.textSecondaryLight),
                            ),
                          ),
                          const SizedBox(height: 20),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${cohort.totalInterns} Interns Enrolled',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: index == 0 ? Colors.white : (isDark ? Colors.white : AppColors.textPrimaryLight),
                                    ),
                                  ),
                                  Text(
                                    '⭐ ${cohort.averagePerformance} Avg Rating • ⏱️ ${cohort.averageAttendanceRate}% Attendance',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: index == 0 ? Colors.white70 : (isDark ? Colors.white60 : AppColors.textSecondaryLight),
                                    ),
                                  ),
                                ],
                              ),
                              if (cohort.internAvatars.isNotEmpty)
                                AvatarStack(avatarUrls: cohort.internAvatars, size: 32),
                            ],
                          ),
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
        title: const Text('Delete Cohort'),
        content: const Text('Are you sure you want to delete this cohort batch?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(appStateProvider.notifier).deleteCohort(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cohort deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
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

  void _showCohortDialog(BuildContext context, WidgetRef ref, {CohortModel? cohort}) {
    final nameCtrl = TextEditingController(text: cohort?.name ?? '');
    final seasonCtrl = TextEditingController(text: cohort?.batchSeason ?? 'Summer 2026');
    final isEdit = cohort != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Cohort' : 'Create Cohort'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Cohort Name *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: seasonCtrl,
              decoration: const InputDecoration(labelText: 'Batch Season (e.g. Summer 2026)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);

              final body = {
                'name': name,
                'batch_season': seasonCtrl.text.trim(),
                'start_date': (cohort?.startDate ?? DateTime.now()).toIso8601String().substring(0, 10),
                'end_date': (cohort?.endDate ?? DateTime.now().add(const Duration(days: 90))).toIso8601String().substring(0, 10),
              };

              try {
                if (isEdit) {
                  await ref.read(appStateProvider.notifier).updateCohort(cohort.id, body);
                } else {
                  await ref.read(appStateProvider.notifier).createCohort(body);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isEdit ? 'Cohort updated' : 'Cohort created successfully')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e')),
                  );
                }
              }
            },
            child: Text(isEdit ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }
}
