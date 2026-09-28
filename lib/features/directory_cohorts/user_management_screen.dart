import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import 'widgets/intern_terms_section.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/user_360_profile_dialog.dart';
import '../../shared/widgets/reference_components.dart';
import '../../core/constants/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/pagination_bar.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  final _searchController = TextEditingController();
  String _selectedRoleFilter = 'all';
  bool _isLoading = true;
  Timer? _searchDebounce;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalUsers = 0;
  final int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadUsers); // fetchUsers updates app state, which can't change during the first build
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({int? page}) async {
    if (page != null) {
      _currentPage = page;
    }
    setState(() => _isLoading = true);
    final currentUser = ref.read(appStateProvider).currentUser;
    final isMentor = currentUser.role == UserRole.mentor;
    
    // GET /api/admin/users?page=1&page_size=10&role=intern&search=...
    final roleParam = isMentor ? 'intern' : (_selectedRoleFilter == 'all' ? null : _selectedRoleFilter);
    final searchParam = _searchController.text.trim().isEmpty ? null : _searchController.text.trim();

    final Map<String, dynamic> result;
    try {
      result = await ref.read(appStateProvider.notifier).fetchUsers(
        role: roleParam,
        search: searchParam,
        page: _currentPage,
        pageSize: _pageSize,
      );
    } catch (_) {
      // The error is kept in appState.usersError and shown by the list.
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _currentPage = (result['page'] as num?)?.toInt() ?? _currentPage;
        _totalPages = (result['total_pages'] as num?)?.toInt() ?? 1;
        _totalUsers = (result['total'] as num?)?.toInt() ?? (result['users'] as List?)?.length ?? 0;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _currentPage = 1;
      _loadUsers(page: 1);
    });
  }

  Future<void> _selectJoiningDate(BuildContext context, TextEditingController controller) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime initial = today;
    final parsed = DateTime.tryParse(controller.text.trim());
    if (parsed != null && !parsed.isAfter(today)) {
      initial = parsed;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: today,
    );

    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  String? _validateFullName(String name) {
    if (name.isEmpty) {
      return 'Enter a full name';
    }
    if (name.length < 2) {
      return 'Use at least 2 characters';
    }
    if (name.length > 100) {
      return 'Use 100 characters or fewer';
    }
    // Letters (incl. Unicode), spaces, - ' . only
    final hasInvalid = name.split('').any((char) {
      if (char == ' ' || char == '-' || char == "'" || char == '.') return false;
      final code = char.codeUnitAt(0);
      final isAsciiLetter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      final isUnicodeLetter = code >= 0x00C0 && !RegExp(r'[0-9!@#$%^&*()_+=\[\]{};:"\\|,<>/?~`]').hasMatch(char);
      return !isAsciiLetter && !isUnicodeLetter;
    });
    if (hasInvalid) {
      return "Use letters, spaces, and - ' . only";
    }
    return null;
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) {
      return 'Enter an email';
    }
    if (email.length > 254) {
      return 'Email must be at most 254 characters';
    }
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      return 'Enter a valid email';
    }
    return null;
  }

  String? _extractNationalPhoneDigits(String input) {
    final clean = input.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    String digits = clean;
    if (digits.startsWith('+91')) {
      digits = digits.substring(3);
    } else if (digits.startsWith('91') && digits.length == 12) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    digits = digits.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return digits;
    }
    return null;
  }

  String? _validatePhone(String phone) {
    if (phone.isEmpty) {
      return 'Enter a mobile number';
    }
    if (_extractNationalPhoneDigits(phone) == null) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  String? _validateJobTitle(String title) {
    if (title.isEmpty) {
      return 'Enter a job title';
    }
    if (title.length > 100) {
      return 'Job title must be at most 100 characters';
    }
    if (RegExp(r'[<>_+\-=]').hasMatch(title)) {
      return 'Characters < > _ + - = are not allowed';
    }
    return null;
  }

  String? _validateDepartment(String dept) {
    if (dept.isEmpty) {
      return 'Enter a department';
    }
    if (dept.length > 100) {
      return 'Department must be at most 100 characters';
    }
    if (RegExp(r'[<>_+\-=]').hasMatch(dept)) {
      return 'Characters < > _ + - = are not allowed';
    }
    return null;
  }

  String? _validateJoiningDate(String dateStr) {
    if (dateStr.trim().isEmpty) {
      return null;
    }
    final trimmed = dateStr.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      return 'Pick a valid date';
    }
    DateTime? parsed;
    try {
      parsed = DateTime.parse(trimmed);
    } catch (_) {
      return 'Pick a valid date';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inputDate = DateTime(parsed.year, parsed.month, parsed.day);
    if (inputDate.isAfter(today)) {
      return "Joining date can't be in the future";
    }
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) {
      return 'Enter a password';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (password.length > 100) {
      return 'Password must be at most 100 characters';
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Password must include at least one number';
    }
    return null;
  }

  String? _validateConfirmPassword(String confirmPassword, String password) {
    if (confirmPassword.isEmpty) {
      return 'Re-enter the password';
    }
    if (confirmPassword != password) {
      return "Passwords don't match";
    }
    return null;
  }

  void _showCreateUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final phoneController = TextEditingController();
    final deptController = TextEditingController();
    final titleController = TextEditingController();
    final joiningDateController = TextEditingController();

    UserRole selectedRole = UserRole.intern;
    String? selectedMentorId;
    List<UserModel> mentors = [];
    bool isLoadingMentors = false;
    bool mentorsRequested = false;
    bool obscurePassword = true;
    bool obscureConfirm = true;
    bool isCreating = false;
    final terms = InternTerms();

    // Field-level error messages
    String? nameError;
    String? emailError;
    String? passwordError;
    String? confirmPasswordError;
    String? phoneError;
    String? deptError;
    String? titleError;
    String? dateError;
    String? apiError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentUser = ref.watch(appStateProvider).currentUser;
          final isMentorActor = currentUser.role == UserRole.mentor;

          // Mentor actor -> intern only; Admin -> intern | mentor (cannot create admin via this form)
          final allowedRoles = isMentorActor
              ? [UserRole.intern]
              : [UserRole.intern, UserRole.mentor];

          // Fetch mentors list via GET /api/admin/users?page=1&page_size=20&role=mentor
          void loadMentorsIfNeeded() async {
            if (!mentorsRequested && selectedRole == UserRole.intern && !isMentorActor) {
              mentorsRequested = true;
              setModalState(() => isLoadingMentors = true);
              List<UserModel> fetched = const [];
              try {
                fetched = await ref.read(appStateProvider.notifier).fetchMentorsForPicker(pageSize: 20);
              } catch (_) {
                // The picker just offers "No mentor"; the admin can assign one later.
              }
              if (ctx.mounted) {
                setModalState(() {
                  mentors = fetched;
                  isLoadingMentors = false;
                });
              }
            }
          }

          loadMentorsIfNeeded();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'New user',
                          style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: isCreating ? null : () => Navigator.pop(ctx),
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // General API Error (only if backend fails)
                  if (apiError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.dangerInk, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              apiError!,
                              style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Full Name (required)
                  CustomTextField(
                    label: 'Full name',
                    hintText: 'e.g. Asha Patel',
                    controller: nameController,
                    errorText: nameError,
                    onChanged: (val) {
                      setModalState(() {
                        nameError = _validateFullName(val.trim());
                      });
                    },
                    prefixIcon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 12),

                  // Email (required)
                  CustomTextField(
                    label: 'Email',
                    hintText: 'asha.patel@example.com',
                    controller: emailController,
                    errorText: emailError,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (val) {
                      setModalState(() {
                        emailError = _validateEmail(val.trim());
                      });
                    },
                    prefixIcon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 12),

                  // Initial Password (required)
                  CustomTextField(
                    label: 'Password',
                    hintText: 'At least 8 characters, with a number',
                    controller: passwordController,
                    errorText: passwordError,
                    obscureText: obscurePassword,
                    prefixIcon: Icons.lock_outline_rounded,
                    onChanged: (val) {
                      setModalState(() {
                        passwordError = _validatePassword(val);
                        if (confirmPasswordController.text.isNotEmpty) {
                          confirmPasswordError = _validateConfirmPassword(confirmPasswordController.text, val);
                        }
                      });
                    },
                    suffixIcon: IconButton(
                      tooltip: obscurePassword ? 'Show password' : 'Hide password',
                      icon: Icon(
                        obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                      onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Confirm Password (FE-only check)
                  CustomTextField(
                    label: 'Confirm password',
                    hintText: 'Re-enter password',
                    controller: confirmPasswordController,
                    errorText: confirmPasswordError,
                    obscureText: obscureConfirm,
                    prefixIcon: Icons.lock_clock_outlined,
                    onChanged: (val) {
                      setModalState(() {
                        confirmPasswordError = _validateConfirmPassword(val, passwordController.text);
                      });
                    },
                    suffixIcon: IconButton(
                      tooltip: obscureConfirm ? 'Show password' : 'Hide password',
                      icon: Icon(
                        obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: AppColors.textTertiary,
                      ),
                      onPressed: () => setModalState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Role
                  Text(
                    'Role',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<UserRole>(
                    initialValue: selectedRole,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surfaceMuted,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    items: allowedRoles.map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Text(
                          r.label,
                          style: AppTypography.bodyStrong.copyWith(color: AppColors.ink),
                        ),
                      );
                    }).toList(),
                    onChanged: isMentorActor
                        ? null
                        : (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedRole = val;
                                if (selectedRole != UserRole.intern) {
                                  selectedMentorId = null;
                                }
                              });
                            }
                          },
                  ),
                  const SizedBox(height: 12),

                  // Mentor Picker (Only for intern; omitted when mentor actor creates)
                  if (selectedRole == UserRole.intern && !isMentorActor) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Mentor (optional)',
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        if (isLoadingMentors)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedMentorId,
                      decoration: InputDecoration(
                        hintText: isLoadingMentors ? 'Loading mentors…' : 'Choose a mentor',
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No mentor'),
                        ),
                        ...mentors.map((m) {
                          return DropdownMenuItem<String?>(
                            value: m.id,
                            child: Text(
                              '${m.name}${m.jobTitle != null && m.jobTitle!.isNotEmpty ? ' (${m.jobTitle})' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setModalState(() => selectedMentorId = val);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (selectedRole == UserRole.intern) ...[
                    InternTermsSection(terms: terms),
                    const SizedBox(height: 12),
                  ],

                  // Phone (Required)
                  CustomTextField(
                    label: 'Mobile number',
                    hintText: '9876543210',
                    controller: phoneController,
                    errorText: phoneError,
                    keyboardType: TextInputType.phone,
                    onChanged: (val) {
                      setModalState(() {
                        phoneError = _validatePhone(val.trim());
                      });
                    },
                    prefixIcon: Icons.phone_outlined,
                  ),
                  const SizedBox(height: 12),

                  // Department (Required - forbids <>_+-=)
                  CustomTextField(
                    label: 'Department',
                    hintText: 'e.g. Engineering',
                    controller: deptController,
                    errorText: deptError,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[<>_+\-=]'))],
                    onChanged: (val) {
                      setModalState(() {
                        deptError = _validateDepartment(val.trim());
                      });
                    },
                    prefixIcon: Icons.apartment_outlined,
                  ),
                  const SizedBox(height: 12),

                  // Job Title (Required - forbids <>_+-=)
                  CustomTextField(
                    label: 'Job title',
                    hintText: 'e.g. Frontend Intern',
                    controller: titleController,
                    errorText: titleError,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[<>_+\-=]'))],
                    onChanged: (val) {
                      setModalState(() {
                        titleError = _validateJobTitle(val.trim());
                      });
                    },
                    prefixIcon: Icons.work_outline_rounded,
                  ),
                  const SizedBox(height: 12),

                  // Joining Date (Optional - YYYY-MM-DD)
                  CustomTextField(
                    label: 'Joining date (optional)',
                    hintText: 'Pick a date',
                    controller: joiningDateController,
                    errorText: dateError,
                    readOnly: true,
                    prefixIcon: Icons.calendar_month_outlined,
                    suffixIcon: joiningDateController.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear date',
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setModalState(() {
                              joiningDateController.clear();
                              dateError = null;
                            }),
                          )
                        : null,
                    onTap: () async {
                      await _selectJoiningDate(context, joiningDateController);
                      setModalState(() {
                        dateError = _validateJoiningDate(joiningDateController.text);
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Create Button
                  CustomButton(
                    text: 'Create user',
                    isLoading: isCreating,
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final email = emailController.text.trim();
                      final password = passwordController.text;
                      final confirmPassword = confirmPasswordController.text;
                      final phone = phoneController.text.trim();
                      final dept = deptController.text.trim();
                      final title = titleController.text.trim();
                      final joiningDate = joiningDateController.text.trim();

                      // Run all validations
                      final nErr = _validateFullName(name);
                      final eErr = _validateEmail(email);
                      final pErr = _validatePassword(password);
                      final cErr = _validateConfirmPassword(confirmPassword, password);
                      final phErr = _validatePhone(phone);
                      final tErr = _validateJobTitle(title);
                      final dErr = _validateDepartment(dept);
                      final dtErr = _validateJoiningDate(joiningDate);

                      setModalState(() {
                        nameError = nErr;
                        emailError = eErr;
                        passwordError = pErr;
                        confirmPasswordError = cErr;
                        phoneError = phErr;
                        titleError = tErr;
                        deptError = dErr;
                        dateError = dtErr;
                        apiError = null;
                      });

                      // If any field error exists, do not proceed
                      if (nErr != null ||
                          eErr != null ||
                          pErr != null ||
                          cErr != null ||
                          phErr != null ||
                          tErr != null ||
                          dErr != null ||
                          dtErr != null) {
                        return;
                      }

                      if (selectedRole == UserRole.intern && terms.problem != null) {
                        setModalState(() => apiError = terms.problem);
                        return;
                      }

                      final nationalPhoneDigits = _extractNationalPhoneDigits(phone)!;

                      setModalState(() {
                        isCreating = true;
                      });

                      final nav = Navigator.of(ctx);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);

                      try {
                        // Build payload matching API specification
                        final payload = <String, dynamic>{
                          'name': name,
                          'email': email,
                          'password': password,
                          'role': selectedRole.toApiValue(),
                          'phone': nationalPhoneDigits,
                          'job_title': title,
                          'department': dept,
                          'joining_date': joiningDate.isNotEmpty ? joiningDate : null,
                          if (selectedRole == UserRole.intern) ...terms.toPayload(),
                        };

                        // Mentor: number or null; only for intern; omitted when mentor creates
                        if (!isMentorActor) {
                          if (selectedRole == UserRole.intern) {
                            payload['mentor_id'] = selectedMentorId != null
                                ? int.tryParse(selectedMentorId!) ?? selectedMentorId
                                : null;
                          } else {
                            payload['mentor_id'] = null;
                          }
                        }

                        await ref.read(appStateProvider.notifier).createUser(payload);
                        nav.pop();
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('$name added')),
                        );
                        if (mounted) {
                          _loadUsers(page: 1);
                        }
                      } catch (e) {
                        setModalState(() {
                          isCreating = false;
                          apiError = apiErrorMessage(e);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Add an account that already exists (e.g. a public sign-up) to this organization.
  void _showAddExistingDialog() {
    final emailController = TextEditingController();
    final isMentorActor = ref.read(appStateProvider).currentUser.role == UserRole.mentor;
    UserRole role = UserRole.intern;
    final terms = InternTerms();
    String? error;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add existing account'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Adds someone who already has an InternHub account (for example a public sign-up) to your organization.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              if (!isMentorActor) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [UserRole.intern, UserRole.mentor, UserRole.admin]
                      .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                      .toList(),
                  onChanged: (v) => setDlg(() => role = v ?? role),
                ),
              ],
              if (role == UserRole.intern) ...[
                const SizedBox(height: 12),
                InternTermsSection(terms: terms),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final email = emailController.text.trim().toLowerCase();
                      if (!email.contains('@')) {
                        setDlg(() => error = "Enter the account's email.");
                        return;
                      }
                      if (role == UserRole.intern && terms.problem != null) {
                        setDlg(() => error = terms.problem);
                        return;
                      }
                      setDlg(() {
                        saving = true;
                        error = null;
                      });
                      final nav = Navigator.of(ctx);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        // The server ignores `name` for an existing account; it is only a required key.
                        await ref.read(appStateProvider.notifier).addOrganizationMember({
                          'name': '',
                          'email': email,
                          'role': role.toApiValue(),
                          if (role == UserRole.intern) ...terms.toPayload(),
                        });
                        nav.pop();
                        messenger.showSnackBar(SnackBar(content: Text('$email added to your organization')));
                        _loadUsers(page: 1);
                      } catch (e) {
                        final message = apiErrorMessage(e);
                        setDlg(() {
                          saving = false;
                          // No account with that email: the server asks for a password to create one.
                          error = message.toLowerCase().contains('password is required')
                              ? 'No InternHub account uses that email. Use "New user" to create one.'
                              : message;
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserDialog(UserModel user) {
    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    final phoneController = TextEditingController(text: user.phone ?? '');
    final deptController = TextEditingController(text: user.department ?? '');
    final titleController = TextEditingController(text: user.jobTitle ?? '');
    final joiningDateController = TextEditingController(text: user.joiningDate ?? '');

    String? selectedMentorId = user.mentorId;
    List<UserModel> mentors = [];
    bool isLoadingMentors = false;
    bool mentorsRequested = false;
    bool isSaving = false;
    UserRole selectedRole = user.role;
    final terms = InternTerms(
      durationMonths: user.internshipDurationMonths,
      isPaid: user.isPaid,
      stipendAmount: user.stipendAmount,
    );

    // Field-level error messages
    String? nameError;
    String? emailError;
    String? phoneError;
    String? deptError;
    String? titleError;
    String? dateError;
    String? apiError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {

          // Fetch mentors list via GET /api/admin/users?page=1&page_size=20&role=mentor
          void loadMentorsIfNeeded() async {
            if (!mentorsRequested && selectedRole == UserRole.intern) {
              mentorsRequested = true;
              setModalState(() => isLoadingMentors = true);
              List<UserModel> fetched = const [];
              try {
                fetched = await ref.read(appStateProvider.notifier).fetchMentorsForPicker(pageSize: 20);
              } catch (_) {
                // Keep the current mentor selectable even if the list fails.
              }
              if (ctx.mounted) {
                setModalState(() {
                  mentors = fetched;
                  isLoadingMentors = false;
                });
              }
            }
          }

          loadMentorsIfNeeded();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit ${user.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                            ),
                            Text(user.role.label, style: AppTypography.caption.copyWith(color: AppColors.primaryInk)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: isSaving ? null : () => Navigator.pop(ctx),
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // General API Error (only if backend fails)
                  if (apiError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.dangerInk, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              apiError!,
                              style: AppTypography.caption.copyWith(color: AppColors.dangerInk),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Full Name (required)
                  CustomTextField(
                    label: 'Full name',
                    hintText: 'e.g. Asha Patel',
                    controller: nameController,
                    errorText: nameError,
                    onChanged: (val) {
                      setModalState(() {
                        nameError = _validateFullName(val.trim());
                      });
                    },
                    prefixIcon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 12),

                  // Email (required)
                  CustomTextField(
                    label: 'Email',
                    hintText: 'asha.patel@example.com',
                    controller: emailController,
                    errorText: emailError,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (val) {
                      setModalState(() {
                        emailError = _validateEmail(val.trim());
                      });
                    },
                    prefixIcon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 12),

                  // Mentor Picker (Only for intern)
                  if (selectedRole == UserRole.intern) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Mentor (optional)',
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                        ),
                        if (isLoadingMentors)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: selectedMentorId,
                      decoration: InputDecoration(
                        hintText: isLoadingMentors ? 'Loading mentors…' : 'Choose a mentor',
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('No mentor'),
                        ),
                        ...mentors.map((m) {
                          return DropdownMenuItem<String?>(
                            value: m.id,
                            child: Text(
                              '${m.name}${m.jobTitle != null && m.jobTitle!.isNotEmpty ? ' (${m.jobTitle})' : ''}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                        if (selectedMentorId != null && !mentors.any((m) => m.id == selectedMentorId))
                          DropdownMenuItem<String?>(
                            value: selectedMentorId,
                            child: Text(user.mentorName ?? 'Current mentor', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (val) {
                        setModalState(() => selectedMentorId = val);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Role (admins only, never their own account)
                  if (ref.read(appStateProvider).currentUser.isAdmin && ref.read(appStateProvider).currentUser.id != user.id) ...[
                    Text('Role', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<UserRole>(
                      initialValue: selectedRole == UserRole.superadmin ? UserRole.admin : selectedRole,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      items: const [UserRole.intern, UserRole.mentor, UserRole.admin]
                          .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                          .toList(),
                      onChanged: (val) => setModalState(() => selectedRole = val ?? selectedRole),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (selectedRole == UserRole.intern) ...[
                    InternTermsSection(terms: terms),
                    const SizedBox(height: 12),
                  ],

                  // Phone (Required)
                  CustomTextField(
                    label: 'Mobile number',
                    hintText: '9876543210',
                    controller: phoneController,
                    errorText: phoneError,
                    keyboardType: TextInputType.phone,
                    onChanged: (val) {
                      setModalState(() {
                        phoneError = _validatePhone(val.trim());
                      });
                    },
                    prefixIcon: Icons.phone_outlined,
                  ),
                  const SizedBox(height: 12),

                  // Department (Required - forbids <>_+-=)
                  CustomTextField(
                    label: 'Department',
                    hintText: 'e.g. Engineering',
                    controller: deptController,
                    errorText: deptError,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[<>_+\-=]'))],
                    onChanged: (val) {
                      setModalState(() {
                        deptError = _validateDepartment(val.trim());
                      });
                    },
                    prefixIcon: Icons.apartment_outlined,
                  ),
                  const SizedBox(height: 12),

                  // Job Title (Required - forbids <>_+-=)
                  CustomTextField(
                    label: 'Job title',
                    hintText: 'e.g. Frontend Intern',
                    controller: titleController,
                    errorText: titleError,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[<>_+\-=]'))],
                    onChanged: (val) {
                      setModalState(() {
                        titleError = _validateJobTitle(val.trim());
                      });
                    },
                    prefixIcon: Icons.work_outline_rounded,
                  ),
                  const SizedBox(height: 12),

                  // Joining Date (Optional - YYYY-MM-DD)
                  CustomTextField(
                    label: 'Joining date (optional)',
                    hintText: 'Pick a date',
                    controller: joiningDateController,
                    errorText: dateError,
                    readOnly: true,
                    prefixIcon: Icons.calendar_month_outlined,
                    suffixIcon: joiningDateController.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear date',
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setModalState(() {
                              joiningDateController.clear();
                              dateError = null;
                            }),
                          )
                        : null,
                    onTap: () async {
                      await _selectJoiningDate(context, joiningDateController);
                      setModalState(() {
                        dateError = _validateJoiningDate(joiningDateController.text);
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Save Changes Button (PUT /api/admin/users/{id} - No password)
                  CustomButton(
                    text: 'Save changes',
                    isLoading: isSaving,
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final email = emailController.text.trim();
                      final phone = phoneController.text.trim();
                      final dept = deptController.text.trim();
                      final title = titleController.text.trim();
                      final joiningDate = joiningDateController.text.trim();

                      // Run all validations
                      final nErr = _validateFullName(name);
                      final eErr = _validateEmail(email);
                      final phErr = _validatePhone(phone);
                      final tErr = _validateJobTitle(title);
                      final dErr = _validateDepartment(dept);
                      final dtErr = _validateJoiningDate(joiningDate);

                      setModalState(() {
                        nameError = nErr;
                        emailError = eErr;
                        phoneError = phErr;
                        titleError = tErr;
                        deptError = dErr;
                        dateError = dtErr;
                        apiError = null;
                      });

                      // If any field error exists, do not proceed
                      if (nErr != null ||
                          eErr != null ||
                          phErr != null ||
                          tErr != null ||
                          dErr != null ||
                          dtErr != null) {
                        return;
                      }

                      if (selectedRole == UserRole.intern && terms.problem != null) {
                        setModalState(() => apiError = terms.problem);
                        return;
                      }

                      final nationalPhoneDigits = _extractNationalPhoneDigits(phone)!;

                      if (selectedRole == UserRole.admin && user.role != UserRole.admin && user.role != UserRole.superadmin) {
                        final ok = await _confirm(
                          title: 'Make ${user.name} an admin?',
                          body: 'Admins can manage every user, project and setting in your organization.',
                          action: 'Make admin',
                        );
                        if (!ok || !ctx.mounted || !context.mounted) return;
                      }

                      setModalState(() {
                        isSaving = true;
                      });

                      final nav = Navigator.of(ctx);
                      final scaffoldMessenger = ScaffoldMessenger.of(context);

                      try {
                        // PUT /api/admin/users/{id} payload (no password)
                        final payload = <String, dynamic>{
                          'name': name,
                          'email': email,
                          'phone': nationalPhoneDigits,
                          'job_title': title,
                          'department': dept,
                          'joining_date': joiningDate.isNotEmpty ? joiningDate : null,
                          if (selectedRole == UserRole.intern) ...terms.toPayload(),
                        };

                        if (selectedRole == UserRole.intern) {
                          payload['mentor_id'] = selectedMentorId != null
                              ? int.tryParse(selectedMentorId!) ?? selectedMentorId
                              : null;
                        }

                        // Role first: the server only accepts intern terms (duration, stipend) for an intern.
                        if (selectedRole != user.role && !(user.role == UserRole.superadmin && selectedRole == UserRole.admin)) {
                          await ref.read(appStateProvider.notifier).changeUserRole(user.id, selectedRole);
                        }
                        await ref.read(appStateProvider.notifier).updateUser(user.id, payload);
                        nav.pop();
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('$name updated')),
                        );
                        if (mounted) {
                          _loadUsers();
                        }
                      } catch (e) {
                        setModalState(() {
                          isSaving = false;
                          apiError = apiErrorMessage(e);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirm({required String title, required String body, required String action, bool destructive = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: destructive
                ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmDeleteUser(UserModel user) async {
    final ok = await _confirm(
      title: 'Delete ${user.name}?',
      body: 'They lose access right away. You can restore them from the recycle bin.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider.notifier).deleteUser(user.id);
      messenger.showSnackBar(SnackBar(content: Text('${user.name} moved to the recycle bin')));
      if (mounted) _loadUsers();
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't delete ${user.name}");
    }
  }

  Future<void> _toggleUserActive(UserModel user) async {
    if (user.isActive) {
      final ok = await _confirm(
        title: 'Deactivate ${user.name}?',
        body: "They won't be able to sign in until you activate them again.",
        action: 'Deactivate',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider.notifier).toggleUserActive(user.id);
      messenger.showSnackBar(
        SnackBar(content: Text(user.isActive ? '${user.name} deactivated' : '${user.name} activated')),
      );
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't update ${user.name}");
    }
  }

  void _showUserActions(UserModel u, {required bool isAdmin, required String currentUserId}) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('View profile'),
              onTap: () {
                Navigator.pop(ctx);
                User360ProfileDialog.show(context, userId: u.id, fallbackUser: u);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditUserDialog(u);
              },
            ),
            if (u.id != currentUserId)
              ListTile(
                leading: Icon(u.isActive ? Icons.block_flipped : Icons.check_circle_outline),
                title: Text(u.isActive ? 'Deactivate' : 'Activate'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleUserActive(u);
                },
              ),
            if (isAdmin && u.id != currentUserId)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: AppColors.dangerInk),
                title: const Text('Delete', style: TextStyle(color: AppColors.dangerInk)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteUser(u);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('New user'),
              subtitle: const Text('Create an account with a password'),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateUserDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Add existing account'),
              subtitle: const Text('Someone who already uses InternHub'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddExistingDialog();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _userCard(UserModel u, {required bool isAdmin, required String currentUserId}) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppSpacing.rTile), boxShadow: AppShadows.soft),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.rTile),
          onTap: () => User360ProfileDialog.show(context, userId: u.id, fallbackUser: u),
          onLongPress: () => _showUserActions(u, isAdmin: isAdmin, currentUserId: currentUserId),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              children: [
                AppAvatar(url: u.avatarUrl, fallbackText: u.name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if ((u.department ?? '').isNotEmpty) u.department! else u.email,
                          if ((u.mentorName ?? '').isNotEmpty) 'Mentor: ${u.mentorName}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          StatusChip(label: u.role.label, statusType: StatusType.neutral),
                          if (!u.isActive) StatusChip(label: 'Inactive', statusType: StatusType.warning),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Actions for ${u.name}',
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () => _showUserActions(u, isAdmin: isAdmin, currentUserId: currentUserId),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final currentUser = state.currentUser;
    final isAdmin = currentUser.role == UserRole.admin || currentUser.role == UserRole.superadmin;

    List<UserModel> filtered = state.allUsers.where((u) {
      if (_selectedRoleFilter != 'all' && u.role.toApiValue() != _selectedRoleFilter) {
        return false;
      }
      final q = _searchController.text.toLowerCase().trim();
      if (q.isNotEmpty) {
        return u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    final filterPillOptions = ['All', 'Interns', 'Mentors', 'Admins'];
    int currentPillIndex = 0;
    if (_selectedRoleFilter == 'intern') {
      currentPillIndex = 1;
    } else if (_selectedRoleFilter == 'mentor') {
      currentPillIndex = 2;
    } else if (_selectedRoleFilter == 'admin') {
      currentPillIndex = 3;
    }
    final hasQuery = _searchController.text.trim().isNotEmpty;

    Widget list;
    if (_isLoading && filtered.isEmpty) {
      list = const Center(child: CircularProgressIndicator());
    } else if (state.usersError != null && filtered.isEmpty) {
      list = LoadErrorView(
        title: "Couldn't load users",
        message: state.usersError!,
        onRetry: () => _loadUsers(page: _currentPage),
      );
    } else if (filtered.isEmpty) {
      list = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.person_search_outlined, size: 54, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            hasQuery ? 'Nobody matches "${_searchController.text.trim()}"' : (isAdmin ? 'No users yet' : 'No interns yet'),
            textAlign: TextAlign.center,
            style: AppTypography.cardTitle.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            hasQuery ? 'Try another name or email.' : 'Tap + to add someone.',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
        ],
      );
    } else {
      list = ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 4, AppSpacing.p20, 16),
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _userCard(filtered[i], isAdmin: isAdmin, currentUserId: currentUser.id),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
              child: PageHeader(
                title: isAdmin ? 'Users' : 'My interns',
                subtitle: _totalUsers > 0 ? plural(_totalUsers, isAdmin ? 'person' : 'intern', isAdmin ? 'people' : null) : null,
                padding: EdgeInsets.zero,
                actions: [
                  HeaderAction(icon: Icons.add_rounded, tooltip: 'Add user', onTap: _showAddMenu),
                ],
              ),
            ),
            // Search stays visible so an active query is never hidden.
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 0, AppSpacing.p20, 10),
              child: TextField(
                controller: _searchController,
                onChanged: (v) {
                  setState(() {});
                  _onSearchChanged(v);
                },
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: isAdmin ? 'Search by name or email' : 'Search your interns',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: hasQuery
                      ? IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                            _loadUsers(page: 1);
                          },
                        )
                      : null,
                ),
              ),
            ),
            // Mentors only ever see interns, so role filters are for admins.
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 0, AppSpacing.p20, 10),
                child: PillFilter(
                  options: filterPillOptions,
                  selectedIndex: currentPillIndex,
                  onSelected: (index) {
                    const filters = ['all', 'intern', 'mentor', 'admin'];
                    setState(() {
                      _selectedRoleFilter = filters[index];
                      _currentPage = 1;
                    });
                    _loadUsers(page: 1);
                  },
                ),
              ),
            if (_isLoading && filtered.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _loadUsers(),
                child: list,
              ),
            ),
            PaginationBar(
              page: _currentPage,
              totalPages: _totalPages,
              totalItems: _totalUsers,
              itemLabel: 'users',
              isLoading: _isLoading,
              onPageChanged: (p) => _loadUsers(page: p),
            ),
          ],
        ),
      ),
    );
  }
}
