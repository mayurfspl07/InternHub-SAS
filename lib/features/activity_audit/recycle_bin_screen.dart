import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/cohort_model.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/status_chip.dart';
import '../../core/constants/app_typography.dart';

class RecycleBinScreen extends ConsumerStatefulWidget {
  const RecycleBinScreen({super.key});

  @override
  ConsumerState<RecycleBinScreen> createState() => _RecycleBinScreenState();
}

class _RecycleBinScreenState extends ConsumerState<RecycleBinScreen> {
  /// Items with a restore or delete in flight; their buttons are disabled.
  final Set<String> _busy = {};
  bool _emptying = false;

  @override
  void initState() {
    super.initState();
    // Always show the current bin, not what was loaded at sign-in.
    Future.microtask(() => ref.read(appStateProvider.notifier).fetchRecycleBin());
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(String id, Future<void> Function() action, String success, String failure) async {
    setState(() => _busy.add(id));
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: failure);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _restore(RecycleBinItem item) => _run(
        item.id,
        () => ref.read(appStateProvider.notifier).restoreRecycleItem(item.id),
        '"${item.title}" restored',
        "Couldn't restore it",
      );

  Future<void> _deleteForever(RecycleBinItem item) async {
    if (!await _confirm(
      'Delete "${item.title}" forever?',
      "It can't be restored after this.",
      'Delete forever',
    )) {
      return;
    }
    await _run(
      item.id,
      () => ref.read(appStateProvider.notifier).permanentlyDeleteRecycleItem(item.id),
      '"${item.title}" deleted forever',
      "Couldn't delete it",
    );
  }

  Future<void> _emptyBin() async {
    final count = ref.read(appStateProvider).recycleBin.length;
    if (!await _confirm(
      'Empty the recycle bin?',
      '${plural(count, 'item')} will be deleted forever. This can\'t be undone.',
      'Empty bin',
    )) {
      return;
    }
    setState(() => _emptying = true);
    try {
      await ref.read(appStateProvider.notifier).clearRecycleBin();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recycle bin emptied')));
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't empty the bin");
    } finally {
      if (mounted) setState(() => _emptying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final items = state.recycleBin;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(
        context,
        title: 'Recycle bin',
        actions: [
          if (items.isNotEmpty)
            HeaderAction(
              icon: Icons.delete_sweep_rounded,
              color: AppColors.dangerInk,
              tooltip: 'Empty bin',
              onTap: _emptying ? () {} : _emptyBin,
            ),
        ],
      ),
      body: SafeArea(
        child: state.recycleBinLoading && items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.recycleBinError != null && items.isEmpty
                ? LoadErrorView(
                    title: "Couldn't load the recycle bin",
                    message: state.recycleBinError!,
                    onRetry: () => ref.read(appStateProvider.notifier).fetchRecycleBin(),
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.read(appStateProvider.notifier).fetchRecycleBin(),
                    child: items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                              const Icon(Icons.delete_outline_rounded, size: 56, color: AppColors.textTertiary),
                              const SizedBox(height: 14),
                              Text('The bin is empty', textAlign: TextAlign.center, style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Text(
                                'Deleted items stay here for a while before they are removed for good.',
                                textAlign: TextAlign.center,
                                style: AppTypography.caption,
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(AppSpacing.p20),
                            itemCount: items.length + 1,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Text(
                                  '${plural(items.length, 'item')} · restore anything you still need',
                                  style: AppTypography.caption,
                                );
                              }
                              final item = items[index - 1];
                              final busy = _busy.contains(item.id) || _emptying;
                              final days = item.daysRemaining;
                              final expiringSoon = days != null && days <= 3;
                              return Container(
                                padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: expiringSoon ? Border.all(color: AppColors.danger.withValues(alpha: 0.5)) : null,
                                  boxShadow: AppShadows.soft,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        StatusChip(label: humanize(item.entityType), statusType: StatusType.neutral),
                                        if (days != null)
                                          StatusChip(
                                            icon: Icons.schedule_rounded,
                                            label: days <= 0 ? 'Removed today' : '${plural(days, 'day')} left',
                                            statusType: expiringSoon ? StatusType.danger : StatusType.neutral,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        item.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.deletedByName.isNotEmpty
                                          ? 'Deleted by ${item.deletedByName} · ${formatDate(item.deletedAt)}'
                                          : 'Deleted ${formatDate(item.deletedAt)}',
                                      style: AppTypography.caption,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: busy ? null : () => _deleteForever(item),
                                          style: TextButton.styleFrom(foregroundColor: AppColors.dangerInk, minimumSize: const Size(0, 44)),
                                          icon: const Icon(Icons.delete_forever_rounded, size: 18),
                                          label: const Text('Delete forever'),
                                        ),
                                        const SizedBox(width: 4),
                                        FilledButton.tonalIcon(
                                          onPressed: busy ? null : () => _restore(item),
                                          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                                          icon: busy
                                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                              : const Icon(Icons.restore_from_trash_rounded, size: 18),
                                          label: const Text('Restore'),
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
}
