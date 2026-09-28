import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/load_error_view.dart';
import '../auth/login_screen.dart';
import '../../core/constants/app_typography.dart';

/// Platform-admin tool: wipes every organization's data on this server
/// (`POST /api/admin/clear-database`, authorised by the server's clear password).
class DataManagementScreen extends ConsumerStatefulWidget {
  const DataManagementScreen({super.key});

  @override
  ConsumerState<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends ConsumerState<DataManagementScreen> {
  static const _confirmWord = 'DELETE';

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _ready => _passwordController.text.isNotEmpty && _confirmController.text.trim() == _confirmWord && !_isLoading;

  Future<void> _confirmAndClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete everything?'),
        content: const Text(
          'Every organization on this server loses its data. Admin accounts are kept, and you will be signed out. '
          "This can't be undone.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(appStateProvider.notifier).clearDatabase(_passwordController.text);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = apiErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  // Mirrors clear_all_database_data() on the server.
  static const _wiped = [
    'Attendance, leave and standups',
    'Projects, tasks, comments and links',
    'Performance reviews, announcements and cohorts',
    'Notifications, the activity log and invite links',
    'Every account except admins',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(context, title: 'Danger zone'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 8, AppSpacing.p20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dangerous_rounded, color: AppColors.dangerInk),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Clear all data on this server',
                            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.dangerInk),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This affects every organization, not just yours. Admin accounts are kept; everything else is deleted for good:',
                      style: AppTypography.caption.copyWith(color: AppColors.ink, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    for (final line in _wiped)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('•  ', style: AppTypography.caption.copyWith(color: AppColors.ink)),
                            Expanded(child: Text(line, style: AppTypography.caption.copyWith(color: AppColors.ink))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !_isLoading,
                onChanged: (_) => setState(() => _errorMessage = null),
                decoration: InputDecoration(
                  labelText: 'Database clear password',
                  helperText: "The server's clear password, not your sign-in password",
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmController,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                enabled: !_isLoading,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Type $_confirmWord to confirm'),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(_errorMessage!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _ready ? _confirmAndClear : null,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
                  icon: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                      : const Icon(Icons.delete_forever_rounded),
                  label: const Text('Clear all data'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
