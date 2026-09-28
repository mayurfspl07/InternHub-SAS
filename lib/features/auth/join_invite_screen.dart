import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../core/constants/app_typography.dart';

/// Accepts the bare token or the whole invite link (`https://…/join/<token>`).
String inviteTokenFrom(String input) {
  final text = input.trim();
  final at = text.indexOf('/join/');
  if (at < 0) return text;
  return text.substring(at + '/join/'.length).split(RegExp(r'[/?#\s]')).first;
}

/// "9876543210" -> "+91 9876543210", matching how profiles store phone numbers.
String normalizePhone(String input) {
  final digits = input.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? '' : '+91 $digits';
}

class JoinInviteScreen extends ConsumerStatefulWidget {
  final String? initialToken;

  const JoinInviteScreen({super.key, this.initialToken});

  @override
  ConsumerState<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

class _JoinInviteScreenState extends ConsumerState<JoinInviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _deptController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isValidatingToken = false;
  bool _obscurePassword = true;
  String? _tokenError;
  String? _submitError;
  Map<String, dynamic>? _inviteData;
  Timer? _tokenDebounce;
  // The token being checked; a slower response for an older token is ignored.
  String _checkingToken = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null && widget.initialToken!.isNotEmpty) {
      _tokenController.text = widget.initialToken!;
      _validateToken(widget.initialToken!);
    }
  }

  @override
  void dispose() {
    _tokenDebounce?.cancel();
    _tokenController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _deptController.dispose();
    _jobTitleController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _validateToken(String token) async {
    final clean = inviteTokenFrom(token);
    if (clean.isEmpty) return;
    if (clean != _tokenController.text) _tokenController.text = clean;

    _checkingToken = clean;
    setState(() {
      _isValidatingToken = true;
      _tokenError = null;
    });

    try {
      final res = await ApiClient().get('/api/auth/invite/$clean');
      if (!mounted || clean != _checkingToken) return;
      setState(() {
        _inviteData = res is Map<String, dynamic> ? res : null;
        _isValidatingToken = false;
      });
    } catch (e) {
      if (!mounted || clean != _checkingToken) return;
      setState(() {
        _tokenError = e is ApiException ? e.message : 'This invite link is invalid or has expired.';
        _inviteData = null;
        _isValidatingToken = false;
      });
    }
  }

  /// Checks the token once typing pauses, not on every keystroke.
  void _onTokenChanged(String value) {
    _tokenDebounce?.cancel();
    if (_inviteData != null || _tokenError != null) {
      setState(() {
        _inviteData = null;
        _tokenError = null;
      });
    }
    if (inviteTokenFrom(value).length < 6) return;
    _tokenDebounce = Timer(const Duration(milliseconds: 500), () => _validateToken(value));
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final token = inviteTokenFrom(_tokenController.text);
    if (token.isEmpty) {
      setState(() => _tokenError = 'Paste your invite link or code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _submitError = null;
    });

    try {
      final body = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'password': _passwordController.text,
        'confirm_password': _confirmPasswordController.text,
        'joining_date': DateTime.now().toIso8601String().substring(0, 10),
        // The server requires phone, department and job title.
        'phone': normalizePhone(_phoneController.text),
        'department': _deptController.text.trim(),
        'job_title': _jobTitleController.text.trim(),
      };

      final res = await ApiClient().post('/api/auth/invite/$token/register', body: body);

      // Invite sign-ups always wait for approval by the link's mentor or an admin.
      final message = res is Map && res['message'] is String
          ? res['message'] as String
          : 'Your request was submitted. You can sign in after it is approved.';
      if (mounted) {
        setState(() => _isLoading = false);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.hourglass_top_rounded, color: AppColors.primaryInk),
                SizedBox(width: 8),
                Text('Waiting for approval'),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _submitError = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitError = "Couldn't send your request. Check your details and try again.";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(context, title: 'Join your team'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: AutofillGroup(
            child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Request to join',
                  style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'Use the invite link from your admin or mentor. They approve your request before you can sign in.',
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),

                // Error message
                if (_submitError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _submitError!,
                      style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Invite Token Field
                CustomTextField(
                  label: 'Invite link or code',
                  hintText: 'Paste the invite link you received',
                  prefixIcon: Icons.vpn_key_outlined,
                  controller: _tokenController,
                  suffixIcon: _isValidatingToken
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          tooltip: 'Check invite',
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          onPressed: () => _validateToken(_tokenController.text),
                        ),
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  onChanged: _onTokenChanged,
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Paste your invite link or code' : null,
                ),
                if (_tokenError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      _tokenError!,
                      style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
                    ),
                  ),
                if (_inviteData != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.successSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.successInk, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Invite for ${_inviteData!['organization_name'] ?? _inviteData!['label'] ?? 'your team'}',
                            style: AppTypography.caption.copyWith(color: AppColors.successInk, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Name
                CustomTextField(
                  label: 'Full name',
                  hintText: 'e.g. Priya Sharma',
                  prefixIcon: Icons.person_outline_rounded,
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Enter your name';
                    if (!ApiConfig.isValidName(val)) return 'Use letters only';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email
                CustomTextField(
                  label: 'Email',
                  hintText: 'you@example.com',
                  prefixIcon: Icons.email_outlined,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Enter your email';
                    if (!ApiConfig.isValidEmail(val)) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  label: 'Mobile number',
                  hintText: '98765 43210',
                  prefixIcon: Icons.phone_outlined,
                  prefixText: '+91 ',
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Enter your mobile number';
                    if (!ApiConfig.isValidPhone(val)) return 'Enter a valid 10-digit mobile number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  label: 'Department',
                  hintText: 'e.g. Engineering',
                  prefixIcon: Icons.business_outlined,
                  controller: _deptController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter your department' : null,
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  label: 'Job title',
                  hintText: 'e.g. Software intern',
                  prefixIcon: Icons.badge_outlined,
                  controller: _jobTitleController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.jobTitle],
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Enter your job title' : null,
                ),
                const SizedBox(height: 16),

                // Password
                CustomTextField(
                  label: 'Password',
                  helperText: ApiConfig.passwordRule,
                  prefixIcon: Icons.lock_outline_rounded,
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (val) {
                    if (val == null || !ApiConfig.isValidPassword(val)) {
                      return ApiConfig.passwordRule;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password
                CustomTextField(
                  label: 'Confirm password',
                  prefixIcon: Icons.lock_outline_rounded,
                  controller: _confirmPasswordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) {
                    if (!_isLoading) _handleRegister();
                  },
                  validator: (val) {
                    if (val != _passwordController.text) {
                      return "Passwords don't match";
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                CustomButton(
                  text: 'Request to join',
                  isLoading: _isLoading,
                  onPressed: _handleRegister,
                ),
                const SizedBox(height: 16),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}
