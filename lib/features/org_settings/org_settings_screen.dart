import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/app_state_provider.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';

/// Common IANA zones offered in the picker; the org's current zone is always included.
const _kTimezones = [
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Asia/Shanghai',
  'Asia/Karachi',
  'Asia/Dhaka',
  'Asia/Kathmandu',
  'Asia/Colombo',
  'Europe/London',
  'Europe/Berlin',
  'Europe/Paris',
  'Africa/Nairobi',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Sao_Paulo',
  'Australia/Sydney',
  'Pacific/Auckland',
  'UTC',
];

/// Organization profile and attendance / leave policies (admins).
///
/// Reads `GET /api/org/current`; saves with `PUT /api/org/profile` and
/// `PUT /api/org/settings`; the logo is uploaded with `POST /api/upload/org-logo`.
class OrgSettingsScreen extends ConsumerStatefulWidget {
  const OrgSettingsScreen({super.key});

  @override
  ConsumerState<OrgSettingsScreen> createState() => _OrgSettingsScreenState();
}

class _OrgSettingsScreenState extends ConsumerState<OrgSettingsScreen> {
  final _api = ApiClient();
  final _nameController = TextEditingController();
  final _quotaController = TextEditingController();
  final _advanceController = TextEditingController();
  final _fullDayController = TextEditingController();
  final _halfDayController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _attempted = false;
  String? _error;
  String? _logoUrl;
  String _timezone = '';
  String _shiftStart = '';
  String _shiftEnd = '';
  String _lateCutoff = '';
  String _noonCutoff = '';
  String _checkinBlock = '';
  bool _selfie = false;
  bool _gps = false;
  bool _autoCheckout = false;

