import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../core/constants/app_typography.dart';

/// Editable internship terms of an intern account (sent with create / update user / add member).
class InternTerms {
  int? durationMonths;
  bool? isPaid;
  double? stipendAmount;

  InternTerms({this.durationMonths, this.isPaid, this.stipendAmount});

  /// Problem to show before saving, or null when the terms are valid.
  String? get problem {
    if (durationMonths == null) return 'Choose an internship duration.';
    if (isPaid == true && (stipendAmount == null || stipendAmount! <= 0)) {
      return 'Enter the monthly stipend for a paid internship.';
    }
    return null;
  }

  Map<String, dynamic> toPayload() => {
        'internship_duration_months': durationMonths,
        'is_paid': isPaid,
        'stipend_amount': isPaid == true ? stipendAmount : null,
      };
}

/// One of the organization's active internship durations (Internship durations master).
class DurationTier {
  final String title;
  final int months;
  final int? days;
  final int leaves;
  final bool isDefault;

  const DurationTier({required this.title, required this.months, this.days, required this.leaves, this.isDefault = false});

  factory DurationTier.fromJson(Map<String, dynamic> j) => DurationTier(
        title: j['title']?.toString() ?? '${j['duration_months']} months',
        months: (j['duration_months'] as num?)?.toInt() ?? 0,
        days: (j['duration_days'] as num?)?.toInt(),
        leaves: (j['leaves'] as num?)?.toInt() ?? 0,
        isDefault: j['is_default'] == true,
      );

  String get summary => '${plural(months, 'month')} · ${plural(leaves, 'leave day')}';
}

/// Active tiers from `GET /api/admin/internship-durations/dropdown` (the caller's own organization).
Future<List<DurationTier>> fetchDurationTiers() async {
  final res = await ApiClient().get('/api/admin/internship-durations/dropdown');
  final rows = res is Map && res['durations'] is List ? res['durations'] as List : const [];
  return rows
      .whereType<Map<String, dynamic>>()
      .where((d) => d['is_active'] != false)
      .map(DurationTier.fromJson)
      .where((t) => t.months > 0)
      .toList()
    ..sort((a, b) => a.months.compareTo(b.months));
}

/// Duration dropdown for an intern. Every intern needs one, so there is no "Not set";
/// a new intern starts on the organization's default tier. The leave allowance comes
/// from the chosen tier and is shown under the field.
class InternDurationField extends StatefulWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;

  const InternDurationField({super.key, required this.value, required this.onChanged, this.enabled = true});

  @override
  State<InternDurationField> createState() => _InternDurationFieldState();
}

class _InternDurationFieldState extends State<InternDurationField> {
  List<DurationTier> _tiers = const [];
  bool _loading = true;
  String? _error;

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
      final tiers = await fetchDurationTiers();
      if (!mounted) return;
      setState(() {
        _tiers = tiers;
        _loading = false;
      });
      // Preselect the default tier (or the only one) for a new intern.
      if (widget.value == null && tiers.isNotEmpty) {
        widget.onChanged((tiers.where((t) => t.isDefault).firstOrNull ?? tiers.first).months);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LinearProgressIndicator(minHeight: 2);
    if (_error != null) {
      return Row(
        children: [
          Expanded(
            child: Text("Couldn't load durations: $_error", style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
          ),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    if (_tiers.isEmpty) {
      return Text(
        'No active internship durations. An admin can add them under More → Internship durations.',
        style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
      );
    }

    // An intern whose tier was since deactivated keeps it visible until changed.
    final tiers = [..._tiers];
    if (widget.value != null && !tiers.any((t) => t.months == widget.value)) {
      tiers.insert(0, DurationTier(title: '${plural(widget.value!, 'month')} (inactive)', months: widget.value!, leaves: 0));
    }
    final selected = tiers.where((t) => t.months == widget.value).firstOrNull;

    return DropdownButtonFormField<int>(
      initialValue: selected?.months,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Internship duration',
        helperText: selected == null ? 'Sets the internship length and leave allowance' : 'Leave allowance: ${plural(selected.leaves, 'day')}',
      ),
      items: [
        for (final t in tiers)
          DropdownMenuItem<int>(
            value: t.months,
            child: Text('${t.title} · ${t.summary}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: widget.enabled ? widget.onChanged : null,
    );
  }
}

/// Internship duration (from the organization's masters), paid / unpaid and the monthly stipend.
class InternTermsSection extends StatefulWidget {
  final InternTerms terms;

  const InternTermsSection({super.key, required this.terms});

  @override
  State<InternTermsSection> createState() => _InternTermsSectionState();
}

class _InternTermsSectionState extends State<InternTermsSection> {
  late final TextEditingController _stipendController;

  @override
  void initState() {
    super.initState();
    _stipendController = TextEditingController(
      text: widget.terms.stipendAmount == null ? '' : widget.terms.stipendAmount!.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _stipendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terms = widget.terms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InternDurationField(
          value: terms.durationMonths,
          onChanged: (v) => setState(() => terms.durationMonths = v),
        ),
        const SizedBox(height: 14),
        Text('Stipend', style: AppTypography.bodyStrong.copyWith(fontSize: 13)),
        const SizedBox(height: 8),
        SegmentedButton<bool?>(
          segments: const [
            ButtonSegment(value: null, label: Text('Not set')),
            ButtonSegment(value: false, label: Text('Unpaid')),
            ButtonSegment(value: true, label: Text('Paid')),
          ],
          selected: {terms.isPaid},
          onSelectionChanged: (s) => setState(() => terms.isPaid = s.first),
        ),
        if (terms.isPaid == true) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _stipendController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Monthly stipend', prefixText: '₹ '),
            onChanged: (v) => terms.stipendAmount = double.tryParse(v.trim()),
          ),
        ],
      ],
    );
  }
}
