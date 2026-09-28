import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/app_state_provider.dart';
import '../../core/utils/formatters.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/status_chip.dart';
import 'masters_repository.dart';
import 'models/masters_models.dart';
import 'widgets/access_restricted_view.dart';
import 'widgets/master_list_scaffold.dart';

class InternshipDurationsScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const InternshipDurationsScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<InternshipDurationsScreen> createState() => _InternshipDurationsScreenState();
}

class _InternshipDurationsScreenState extends ConsumerState<InternshipDurationsScreen> {
  final _repository = MastersRepository();
  List<InternshipDuration> _all = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  int _filter = 0; // All, Active, Inactive

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
      final list = await _repository.getInternshipDurations();
      // There's no reorder endpoint, so the list is ordered by length.
      list.sort((a, b) => a.durationDays.compareTo(b.durationDays));
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

  List<InternshipDuration> get _visible {
    final q = _search.trim().toLowerCase();
    return _all.where((d) {
      if (_filter == 1 && !d.isActive) return false;
      if (_filter == 2 && d.isActive) return false;
      return q.isEmpty || d.title.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openForm([InternshipDuration? duration]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DurationForm(duration: duration),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(duration == null ? 'Duration added' : 'Duration updated')));
      _load();
    }
  }

  Future<void> _delete(InternshipDuration d) async {
    if (!await confirmMasterDelete(context, d.title, "New interns can't be given this duration any more.")) return;
    try {
      await _repository.deleteInternshipDuration(d.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"${d.title}" deleted')));
      _load();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't delete it");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appStateProvider).currentUser;
    if (!canManageInternshipDurations(user)) {
      return Scaffold(
        appBar: pageAppBar(context, title: 'Internship durations'),
        body: const AccessRestrictedView(),
      );
    }

    final active = _all.where((d) => d.isActive).length;
    final interns = _all.fold<int>(0, (sum, d) => sum + d.internCount);

    return MasterListScaffold(
      title: 'Internship durations',
      subtitle: 'Lengths you can give an internship',
      itemNoun: 'duration',
      addTooltip: 'New duration',
      loading: _loading,
      error: _error,
      totalCount: _all.length,
      stats: [('active', '$active'), (interns == 1 ? 'intern' : 'interns', '$interns')],
      filterOptions: const ['All', 'Active', 'Inactive'],
      filterIndex: _filter,
      onFilterChanged: (i) => setState(() => _filter = i),
      searchQuery: _search,
      onSearchChanged: (v) => setState(() => _search = v),
      onRefresh: _load,
      onAdd: () => _openForm(),
      onEdit: (row) => _openForm(_all.firstWhere((d) => d.id == row.id)),
      onDelete: (row) => _delete(_all.firstWhere((d) => d.id == row.id)),
      rows: [
        for (final d in _visible)
          MasterRow(
            id: d.id,
            title: d.title,
            subtitle: '${plural(d.durationMonths, 'month')} · ${plural(d.durationDays, 'day')} · ${plural(d.leaves, 'leave day')}',
            icon: Icons.schedule_rounded,
            badges: [
              if (d.isDefault) const StatusChip(label: 'Default', statusType: StatusType.success),
              StatusChip(label: d.isActive ? 'Active' : 'Inactive', statusType: d.isActive ? StatusType.info : StatusType.neutral),
              if (d.internCount > 0) StatusChip(label: plural(d.internCount, 'intern'), statusType: StatusType.neutral),
            ],
            deleteBlockedReason: d.isDefault
                ? 'The default duration'
                : (d.internCount > 0 ? 'Used by ${plural(d.internCount, 'intern')}' : null),
          ),
      ],
    );
  }
}

class _DurationForm extends StatefulWidget {
  final InternshipDuration? duration;

  const _DurationForm({this.duration});

  @override
  State<_DurationForm> createState() => _DurationFormState();
}

class _DurationFormState extends State<_DurationForm> {
  late final TextEditingController _title = TextEditingController(text: widget.duration?.title ?? '');
  late final TextEditingController _months = TextEditingController(text: '${widget.duration?.durationMonths ?? 3}');
  late final TextEditingController _days = TextEditingController(text: '${widget.duration?.durationDays ?? 90}');
  late final TextEditingController _leaves = TextEditingController(text: '${widget.duration?.leaves ?? 0}');
  late bool _isDefault = widget.duration?.isDefault ?? false;
  late bool _isActive = widget.duration?.isActive ?? true;
  // Days follow months (30 per month) until the admin types their own number.
  late bool _daysEdited = widget.duration != null;
  final Map<String, String?> _errors = {};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_title, _months, _days, _leaves]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final months = int.tryParse(_months.text.trim());
    final days = int.tryParse(_days.text.trim());
    final leaves = int.tryParse(_leaves.text.trim());
    setState(() {
      _errors
        ..clear()
        ..['title'] = title.isEmpty ? 'Enter a name' : null
        ..['months'] = (months == null || months < 1 || months > 36) ? 'Enter 1 to 36 months' : null
        ..['days'] = (days == null || days < 1 || days > 1100) ? 'Enter the number of days' : null
        ..['leaves'] = (leaves == null || leaves < 0 || (days != null && leaves > days)) ? 'Enter 0 up to the number of days' : null;
      _error = null;
    });
    if (_errors.values.any((e) => e != null)) return;
    setState(() => _saving = true);
    try {
      final repo = MastersRepository();
      final d = widget.duration;
      if (d == null) {
        await repo.createInternshipDuration(
          title: title,
          durationMonths: months!,
          durationDays: days!,
          leaves: leaves!,
          isDefault: _isDefault,
          isActive: _isActive,
        );
      } else {
        await repo.updateInternshipDuration(
          d.id,
          title: title,
          durationMonths: months!,
          durationDays: days!,
          leaves: leaves!,
          isDefault: _isDefault,
          isActive: _isActive,
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

  Widget _number(String key, String label, TextEditingController c, {String? suffix, ValueChanged<String>? onChanged}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
      onChanged: (v) {
        setState(() => _errors[key] = null);
        onChanged?.call(v);
      },
      decoration: InputDecoration(labelText: label, suffixText: suffix, errorText: _errors[key]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MasterFormDialog(
      title: widget.duration == null ? 'New duration' : 'Edit duration',
      error: _error,
      saving: _saving,
      onSave: _save,
      children: [
        TextField(
          controller: _title,
          autofocus: widget.duration == null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() => _errors['title'] = null),
          decoration: InputDecoration(labelText: 'Name', hintText: 'e.g. Summer internship', errorText: _errors['title']),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _number('months', 'Months', _months, onChanged: (v) {
                final m = int.tryParse(v);
                if (!_daysEdited && m != null) _days.text = '${m * 30}';
              }),
            ),
            const SizedBox(width: 12),
            Expanded(child: _number('days', 'Days', _days, onChanged: (_) => _daysEdited = true)),
          ],
        ),
        if ((widget.duration?.internCount ?? 0) > 0) ...[
          const SizedBox(height: 8),
          Text(
            '${plural(widget.duration!.internCount, 'intern')} on this duration follow any change to its length and leave days.',
            style: AppTypography.caption,
          ),
        ],
        const SizedBox(height: 16),
        _number('leaves', 'Leave days allowed', _leaves, suffix: 'days'),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: Text(
            (widget.duration?.internCount ?? 0) > 0
                ? "Can't be turned off while interns are on it"
                : "Inactive durations can't be picked for new interns",
          ),
          value: _isActive,
          // The server refuses to turn off a duration interns are on.
          onChanged: (widget.duration?.internCount ?? 0) > 0 && _isActive ? null : (v) => setState(() => _isActive = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Default for new interns'),
          value: _isDefault,
          onChanged: (v) => setState(() => _isDefault = v),
        ),
      ],
    );
  }
}
