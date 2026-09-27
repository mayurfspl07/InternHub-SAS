import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/file_export_service.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';

/// Month-by-month attendance summary per intern (`GET /api/attendance/report` → `monthly_summary`).
/// Admins see the whole organization, mentors their own interns.
class MonthlyAttendanceReportScreen extends StatefulWidget {
  const MonthlyAttendanceReportScreen({super.key});

  @override
  State<MonthlyAttendanceReportScreen> createState() => _MonthlyAttendanceReportScreenState();
}

class _Row {
  final String name;
  final String? department;
  final Map<String, dynamic>? summary;
  const _Row(this.name, this.department, this.summary);
}

class _MonthlyAttendanceReportScreenState extends State<MonthlyAttendanceReportScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  String? _error;
  List<_Row> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _monthKey => DateFormat('yyyy-MM').format(_month);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final last = DateTime(_month.year, _month.month + 1, 0);
    try {
      final res = await ApiClient().get('/api/attendance/report', queryParameters: {
        'start': DateFormat('yyyy-MM-dd').format(_month),
        'end': DateFormat('yyyy-MM-dd').format(last),
        'page_size': 1,
      });
      final interns = res is Map && res['interns'] is List
          ? (res['interns'] as List).whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final summaries = res is Map && res['monthly_summary'] is List
          ? (res['monthly_summary'] as List).whereType<Map<String, dynamic>>().where((s) => s['year_month'] == _monthKey)
          : const <Map<String, dynamic>>[];
      final byUser = {for (final s in summaries) s['user_id']?.toString(): s};
      setState(() {
        _rows = interns
            .map((i) => _Row(i['name']?.toString() ?? '', i['department']?.toString(), byUser[i['id']?.toString()]))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    if (next.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) return;
    setState(() => _month = next);
    _load();
  }

  Future<void> _export() async {
    try {
      await FileExportService.downloadAndShare(
        endpoint: '/api/attendance/export.csv',
        defaultFileName: 'attendance-$_monthKey.csv',
        queryParameters: {'month': _monthKey},
      );
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: 'Export failed');
    }
  }

  Widget _stat(String label, dynamic value, Color color) {
    return Expanded(
      child: Column(children: [
        Text('${value ?? 0}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(
        context,
        title: 'Monthly report',
        actions: [HeaderAction(icon: Icons.download_rounded, tooltip: 'Export CSV', onTap: _export)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 8, AppSpacing.p20, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded)),
                Text(DateFormat('MMMM yyyy').format(_month), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right_rounded)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadErrorView(title: "Couldn't load the report", message: _error!, onRetry: _load)
                    : _rows.isEmpty
                        ? const Center(child: Text('No interns to report on.', style: TextStyle(color: AppColors.textSecondary)))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 4, AppSpacing.p20, 24),
                              itemCount: _rows.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final r = _rows[i];
                                final s = r.summary;
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: AppShadows.soft,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                          child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                                        ),
                                        Text(
                                          s == null ? 'No records' : '${(s['present_rate'] as num?)?.toStringAsFixed(0) ?? 0}% present',
                                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                      ]),
                                      if ((r.department ?? '').isNotEmpty)
                                        Text(r.department!, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                                      if (s != null) ...[
                                        const SizedBox(height: 10),
                                        Row(children: [
                                          _stat('Present', s['present'], AppColors.successInk),
                                          _stat('Late', s['late'], AppColors.warningInk),
                                          _stat('Half day', s['half_day'], AppColors.peachInk),
                                          _stat('Absent', s['absent'], AppColors.dangerInk),
                                          _stat('Days', s['total_days'], AppColors.ink),
                                        ]),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
