import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../shared/widgets/page_header.dart';
import '../../../shared/widgets/reference_components.dart';

/// One row in a master-data list.
class MasterRow {
  final int id;
  final String title;
  final String? subtitle;
  final Color? swatch;
  final IconData? icon;
  final List<Widget> badges;

  /// Why the row can't be deleted, or null when it can.
  final String? deleteBlockedReason;

  const MasterRow({
    required this.id,
    required this.title,
    this.subtitle,
    this.swatch,
    this.icon,
    this.badges = const [],
    this.deleteBlockedReason,
  });
}

/// Card list shared by task statuses, project statuses and internship durations:
/// search, a count, optional compact stats and filter pills, and cards with an actions
/// menu. Up/down reordering is offered only when the full, unfiltered list is shown.
class MasterListScaffold extends StatefulWidget {
  final String title;
  final String subtitle;
  final String itemNoun; // singular, e.g. "status"
  final String addTooltip;
  final bool loading;
  final String? error;
  final List<MasterRow> rows;
  final int totalCount;
  final List<(String, String)> stats;
  final List<String> filterOptions;
  final int filterIndex;
  final ValueChanged<int>? onFilterChanged;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd;
  final ValueChanged<MasterRow> onEdit;
  final ValueChanged<MasterRow> onDelete;

  /// Moves the row at [from] to [to] in the full list; null when the API has no reorder.
  final Future<void> Function(int from, int to)? onReorder;

  const MasterListScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.itemNoun,
    required this.addTooltip,
    required this.loading,
    required this.error,
    required this.rows,
    required this.totalCount,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.stats = const [],
    this.filterOptions = const [],
    this.filterIndex = 0,
    this.onFilterChanged,
    this.onReorder,
  });

  @override
  State<MasterListScaffold> createState() => _MasterListScaffoldState();
}

class _MasterListScaffoldState extends State<MasterListScaffold> {
  late final TextEditingController _search = TextEditingController(text: widget.searchQuery);
  bool _reordering = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _filtered => widget.searchQuery.trim().isNotEmpty || widget.filterIndex != 0;

  Future<void> _move(int from, int to) async {
    if (_reordering) return;
    setState(() => _reordering = true);
    try {
      await widget.onReorder!(from, to);
    } finally {
      if (mounted) setState(() => _reordering = false);
    }
  }

  String _countLabel() {
    final n = widget.rows.length;
    final noun = widget.itemNoun;
    String p(int c) => '$c ${c == 1 ? noun : '${noun}s'}';
    return _filtered ? 'Showing ${p(n)} of ${widget.totalCount}' : p(widget.totalCount);
  }

