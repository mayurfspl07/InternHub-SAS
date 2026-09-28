import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';

/// Reset a forgotten password with a 6-digit code emailed by the server.
///
/// Step 1: `POST /api/auth/password/forgot {email}`.
/// Step 2: `POST /api/auth/password/reset {email, code, new_password, confirm_password}`.
class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;
  // Seconds until another code can be requested.
  int _resendIn = 0;
  Timer? _resendTimer;

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  void _useDifferentEmail() {
    _resendTimer?.cancel();
    setState(() {
      _codeSent = false;
      _resendIn = 0;
      _info = null;
      _error = null;
      _codeController.clear();
      _passwordController.clear();
      _confirmController.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail ?? '';
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (!ApiConfig.isValidEmail(email)) {
      setState(() => _error = 'Enter the email you sign in with.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ApiClient().post('/api/auth/password/forgot', body: {'email': email});
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _info = res is Map && res['message'] is String
            ? res['message'] as String
            : 'If an account exists for that email, a reset code is on its way.';
      });
      _startResendCooldown();
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    String? problem;
    if (code.length != 6) {
      problem = 'Enter the 6-digit code from the email.';
    } else if (!ApiConfig.isValidPassword(password)) {
      problem = '${ApiConfig.passwordRule}.';
    } else if (password != _confirmController.text) {
      problem = "Passwords don't match.";
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient().post('/api/auth/password/reset', body: {
        'email': _emailController.text.trim(),
        'code': code,
        'new_password': password,
        'confirm_password': _confirmController.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated. Sign in with your new password.')),
      );
      Navigator.of(context).pop(_emailController.text.trim());
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(context, title: 'Reset password'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.p20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _codeSent
                    ? 'Enter the code we emailed you and choose a new password.'
                    : "We'll email you a 6-digit code to reset your password.",
                style: AppTypography.body,
              ),
              const SizedBox(height: 20),
              CustomTextField(
                label: 'Email',
                hintText: 'you@company.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.mail_outline_rounded,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_codeSent && !_busy) _requestCode();
                },
                readOnly: _codeSent,
              ),
              if (_codeSent)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : _useDifferentEmail,
                    child: const Text('Use a different email'),
                  ),
                ),
              if (_codeSent) ...[
                const SizedBox(height: 14),
                CustomTextField(
                  label: 'Reset code',
                  hintText: '6 digits',
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.pin_outlined,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                ),
                const SizedBox(height: 14),
                CustomTextField(
                  label: 'New password',
                  helperText: ApiConfig.passwordRule,
                  controller: _passwordController,
                  obscureText: _obscure,
                  prefixIcon: Icons.lock_outline_rounded,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: 14),
                CustomTextField(
                  label: 'Confirm new password',
                  controller: _confirmController,
                  obscureText: _obscure,
                  prefixIcon: Icons.lock_outline_rounded,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) {
                    if (!_busy) _resetPassword();
                  },
                ),
              ],
              if (_info != null && _codeSent) ...[
                const SizedBox(height: 14),
                Text(_info!, style: AppTypography.caption),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
              ],
              const SizedBox(height: 24),
              CustomButton(
                text: _codeSent ? 'Set new password' : 'Send code',
                isLoading: _busy,
                onPressed: _busy ? null : (_codeSent ? _resetPassword : _requestCode),
              ),
              if (_codeSent) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy || _resendIn > 0 ? null : _requestCode,
                  child: Text(_resendIn > 0 ? 'Send a new code in ${_resendIn}s' : 'Send a new code'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
