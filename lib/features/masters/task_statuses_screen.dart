import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/status_chip.dart';
import 'masters_repository.dart';
import 'models/masters_models.dart';
import 'widgets/access_restricted_view.dart';
import 'widgets/master_list_scaffold.dart';

/// The three board categories a task status can belong to.
const _categories = <(String, String)>[('todo', 'To do'), ('in_progress', 'In progress'), ('done', 'Done')];

/// Any legacy value ("completed", "doing", "testing"…) maps onto one of the three categories.
String normalizeTaskCategory(String raw) {
  final c = raw.toLowerCase().trim();
  if (c == 'done' || c == 'completed') return 'done';
  if (c == 'todo' || c == 'pending' || c == 'backlog') return 'todo';
  return 'in_progress';
}

class TaskStatusesScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const TaskStatusesScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<TaskStatusesScreen> createState() => _TaskStatusesScreenState();
}

class _TaskStatusesScreenState extends ConsumerState<TaskStatusesScreen> {
  final _repository = MastersRepository();
  List<TaskStatus> _all = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  int _filter = 0; // 0 = all, then one per category

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repository.getTaskStatuses();
      list.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      if (mounted) {
        setState(() {
          _all = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  List<TaskStatus> get _visible {
    final q = _search.trim().toLowerCase();
    return _all.where((s) {
      if (_filter > 0 && normalizeTaskCategory(s.statusCategory) != _categories[_filter - 1].$1) return false;
      return q.isEmpty || s.name.toLowerCase().contains(q) || s.slug.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _reorder(int from, int to) async {
    final list = [..._all];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    setState(() => _all = list);
    try {
      await _repository.reorderTaskStatuses(list.map((s) => s.id).toList());
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't save the new order");
      await _load();
    }
  }

  Future<void> _openForm([TaskStatus? status]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TaskStatusForm(status: status, nextOrder: _all.length + 1),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == null ? 'Status added' : 'Status updated')));
      _load();
    }
  }

  Future<void> _delete(TaskStatus s) async {
    if (!await confirmMasterDelete(context, s.name, "Tasks can't use it any more. A status that still has tasks can't be deleted.")) return;
    try {
      await _repository.deleteTaskStatus(s.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${s.name}" deleted')));
      _load();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't delete it");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appStateProvider).currentUser;
    if (!canManageTaskStatuses(user)) {
      return Scaffold(
        appBar: pageAppBar(context, title: 'Task statuses'),
        body: const AccessRestrictedView(),
      );
    }

    final visible = _visible;
    int count(String cat) => _all.where((s) => normalizeTaskCategory(s.statusCategory) == cat).length;

    return MasterListScaffold(
      title: 'Task statuses',
      subtitle: 'The columns on every project board',
      itemNoun: 'status',
      addTooltip: 'New status',
      loading: _loading,
      error: _error,
      totalCount: _all.length,
      stats: [for (final c in _categories) (c.$2.toLowerCase(), '${count(c.$1)}')],
      filterOptions: ['All', for (final c in _categories) c.$2],
      filterIndex: _filter,
      onFilterChanged: (i) => setState(() => _filter = i),
      searchQuery: _search,
      onSearchChanged: (v) => setState(() => _search = v),
      onRefresh: _load,
      onAdd: () => _openForm(),
      onEdit: (row) => _openForm(_all.firstWhere((s) => s.id == row.id)),
      onDelete: (row) => _delete(_all.firstWhere((s) => s.id == row.id)),
      onReorder: _reorder,
      rows: [
        for (final s in visible)
          MasterRow(
            id: s.id,
            title: s.name,
            subtitle: s.slug,
            swatch: s.parsedColor,
            badges: [
              StatusChip(label: _categories.firstWhere((c) => c.$1 == normalizeTaskCategory(s.statusCategory)).$2, statusType: StatusType.neutral),
              if (s.isDefault) const StatusChip(label: 'Default', statusType: StatusType.success),
            ],
            deleteBlockedReason: s.isDefault ? 'The default status' : null,
          ),
      ],
    );
  }
}

class _TaskStatusForm extends StatefulWidget {
  final TaskStatus? status;
  final int nextOrder;

  const _TaskStatusForm({this.status, required this.nextOrder});

  @override
  State<_TaskStatusForm> createState() => _TaskStatusFormState();
}

class _TaskStatusFormState extends State<_TaskStatusForm> {
  late final TextEditingController _name = TextEditingController(text: widget.status?.name ?? '');
  late final TextEditingController _color = TextEditingController(text: widget.status?.color ?? kStatusSwatches.first);
  late String _category = normalizeTaskCategory(widget.status?.statusCategory ?? 'in_progress');
  late bool _isDefault = widget.status?.isDefault ?? false;
  String? _nameError;
  String? _colorError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final color = normalizeHexColor(_color.text);
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : (name.length > 50 ? 'Use 50 characters or fewer' : null);
      _colorError = color == null ? 'Use a 6-digit hex code like #C8A24B' : null;
      _error = null;
    });
    if (_nameError != null || _colorError != null) return;
    setState(() => _saving = true);
    try {
      final repo = MastersRepository();
      final s = widget.status;
      if (s == null) {
        await repo.createTaskStatus(
          name: name,
          slug: generateSlug(name),
          color: color!,
          statusCategory: _category,
          isDefault: _isDefault,
          orderIndex: widget.nextOrder,
        );
      } else {
        await repo.updateTaskStatus(
          s.id,
          name: name,
          slug: s.slug,
          color: color!,
          statusCategory: _category,
          isDefault: _isDefault,
          orderIndex: s.orderIndex,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MasterFormDialog(
      title: widget.status == null ? 'New task status' : 'Edit task status',
      error: _error,
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: widget.status == null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _nameError = null),
          decoration: InputDecoration(labelText: 'Name', hintText: 'e.g. In review', errorText: _nameError),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Board group', helperText: 'Decides whether tasks here count as open or done'),
          items: [for (final c in _categories) DropdownMenuItem(value: c.$1, child: Text(c.$2))],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 16),
        HexColorField(controller: _color, error: _colorError, onChanged: () => setState(() => _colorError = null)),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Default for new tasks'),
          value: _isDefault,
          onChanged: (v) => setState(() => _isDefault = v),
        ),
      ],
    );
  }
}
