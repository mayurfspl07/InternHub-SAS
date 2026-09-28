import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/app_state_provider.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/status_chip.dart';
import 'masters_repository.dart';
import 'models/masters_models.dart';
import 'widgets/access_restricted_view.dart';
import 'widgets/master_list_scaffold.dart';

class ProjectStatusesScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const ProjectStatusesScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<ProjectStatusesScreen> createState() => _ProjectStatusesScreenState();
}

class _ProjectStatusesScreenState extends ConsumerState<ProjectStatusesScreen> {
  final _repository = MastersRepository();
  List<ProjectStatus> _all = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  int _filter = 0; // All, In use, Unused

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
      final list = await _repository.getProjectStatuses();
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

  List<ProjectStatus> get _visible {
    final q = _search.trim().toLowerCase();
    return _all.where((s) {
      if (_filter == 1 && s.projectCount == 0) return false;
      if (_filter == 2 && s.projectCount > 0) return false;
      return q.isEmpty || s.name.toLowerCase().contains(q) || s.slug.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _reorder(int from, int to) async {
    final list = [..._all];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    setState(() => _all = list);
    try {
      await _repository.reorderProjectStatuses(list.map((s) => s.id).toList());
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't save the new order");
      await _load();
    }
  }

  Future<void> _openForm([ProjectStatus? status]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProjectStatusForm(status: status, nextOrder: _all.length + 1),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(status == null ? 'Status added' : 'Status updated')));
      _load();
    }
  }

  Future<void> _delete(ProjectStatus s) async {
    if (!await confirmMasterDelete(context, s.name, 'Projects can no longer be set to this status.')) return;
    try {
      await _repository.deleteProjectStatus(s.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${s.name}" deleted')));
      _load();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't delete it");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appStateProvider).currentUser;
    if (!canManageProjectStatuses(user)) {
      return Scaffold(
        appBar: pageAppBar(context, title: 'Project statuses'),
        body: const AccessRestrictedView(),
      );
    }

    final inUse = _all.where((s) => s.projectCount > 0).length;
    final totalProjects = _all.fold<int>(0, (sum, s) => sum + s.projectCount);

    return MasterListScaffold(
      title: 'Project statuses',
      subtitle: 'The stages a project moves through',
      itemNoun: 'status',
      addTooltip: 'New status',
      loading: _loading,
      error: _error,
      totalCount: _all.length,
      stats: [('in use', '$inUse'), (totalProjects == 1 ? 'project' : 'projects', '$totalProjects')],
      filterOptions: const ['All', 'In use', 'Unused'],
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
        for (final s in _visible)
          MasterRow(
            id: s.id,
            title: s.name,
            subtitle: plural(s.projectCount, 'project'),
            swatch: s.parsedColor,
            badges: [
              if (s.isDefault) const StatusChip(label: 'Default', statusType: StatusType.success),
              StatusChip(label: s.isSystem ? 'Built-in' : 'Custom', statusType: StatusType.neutral),
            ],
            deleteBlockedReason: s.isDefault
                ? 'The default status'
                : (s.projectCount > 0 ? 'Move its ${plural(s.projectCount, 'project')} first' : null),
          ),
      ],
    );
  }
}

class _ProjectStatusForm extends StatefulWidget {
  final ProjectStatus? status;
  final int nextOrder;

  const _ProjectStatusForm({this.status, required this.nextOrder});

  @override
  State<_ProjectStatusForm> createState() => _ProjectStatusFormState();
}

class _ProjectStatusFormState extends State<_ProjectStatusForm> {
  late final TextEditingController _name = TextEditingController(text: widget.status?.name ?? '');
  late final TextEditingController _color = TextEditingController(text: widget.status?.color ?? kStatusSwatches.first);
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
        await repo.createProjectStatus(
          name: name,
          slug: generateSlug(name),
          color: color!,
          orderIndex: widget.nextOrder,
          isDefault: _isDefault,
        );
      } else {
        await repo.updateProjectStatus(
          s.id,
          name: name,
          slug: s.slug,
          color: color!,
          orderIndex: s.orderIndex,
          isDefault: _isDefault,
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
      title: widget.status == null ? 'New project status' : 'Edit project status',
      error: _error,
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _name,
          autofocus: widget.status == null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _nameError = null),
          decoration: InputDecoration(labelText: 'Name', hintText: 'e.g. On hold', errorText: _nameError),
        ),
        const SizedBox(height: 16),
        HexColorField(controller: _color, error: _colorError, onChanged: () => setState(() => _colorError = null)),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Default for new projects'),
          value: _isDefault,
          onChanged: (v) => setState(() => _isDefault = v),
        ),
      ],
    );
  }
}
