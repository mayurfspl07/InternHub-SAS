import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../dashboard/main_navigation_wrapper.dart';

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
    final clean = token.trim();
    if (clean.isEmpty) return;

    setState(() {
      _isValidatingToken = true;
      _tokenError = null;
    });

    try {
      final res = await ApiClient().get('/api/auth/invite/$clean');
      if (res is Map<String, dynamic>) {
        setState(() {
          _inviteData = res;
          _isValidatingToken = false;
        });
      }
    } catch (e) {
      setState(() {
        _tokenError = e is ApiException ? e.message : 'Invalid or expired invite token.';
        _inviteData = null;
        _isValidatingToken = false;
      });
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _tokenError = 'Please enter an invite token.');
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
        if (_phoneController.text.trim().isNotEmpty) 'phone': _phoneController.text.trim(),
        if (_deptController.text.trim().isNotEmpty) 'department': _deptController.text.trim(),
        if (_jobTitleController.text.trim().isNotEmpty) 'job_title': _jobTitleController.text.trim(),
      };

      final res = await ApiClient().post('/api/auth/invite/$token/register', body: body);

      if (mounted) {
        if (res is Map && res['status'] == 'pending_approval') {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, color: AppColors.primaryInk),
                  SizedBox(width: 8),
                  Text('Registration Pending'),
                ],
              ),
              content: const Text(
                'Your account has been submitted for administrative approval. You will receive an email once approved.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context); // back to login
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          // Attempt auto sign in
          await ref.read(appStateProvider.notifier).login(
                email: _emailController.text.trim(),
                password: _passwordController.text,
              );
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainNavigationWrapper()),
              (route) => false,
            );
          }
        }
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
          _submitError = 'An error occurred during registration. Please check your inputs.';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(context, title: 'Join via Invite'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Onboard to Your Workspace',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Enter the invite code provided by your organization admin or mentor',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),

                // Error message
                if (_submitError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _submitError!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Invite Token Field
                CustomTextField(
                  label: 'Invite Token / Code',
                  hintText: 'Enter token or paste code',
                  prefixIcon: Icons.vpn_key_outlined,
                  controller: _tokenController,
                  suffixIcon: _isValidatingToken
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          onPressed: () => _validateToken(_tokenController.text),
                        ),
                  onChanged: (val) {
                    if (val.length >= 6) {
                      _validateToken(val);
                    }
                  },
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Invite code is required' : null,
                ),
                if (_tokenError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      _tokenError!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                if (_inviteData != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Valid Invite: ${_inviteData!['label'] ?? _inviteData!['organization_name'] ?? 'Authorized Workspace'}',
                            style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                // Name
                CustomTextField(
                  label: 'Full Name',
                  hintText: 'e.g. Jane Doe',
                  prefixIcon: Icons.person_outline_rounded,
                  controller: _nameController,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Name is required';
                    if (!ApiConfig.isValidName(val)) return 'Please enter a valid name';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email
                CustomTextField(
                  label: 'Email Address',
                  hintText: 'e.g. name@domain.com',
                  prefixIcon: Icons.email_outlined,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Email is required';
                    if (!ApiConfig.isValidEmail(val)) return 'Please enter a valid email address';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Department
                CustomTextField(
                  label: 'Department (Optional)',
                  hintText: 'e.g. Engineering, Design',
                  prefixIcon: Icons.business_outlined,
                  controller: _deptController,
                ),
                const SizedBox(height: 16),

                // Phone
                CustomTextField(
                  label: 'Phone (Optional)',
                  hintText: 'e.g. +91 9876543210',
                  prefixIcon: Icons.phone_outlined,
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),

                // Password
                CustomTextField(
                  label: 'Create Password',
                  hintText: 'At least 8 characters',
                  prefixIcon: Icons.lock_outline_rounded,
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: (val) {
                    if (val == null || val.length < ApiConfig.passwordMin) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password
                CustomTextField(
                  label: 'Confirm Password',
                  hintText: 'Re-enter your password',
                  prefixIcon: Icons.lock_outline_rounded,
                  controller: _confirmPasswordController,
                  obscureText: _obscurePassword,
                  validator: (val) {
                    if (val != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 28),

                CustomButton(
                  text: 'Register via Invite',
                  isLoading: _isLoading,
                  onPressed: _handleRegister,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