  /// Values as last loaded or saved, to detect unsaved edits.
  String _savedSnapshot = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_nameController, _quotaController, _advanceController, _fullDayController, _halfDayController]) {
      c.dispose();
    }
    super.dispose();
  }

  String _snapshot() => [
        _nameController.text.trim(),
        _timezone,
        _shiftStart,
        _shiftEnd,
        _lateCutoff,
        _noonCutoff,
        _checkinBlock,
        _quotaController.text.trim(),
        _advanceController.text.trim(),
        _fullDayController.text.trim(),
        _halfDayController.text.trim(),
        _selfie,
        _gps,
        _autoCheckout,
      ].join('|');

  bool get _isDirty => !_loading && _error == null && _snapshot() != _savedSnapshot;

  String _hhmm(dynamic v) {
    final s = v?.toString() ?? '';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  String _num(dynamic v) {
    if (v is num) return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return v?.toString() ?? '';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/api/org/current');
      final org = res is Map && res['organization'] is Map ? res['organization'] as Map : const {};
      final s = res is Map && res['settings'] is Map ? res['settings'] as Map : const {};
      if (!mounted) return;
      setState(() {
        _nameController.text = org['name']?.toString() ?? '';
        _timezone = org['timezone']?.toString() ?? '';
        _logoUrl = (org['logo_url']?.toString().isNotEmpty ?? false) ? org['logo_url'].toString() : null;
        _shiftStart = _hhmm(s['shift_start']);
        _shiftEnd = _hhmm(s['shift_end']);
        _lateCutoff = _hhmm(s['late_cutoff']);
        _noonCutoff = _hhmm(s['noon_cutoff']);
        _checkinBlock = _hhmm(s['checkin_block']);
        _quotaController.text = _num(s['leave_quota_days']);
        _advanceController.text = _num(s['advance_leave_days']);
        _fullDayController.text = _num(s['full_day_hours']);
        _halfDayController.text = _num(s['half_day_hours']);
        _selfie = s['require_attendance_selfie'] == true;
        _gps = s['require_attendance_gps'] == true;
        _autoCheckout = s['auto_checkout_enabled'] == true;
        _attempted = false;
        _loading = false;
        _savedSnapshot = _snapshot();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  // ---------------------------------------------------------------- validation

  int? _minutes(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  /// Field errors keyed by field; empty when everything is valid.
  Map<String, String> _validate() {
    final errors = <String, String>{};
    if (_nameController.text.trim().isEmpty) errors['name'] = 'Enter the organization name';

    final start = _minutes(_shiftStart), end = _minutes(_shiftEnd);
    final late = _minutes(_lateCutoff), noon = _minutes(_noonCutoff), block = _minutes(_checkinBlock);
    if (start != null && end != null && end <= start) errors['shiftEnd'] = 'Must be after the shift starts';
    if (start != null && late != null && late < start) errors['late'] = "Can't be before the shift starts";
    if (late != null && noon != null && noon <= late) errors['noon'] = "Must be after the 'late' time";
    if (start != null && block != null && block <= start) errors['block'] = 'Must be after the shift starts';

    final full = double.tryParse(_fullDayController.text.trim());
    final half = double.tryParse(_halfDayController.text.trim());
    if (_fullDayController.text.trim().isNotEmpty && (full == null || full <= 0 || full > 24)) {
      errors['full'] = 'Enter hours between 0 and 24';
    }
    if (_halfDayController.text.trim().isNotEmpty && (half == null || half <= 0)) {
      errors['half'] = 'Enter a number of hours';
    } else if (half != null && full != null && half >= full) {
      errors['half'] = 'Must be less than a full day';
    }

    final quota = int.tryParse(_quotaController.text.trim());
    if (_quotaController.text.trim().isNotEmpty && (quota == null || quota > 365)) {
      errors['quota'] = 'Enter 0 to 365 days';
    }
    final advance = int.tryParse(_advanceController.text.trim());
    if (_advanceController.text.trim().isNotEmpty && (advance == null || advance > 90)) {
      errors['advance'] = 'Enter 0 to 90 days';
    }
    return errors;
  }

  // ---------------------------------------------------------------- actions

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    final initial = parts.length >= 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() => onPicked('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'));
    }
  }

  Future<void> _pickTimezone() async {
    final zones = {..._kTimezones, if (_timezone.isNotEmpty) _timezone}.toList()..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text('Timezone', style: AppTypography.section),
              ),
              for (final z in zones)
                ListTile(
                  title: Text(z.replaceAll('_', ' ')),
                  trailing: z == _timezone ? const Icon(Icons.check_rounded, color: AppColors.primaryInk) : null,
                  onTap: () => Navigator.pop(ctx, z),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _timezone = picked);
  }

  Future<void> _uploadLogo() async {
    if (_uploadingLogo) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 90);
    if (picked == null || !mounted) return;
    setState(() => _uploadingLogo = true);
    try {
      final file = await http.MultipartFile.fromPath('file', picked.path);
      final res = await _api.postMultipart('/api/upload/org-logo', files: [file]);
      final url = res is Map ? (res['logo_url'] ?? res['url'])?.toString() : null;
      if (mounted) {
        setState(() => _logoUrl = url ?? _logoUrl);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo updated')));
      }
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't upload the logo");
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _save() async {
    setState(() => _attempted = true);
    if (_validate().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fix the highlighted fields first')));
      return;
    }
    setState(() => _saving = true);
    String? t(String v) => v.isEmpty ? null : '$v:00';

    // Two endpoints: say exactly which part saved if only one succeeds.
    var profileSaved = false;
    try {
      await _api.put('/api/org/profile', body: {
        'name': _nameController.text.trim(),
        if (_timezone.isNotEmpty) 'timezone': _timezone,
      });
      profileSaved = true;
      await _api.put('/api/org/settings', body: {
        'shift_start': t(_shiftStart),
        'shift_end': t(_shiftEnd),
        'late_cutoff': t(_lateCutoff),
        'noon_cutoff': t(_noonCutoff),
        'checkin_block': t(_checkinBlock),
        'leave_quota_days': int.tryParse(_quotaController.text.trim()),
        'advance_leave_days': int.tryParse(_advanceController.text.trim()),
        'full_day_hours': double.tryParse(_fullDayController.text.trim()),
        'half_day_hours': double.tryParse(_halfDayController.text.trim()),
        'require_attendance_selfie': _selfie,
        'require_attendance_gps': _gps,
        'auto_checkout_enabled': _autoCheckout,
      }..removeWhere((_, v) => v == null));
      await ref.read(appStateProvider.notifier).fetchCurrentUser(); // organization name in the app
      if (mounted) {
        setState(() => _savedSnapshot = _snapshot());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
      }
    } catch (e) {
      if (mounted) {
        showApiError(
          context,
          e,
          prefix: profileSaved ? "Name and timezone saved, but the policies didn't" : "Couldn't save",
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text("Your edits haven't been saved."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerInk),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ---------------------------------------------------------------- UI

  Widget _section(String title, List<Widget> children, {String? subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppSpacing.r24), boxShadow: AppShadows.soft),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: AppTypography.cardTitle),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: AppTypography.caption),
        ],
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _timeRow(String label, String value, ValueChanged<String> onChanged, {String? error}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: AppTypography.body.copyWith(color: AppColors.ink))),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _pickTime(value, onChanged),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(96, 44),
                  side: BorderSide(color: error != null ? AppColors.danger : AppColors.border),
                ),
                child: Text(value.isEmpty ? 'Set time' : formatTime(value)),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(error, style: AppTypography.label.copyWith(color: AppColors.dangerInk)),
            ),
        ],
      ),
    );
  }

  Widget _numberField(String label, TextEditingController c, {bool decimal = false, String? error, String? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, errorText: error, suffixText: suffix),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errors = _attempted ? _validate() : const <String, String>{};

    return PopScope(
      canPop: !_isDirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) {
          setState(() => _savedSnapshot = _snapshot());
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        appBar: pageAppBar(context, title: 'Organization settings'),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? LoadErrorView(title: "Couldn't load organization settings", message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.p20),
                      children: [
                        _section('Profile', [
                          Row(children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                AppAvatar(url: _logoUrl, size: 60),
                                if (_uploadingLogo)
                                  const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Flexible(
                              child: OutlinedButton.icon(
                                onPressed: _uploadingLogo ? null : _uploadLogo,
                                icon: const Icon(Icons.upload_rounded, size: 18),
                                label: Text(_uploadingLogo ? 'Uploading…' : 'Change logo'),
                                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(labelText: 'Organization name', errorText: errors['name']),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: _pickTimezone,
                            borderRadius: BorderRadius.circular(12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Timezone',
                                suffixIcon: Icon(Icons.arrow_drop_down_rounded),
                              ),
                              child: Text(
                                _timezone.isEmpty ? 'Choose a timezone' : _timezone.replaceAll('_', ' '),
                                style: AppTypography.body.copyWith(color: _timezone.isEmpty ? AppColors.textSecondary : AppColors.ink),
                              ),
                            ),
                          ),
                        ]),
                        _section('Working hours', subtitle: 'Used to mark interns late, half day or absent.', [
                          _timeRow('Shift starts', _shiftStart, (v) => _shiftStart = v),
                          _timeRow('Shift ends', _shiftEnd, (v) => _shiftEnd = v, error: errors['shiftEnd']),
                          _timeRow('Late after', _lateCutoff, (v) => _lateCutoff = v, error: errors['late']),
                          _timeRow('Half day after', _noonCutoff, (v) => _noonCutoff = v, error: errors['noon']),
                          _timeRow('No check-in after', _checkinBlock, (v) => _checkinBlock = v, error: errors['block']),
                          const SizedBox(height: 12),
                          _numberField('Hours for a full day', _fullDayController, decimal: true, error: errors['full'], suffix: 'h'),
                          _numberField('Hours for a half day', _halfDayController, decimal: true, error: errors['half'], suffix: 'h'),
                        ]),
                        _section('Attendance checks', [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Require a selfie'),
                            value: _selfie,
                            onChanged: (v) => setState(() => _selfie = v),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Require location'),
                            value: _gps,
                            onChanged: (v) => setState(() => _gps = v),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Auto check-out'),
                            subtitle: const Text('Close sessions nobody checked out of'),
                            value: _autoCheckout,
                            onChanged: (v) => setState(() => _autoCheckout = v),
                          ),
                        ]),
                        _section('Leave', [
                          _numberField('Leave days per intern', _quotaController, error: errors['quota'], suffix: 'days'),
                          _numberField('Notice needed before leave', _advanceController, error: errors['advance'], suffix: 'days'),
                        ]),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _saving || !_isDirty ? null : _save,
                            child: _saving
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(_isDirty ? 'Save changes' : 'No changes'),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
      ),
    );
  }
}
