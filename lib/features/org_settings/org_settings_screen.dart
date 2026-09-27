import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';

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
  final _timezoneController = TextEditingController();
  final _quotaController = TextEditingController();
  final _advanceController = TextEditingController();
  final _fullDayController = TextEditingController();
  final _halfDayController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _logoUrl;
  String _shiftStart = '';
  String _shiftEnd = '';
  String _lateCutoff = '';
  String _noonCutoff = '';
  String _checkinBlock = '';
  bool _selfie = false;
  bool _gps = false;
  bool _autoCheckout = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_nameController, _timezoneController, _quotaController, _advanceController, _fullDayController, _halfDayController]) {
      c.dispose();
    }
    super.dispose();
  }

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
      setState(() {
        _nameController.text = org['name']?.toString() ?? '';
        _timezoneController.text = org['timezone']?.toString() ?? '';
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
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    final initial = parts.length >= 2
        ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0)
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      onPicked('${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _uploadLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 90);
    if (picked == null) return;
    try {
      final file = await http.MultipartFile.fromPath('file', picked.path);
      final res = await _api.postMultipart('/api/upload/org-logo', files: [file]);
      final url = res is Map ? (res['logo_url'] ?? res['url'])?.toString() : null;
      if (mounted) {
        setState(() => _logoUrl = url ?? _logoUrl);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logo updated')));
      }
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: 'Could not upload the logo');
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The organization needs a name')));
      return;
    }
    setState(() => _saving = true);
    String? t(String v) => v.isEmpty ? null : '$v:00';
    try {
      await _api.put('/api/org/profile', body: {
        'name': name,
        if (_timezoneController.text.trim().isNotEmpty) 'timezone': _timezoneController.text.trim(),
      });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organization settings saved'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: 'Could not save');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppSpacing.r24), boxShadow: AppShadows.soft),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: AppTypography.cardTitle),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _timeRow(String label, String value, ValueChanged<String> onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: OutlinedButton(
        onPressed: () => _pickTime(value, (v) => setState(() => onChanged(v))),
        child: Text(value.isEmpty ? 'Set' : value),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController c, {bool decimal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(context, title: 'Organization'),
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
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: AppColors.primarySoft,
                            backgroundImage: _logoUrl != null ? NetworkImage(ApiConfig.mediaUrl(_logoUrl!)) : null,
                            child: _logoUrl == null ? const Icon(Icons.business_rounded, color: AppColors.primaryInk) : null,
                          ),
                          const SizedBox(width: 14),
                          OutlinedButton.icon(
                            onPressed: _uploadLogo,
                            icon: const Icon(Icons.upload_rounded, size: 18),
                            label: const Text('Change logo'),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Organization name')),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _timezoneController,
                          decoration: const InputDecoration(labelText: 'Timezone', hintText: 'e.g. Asia/Kolkata'),
                        ),
                      ]),
                      _section('Working hours', [
                        _timeRow('Shift starts', _shiftStart, (v) => _shiftStart = v),
                        _timeRow('Shift ends', _shiftEnd, (v) => _shiftEnd = v),
                        _timeRow('Late after', _lateCutoff, (v) => _lateCutoff = v),
                        _timeRow('Half day after', _noonCutoff, (v) => _noonCutoff = v),
                        _timeRow('No check-in after', _checkinBlock, (v) => _checkinBlock = v),
                        const SizedBox(height: 6),
                        _numberField('Hours for a full day', _fullDayController, decimal: true),
                        _numberField('Hours for a half day', _halfDayController, decimal: true),
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
                          title: const Text('Auto check-out missed sessions'),
                          value: _autoCheckout,
                          onChanged: (v) => setState(() => _autoCheckout = v),
                        ),
                      ]),
                      _section('Leave', [
                        _numberField('Leave days per intern', _quotaController),
                        _numberField('Days of notice before a leave', _advanceController),
                      ]),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Save changes'),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }
}
