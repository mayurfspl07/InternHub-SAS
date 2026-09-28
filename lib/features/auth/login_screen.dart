import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../dashboard/main_navigation_wrapper.dart';
import 'forgot_password_screen.dart';
import '../../core/constants/app_typography.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _rememberMe = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  int? _retryAfterCountdown;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    setState(() => _retryAfterCountdown = seconds);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_retryAfterCountdown == null || _retryAfterCountdown! <= 1) {
        timer.cancel();
        setState(() {
          _retryAfterCountdown = null;
          _errorMessage = null;
        });
      } else {
        setState(() => _retryAfterCountdown = _retryAfterCountdown! - 1);
      }
    });
  }

  Future<void> _handleLogin() async {
    if (_retryAfterCountdown != null && _retryAfterCountdown! > 0) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      await ref.read(appStateProvider.notifier).login(
        email: email,
        password: password,
        remember: _rememberMe,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigationWrapper()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (e.isRateLimited) {
          final waitSec = e.retryAfterSeconds ?? 60;
          _errorMessage = 'Too many attempts. Wait a moment, then try again.';
          _startCountdown(waitSec);
        } else {
          _errorMessage = e.message;
        }
      });
    } catch (e, stack) {
      // Not a server rejection (those are ApiExceptions above): something failed after sign-in,
      // e.g. reading the profile. Say so instead of blaming the password.
      debugPrint('Login failed after the server accepted it: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "Signed in, but the app couldn't load your account. Please try again.";
      });
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialEmail: _emailController.text.trim())),
    );
    if (email != null && email.isNotEmpty && mounted) {
      _emailController.text = email;
      _passwordController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (ModalRoute.of(context)?.canPop ?? false) {
          Navigator.of(context).maybePop();
        } else {
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          extendBody: true,
          extendBodyBehindAppBar: true,
          backgroundColor: AppColors.surface,
          body: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Full Screen Background Illustration
                Image.asset(
                  'assets/images/login background.png',
                  width: size.width,
                  height: size.height,
                  fit: BoxFit.cover,
                ),

                // 2. Safe Area Form Content
                Positioned.fill(
                  child: SafeArea(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: AutofillGroup(
                      child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),

                        // Top-Left Branding Logo
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Image.asset(
                            'assets/images/Logo_lightmode.png',
                            height: 46,
                            fit: BoxFit.contain,
                          ),
                        ),

                        // Responsive Spacer to position "Welcome Back!" right below the 3D illustration
                        SizedBox(height: size.height * 0.275),

                        // Title: Welcome Back!
                        Center(
                          child: Text(
                            'Welcome back',
                            style: AppTypography.headline.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -0.4),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Subtitle
                        Center(
                          child: Text(
                            'Sign in to your workspace',
                            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Error Banner if any
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.dangerSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            // The wait time shows once, on the button below.
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.dangerInk, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: AppTypography.caption.copyWith(color: AppColors.dangerInk, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // 1. Email or Phone Label & Field
                        Text(
                          'Email',
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border, width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.ink.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email, AutofillHints.username],
                            autocorrect: false,
                            enableSuggestions: false,
                            style: AppTypography.body.copyWith(fontWeight: FontWeight.w500, color: AppColors.ink),
                            decoration: InputDecoration(
                              hintText: 'you@company.com',
                              hintStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary, fontWeight: FontWeight.w400),
                              prefixIcon: Icon(
                                Icons.mail_outline_rounded,
                                color: AppColors.textTertiary,
                                size: 20,
                              ),
                              border: InputBorder.none,
                              filled: false,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Enter your email';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 2. Password Label & Field
                        Text(
                          'Password',
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border, width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.ink.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            autocorrect: false,
                            enableSuggestions: false,
                            onFieldSubmitted: (_) => _handleLogin(),
                            style: AppTypography.body.copyWith(fontWeight: FontWeight.w500, color: AppColors.ink),
                            decoration: InputDecoration(
                              hintText: 'Your password',
                              hintStyle: AppTypography.caption.copyWith(color: AppColors.textTertiary, fontWeight: FontWeight.w400),
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: AppColors.textTertiary,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                              ),
                              border: InputBorder.none,
                              filled: false,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'Enter your password';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Remember Me & Forgot Password Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Remember Me Checkbox (the whole label is the tap target)
                            InkWell(
                              onTap: () => setState(() => _rememberMe = !_rememberMe),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                                child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      onChanged: (val) => setState(() => _rememberMe = val ?? true),
                                      activeColor: AppColors.ink,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      side: const BorderSide(color: AppColors.textTertiary, width: 1.4),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Remember me',
                                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              ),
                            ),

                            TextButton(
                              onPressed: _showForgotPasswordDialog,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primaryInk,
                                minimumSize: const Size(44, 44),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: Text(
                                'Forgot password?',
                                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.primaryInk),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // 3. Login Button (Sleek Dark with Arrow)
                        Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                          ),
                          child: ElevatedButton(
                            onPressed: (_isLoading || (_retryAfterCountdown != null && _retryAfterCountdown! > 0))
                                ? null
                                : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onPrimary,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        (_retryAfterCountdown != null && _retryAfterCountdown! > 0)
                                            ? 'Retry in ${_retryAfterCountdown}s'
                                            : 'Sign in',
                                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.onPrimary, letterSpacing: 0.2),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        color: AppColors.onPrimary,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: TextButton.icon(
                            onPressed: () => Navigator.of(context).pushNamed('/join'),
                            icon: const Icon(Icons.link_rounded, size: 18),
                            label: const Text('Have an invite link? Join your team'),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
  }
}
