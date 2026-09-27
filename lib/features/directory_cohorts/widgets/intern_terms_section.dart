import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/load_error_view.dart';

/// Editable internship terms of an intern account (sent with create / update user).
class InternTerms {
  int? durationMonths;
  bool? isPaid;
  double? stipendAmount;

  InternTerms({this.durationMonths, this.isPaid, this.stipendAmount});

  /// Problem to show before saving, or null when the terms are valid.
  String? get problem {
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

/// Internship length (from the organization's Internship Duration masters),
/// paid / unpaid and the monthly stipend.
class InternTermsSection extends StatefulWidget {
  final InternTerms terms;

  const InternTermsSection({super.key, required this.terms});

  @override
  State<InternTermsSection> createState() => _InternTermsSectionState();
}

class _InternTermsSectionState extends State<InternTermsSection> {
  List<Map<String, dynamic>> _durations = const [];
  String? _error;
  bool _loading = true;
  late final TextEditingController _stipendController;

  @override
  void initState() {
    super.initState();
    _stipendController = TextEditingController(
      text: widget.terms.stipendAmount == null ? '' : widget.terms.stipendAmount!.toStringAsFixed(0),
    );
    _loadDurations();
  }

  @override
  void dispose() {
    _stipendController.dispose();
    super.dispose();
  }

  Future<void> _loadDurations() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient().get('/api/admin/internship-durations/dropdown');
      final rows = res is Map && res['durations'] is List
          ? (res['durations'] as List).whereType<Map<String, dynamic>>().where((d) => d['is_active'] != false).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _durations = rows;
        _loading = false;
        // New interns start on the organization's default tier.
        if (widget.terms.durationMonths == null) {
          final def = rows.where((d) => d['is_default'] == true).firstOrNull;
          widget.terms.durationMonths = (def?['duration_months'] as num?)?.toInt();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceMuted,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      );

  @override
  Widget build(BuildContext context) {
    final terms = widget.terms;
    final months = _durations.map((d) => (d['duration_months'] as num?)?.toInt()).whereType<int>().toSet().toList()
      ..sort();
    if (terms.durationMonths != null && !months.contains(terms.durationMonths)) months.insert(0, terms.durationMonths!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Internship length', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const SizedBox(height: 8),
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else if (_error != null)
          Row(
            children: [
              Expanded(
                child: Text('Couldn\'t load internship lengths: $_error',
                    style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              ),
              TextButton(onPressed: _loadDurations, child: const Text('Retry')),
            ],
          )
        else
          DropdownButtonFormField<int?>(
            initialValue: terms.durationMonths,
            decoration: _decoration('Not set'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('Not set')),
              ...months.map((m) {
                final tier = _durations.where((d) => (d['duration_months'] as num?)?.toInt() == m).firstOrNull;
                return DropdownMenuItem<int?>(
                  value: m,
                  child: Text(tier?['title']?.toString() ?? '$m months'),
                );
              }),
            ],
            onChanged: (v) => setState(() => terms.durationMonths = v),
          ),
        const SizedBox(height: 12),
        const Text('Stipend', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
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
            decoration: _decoration('Monthly stipend (₹)').copyWith(prefixText: '₹ '),
            onChanged: (v) => terms.stipendAmount = double.tryParse(v.trim()),
          ),
        ],
      ],
    );
  }
}