  @override
  Widget build(BuildContext context) {
    final canReorder = widget.onReorder != null && !_filtered;

    Widget body;
    if (widget.loading && widget.totalCount == 0) {
      body = const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()));
    } else if (widget.error != null && widget.totalCount == 0) {
      body = SliverFillRemaining(
        hasScrollBody: false,
        child: LoadErrorView(message: widget.error!, onRetry: widget.onRefresh),
      );
    } else if (widget.rows.isEmpty) {
      body = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 32),
          child: Column(
            children: [
              const Icon(Icons.inbox_outlined, size: 48, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              Text(
                _filtered ? 'Nothing matches' : 'No ${widget.itemNoun}s yet',
                style: AppTypography.section.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                _filtered ? 'Try another search or filter.' : 'Tap + to add the first one.',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      );
    } else {
      body = SliverPadding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 0, AppSpacing.p20, 24),
        sliver: SliverList.separated(
          itemCount: widget.rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _card(widget.rows[i], i, canReorder),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PageHeader(
                        title: widget.title,
                        subtitle: widget.subtitle,
                        showBack: Navigator.canPop(context),
                        padding: EdgeInsets.zero,
                        actions: [HeaderAction(icon: Icons.add_rounded, tooltip: widget.addTooltip, onTap: widget.onAdd)],
                      ),
                      if (widget.stats.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in widget.stats)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: AppShadows.soft,
                                ),
                                child: Text.rich(
                                  TextSpan(children: [
                                    TextSpan(text: '${s.$2} ', style: AppTypography.bodyStrong),
                                    TextSpan(text: s.$1, style: AppTypography.caption),
                                  ]),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        controller: _search,
                        onChanged: (v) {
                          setState(() {});
                          widget.onSearchChanged(v);
                        },
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search ${widget.itemNoun}s',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _search.text.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() {});
                                    widget.onSearchChanged('');
                                  },
                                )
                              : null,
                        ),
                      ),
                      if (widget.filterOptions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        PillFilter(
                          options: widget.filterOptions,
                          selectedIndex: widget.filterIndex,
                          onSelected: (i) => widget.onFilterChanged?.call(i),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        widget.onReorder != null && _filtered
                            ? '${_countLabel()} · clear search and filters to reorder'
                            : _countLabel(),
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.loading && widget.totalCount > 0) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(MasterRow row, int index, bool canReorder) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          if (row.swatch != null)
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(color: row.swatch, shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
            )
          else if (row.icon != null)
            Icon(row.icon, size: 20, color: AppColors.primaryInk),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                if (row.subtitle != null && row.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(row.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption),
                ],
                if (row.badges.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: row.badges),
                ],
              ],
            ),
          ),
          if (canReorder) ...[
            IconButton(
              tooltip: 'Move up',
              visualDensity: VisualDensity.compact,
              onPressed: index == 0 || _reordering ? null : () => _move(index, index - 1),
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            ),
            IconButton(
              tooltip: 'Move down',
              visualDensity: VisualDensity.compact,
              onPressed: index == widget.rows.length - 1 || _reordering ? null : () => _move(index, index + 1),
              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
            ),
          ],
          PopupMenuButton<String>(
            tooltip: 'Actions for ${row.title}',
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
            onSelected: (v) => v == 'edit' ? widget.onEdit(row) : widget.onDelete(row),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'), contentPadding: EdgeInsets.zero),
              ),
              PopupMenuItem(
                value: 'delete',
                enabled: row.deleteBlockedReason == null,
                child: ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: row.deleteBlockedReason == null ? AppColors.dangerInk : AppColors.textTertiary),
                  title: Text('Delete', style: TextStyle(color: row.deleteBlockedReason == null ? AppColors.dangerInk : AppColors.textTertiary)),
                  subtitle: row.deleteBlockedReason == null ? null : Text(row.deleteBlockedReason!, style: AppTypography.label),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Validates "#RRGGBB" (or "RRGGBB"); returns the normalized "#RRGGBB" or null.
String? normalizeHexColor(String input) {
  final hex = input.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return '#${hex.toUpperCase()}';
}

/// Swatches offered in the status forms (journal palette plus common status colors).
const kStatusSwatches = [
  '#C8A24B', '#8A7A5C', '#6F8F5E', '#4F7A9A', '#8C6BB1', '#C0664F', '#B38F2F', '#6B6B6B',
];

/// Colour field with swatches and a hex input; shows its own error.
class HexColorField extends StatelessWidget {
  final TextEditingController controller;
  final String? error;
  final VoidCallback onChanged;

  const HexColorField({super.key, required this.controller, required this.error, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final current = normalizeHexColor(controller.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Colour', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in kStatusSwatches)
              Semantics(
                button: true,
                selected: current == hex,
                label: 'Colour $hex',
                child: InkResponse(
                  radius: 22,
                  onTap: () {
                    controller.text = hex;
                    onChanged();
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                      shape: BoxShape.circle,
                      border: Border.all(color: current == hex ? AppColors.ink : AppColors.border, width: current == hex ? 2.5 : 1),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          autocorrect: false,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: 'Hex code',
            hintText: '#C8A24B',
            errorText: error,
            prefixIcon: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: current == null ? AppColors.surfaceMuted : Color(int.parse('FF${current.substring(1)}', radix: 16)),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standard form dialog frame used by the master screens: title, close, scrollable
/// body, inline error and Cancel/Save.
class MasterFormDialog extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? error;
  final bool saving;
  final String saveLabel;
  final VoidCallback onSave;

  const MasterFormDialog({
    super.key,
    required this.title,
    required this.children,
    required this.error,
    required this.saving,
    required this.onSave,
    this.saveLabel = 'Save',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: AppTypography.section.copyWith(fontWeight: FontWeight.w700))),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...children,
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: saving ? null : onSave,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(96, 44)),
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(saveLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirms a delete; returns true when the user agrees.
Future<bool> confirmMasterDelete(BuildContext context, String name, String note) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "$name"?'),
      content: Text(note),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}
