import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/api/auth_storage.dart';
import '../../core/api/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../core/constants/app_typography.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ChangePasswordDialog(),
    );
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await ApiClient().post('/api/profile/change-password', body: {
        'current_password': _currentPasswordController.text,
        'new_password': _newPasswordController.text,
        'confirm_password': _confirmPasswordController.text,
      });
      // Changing the password signs out every old session; keep this one with the new token.
      final token = res is Map ? res['token']?.toString() : null;
      if (token != null && token.isNotEmpty) await AuthStorage.updateToken(token);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = "Couldn't change your password. Check your current password and try again.";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return PopScope(
      // Back can't close the dialog mid-request.
      canPop: !_isLoading,
      child: AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_reset_rounded, color: AppColors.primaryInk, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Change password',
              style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Current Password
              CustomTextField(
                label: 'Current password',
                prefixIcon: Icons.lock_outline_rounded,
                controller: _currentPasswordController,
                obscureText: _obscureCurrent,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
                suffixIcon: IconButton(
                  tooltip: _obscureCurrent ? 'Show password' : 'Hide password',
                  icon: Icon(_obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                ),
                validator: (val) => (val == null || val.isEmpty) ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 12),

              // New Password
              CustomTextField(
                label: 'New password',
                helperText: ApiConfig.passwordRule,
                prefixIcon: Icons.vpn_key_outlined,
                controller: _newPasswordController,
                obscureText: _obscureNew,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                enabled: !_isLoading,
                suffixIcon: IconButton(
                  tooltip: _obscureNew ? 'Show password' : 'Hide password',
                  icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
                validator: (val) {
                  if (val == null || !ApiConfig.isValidPassword(val)) {
                    return ApiConfig.passwordRule;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Confirm Password
              CustomTextField(
                label: 'Confirm new password',
                prefixIcon: Icons.lock_outline_rounded,
                controller: _confirmPasswordController,
                obscureText: _obscureNew,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                enabled: !_isLoading,
                onFieldSubmitted: (_) => _handleSubmit(),
                validator: (val) {
                  if (val != _newPasswordController.text) {
                    return "Passwords don't match";
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            minimumSize: const Size(0, 44),
            elevation: 0,
            shape: const StadiumBorder(),
          ),
          child: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
              : const Text('Change password'),
        ),
      ],
      ),
    );
  }
}
