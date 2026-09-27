import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/load_error_view.dart';

class RecycleBinScreen extends ConsumerStatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  ConsumerState<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends ConsumerState<RecycleBinScreen> {
  @override
  void initState() {
    super.initState();
    // Always show the current bin, not what was loaded at sign-in.
    Future.microtask(() => ref.read(appStateProvider.notifier).fetchRecycleBin());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final items = state.recycleBin;

    return Scaffold(
      appBar: pageAppBar(
        context,
        title: 'Recycle Bin',
        actions: [
          HeaderAction(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: () => ref.read(appStateProvider.notifier).fetchRecycleBin(),
          ),
          if (items.isNotEmpty)
            HeaderAction(
              icon: Icons.delete_sweep_rounded,
              color: AppColors.danger,
              tooltip: 'Empty Recycle Bin',
              onTap: () => _confirmClearAll(context, ref),
            ),
        ],
      ),
      body: SafeArea(
        child: state.recycleBinLoading && items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.recycleBinError != null && items.isEmpty
            ? LoadErrorView(
                title: 'Couldn\'t load the recycle bin',
                message: state.recycleBinError!,
                onRetry: () => ref.read(appStateProvider.notifier).fetchRecycleBin(),
              )
            : RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchRecycleBin(),
          child: items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.28),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 64, color: AppColors.textSecondary),
                          const SizedBox(height: 16),
                          Text(
                            'Recycle bin is empty',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Deleted records appear here until they expire.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.p20),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final deletedDate = DateFormat('MMM d, yyyy').format(item.deletedAt);

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: AppShadows.soft,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerSoft,
                                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                ),
                                child: Text(
                                  item.entityType.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.dangerInk,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (item.daysRemaining != null)
                                Text(
                                  item.daysRemaining == 1 ? '1 day left' : '${item.daysRemaining} days left',
                                  style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w600),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.deletedByName.isNotEmpty ? 'Deleted by ${item.deletedByName} on $deletedDate' : 'Deleted on $deletedDate',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          Wrap(
                            alignment: WrapAlignment.end,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  try {
                                    await ref.read(appStateProvider.notifier).restoreRecycleItem(item.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Item restored successfully!')),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Restore failed: $e')),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.restore_from_trash_rounded, size: 18, color: AppColors.primaryInk),
                                label: const Text('Restore'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  try {
                                    await ref.read(appStateProvider.notifier).permanentlyDeleteRecycleItem(item.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Item permanently purged.')),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Purge failed: $e')),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.delete_forever_rounded, size: 18, color: AppColors.danger),
                                label: const Text('Purge', style: TextStyle(color: AppColors.danger)),
                              ),
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

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Recycle Bin'),
        content: const Text(
          'Are you sure you want to permanently delete all items in the Recycle Bin? This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(appStateProvider.notifier).clearRecycleBin();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Recycle bin cleared.')),
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
            child: const Text('Clear All', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
