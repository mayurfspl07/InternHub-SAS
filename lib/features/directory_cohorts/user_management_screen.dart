import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/user_360_profile_dialog.dart';

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
    _loadUsers();
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

    final result = await ref.read(appStateProvider.notifier).fetchUsers(
      role: roleParam,
      search: searchParam,
      page: _currentPage,
      pageSize: _pageSize,
    );
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
    if (controller.text.trim().isNotEmpty) {
      try {
        final parsed = DateTime.parse(controller.text.trim());
        if (!parsed.isAfter(today)) {
          initial = parsed;
        }
      } catch (_) {}
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: today,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.primary,
                    surface: AppColors.surfaceDark,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: AppColors.primary,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  String? _validateFullName(String name) {
    if (name.isEmpty) {
      return 'Full name is required';
    }
    if (name.length < 2) {
      return 'Full name must be at least 2 characters';
    }
    if (name.length > 100) {
      return 'Full name must be at most 100 characters';
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
      return "Full name can only contain letters, spaces, and - ' .";
    }
    return null;
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) {
      return 'Email is required';
    }
    if (email.length > 254) {
      return 'Email must be at most 254 characters';
    }
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(email)) {
      return 'Please enter a valid email address';
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
      return 'Phone number is required';
    }
    if (_extractNationalPhoneDigits(phone) == null) {
      return 'Invalid phone number';
    }
    return null;
  }

  String? _validateJobTitle(String title) {
    if (title.isEmpty) {
      return 'Job title is required';
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
      return 'Department is required';
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
      return 'Please enter a valid date';
    }
    DateTime? parsed;
    try {
      parsed = DateTime.parse(trimmed);
    } catch (_) {
      return 'Please enter a valid date';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final inputDate = DateTime(parsed.year, parsed.month, parsed.day);
    if (inputDate.isAfter(today)) {
      return 'Joining date cannot be in the future';
    }
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) {
      return 'Password is required';
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
      return 'Please confirm your password';
    }
    if (confirmPassword != password) {
      return 'Passwords do not match';
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
    bool obscurePassword = true;
    bool obscureConfirm = true;
    bool isCreating = false;

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
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final currentUser = ref.watch(appStateProvider).currentUser;
          final isMentorActor = currentUser.role == UserRole.mentor;

          // Mentor actor -> intern only; Admin -> intern | mentor (cannot create admin via this form)
          final allowedRoles = isMentorActor
              ? [UserRole.intern]
              : [UserRole.intern, UserRole.mentor];

          // Fetch mentors list via GET /api/admin/users?page=1&page_size=20&role=mentor
          void loadMentorsIfNeeded() async {
            if (mentors.isEmpty && !isLoadingMentors && selectedRole == UserRole.intern && !isMentorActor) {
              setModalState(() => isLoadingMentors = true);
              final fetched = await ref.read(appStateProvider.notifier).fetchMentorsForPicker(pageSize: 20);
              setModalState(() {
                mentors = fetched;
                isLoadingMentors = false;
              });
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
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Create New User',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // General API Error (only if backend fails)
                  if (apiError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              apiError!,
                              style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Full Name (required)
                  CustomTextField(
                    label: 'Full Name *',
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
                    label: 'Email Address *',
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
                    label: 'Initial Password *',
                    hintText: 'Min 8 chars',
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
                      icon: Icon(
                        obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                      onPressed: () => setModalState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Confirm Password (FE-only check)
                  CustomTextField(
                    label: 'Confirm Password *',
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
                      icon: Icon(
                        obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                      onPressed: () => setModalState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Role
                  Text(
                    'Assigned Role *',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<UserRole>(
                    initialValue: selectedRole,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
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
                          r.toApiValue().toUpperCase(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
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
                          'Assign Mentor (Optional)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                          ),
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
                        hintText: isLoadingMentors ? 'Loading mentors...' : 'Select Mentor (or None)',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None (Unassigned)'),
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

                  // Phone (Required)
                  CustomTextField(
                    label: 'Phone *',
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
                    label: 'Department *',
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
                    label: 'Job Title *',
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
                    label: 'Joining Date (Optional)',
                    hintText: 'YYYY-MM-DD (e.g. 2026-09-01)',
                    controller: joiningDateController,
                    errorText: dateError,
                    readOnly: true,
                    prefixIcon: Icons.calendar_month_outlined,
                    suffixIcon: joiningDateController.text.isNotEmpty
                        ? IconButton(
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
                    text: 'Create User',
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
                          SnackBar(
                            content: Text('User $name created successfully'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        if (mounted) {
                          _loadUsers(page: 1);
                        }
                      } catch (e) {
                        setModalState(() {
                          isCreating = false;
                          apiError = e.toString().replaceAll('ApiException: ', '');
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
    bool isSaving = false;

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
          final isDark = Theme.of(context).brightness == Brightness.dark;

          // Fetch mentors list via GET /api/admin/users?page=1&page_size=20&role=mentor
          void loadMentorsIfNeeded() async {
            if (mentors.isEmpty && !isLoadingMentors && user.role == UserRole.intern) {
              setModalState(() => isLoadingMentors = true);
              final fetched = await ref.read(appStateProvider.notifier).fetchMentorsForPicker(pageSize: 20);
              setModalState(() {
                mentors = fetched;
                isLoadingMentors = false;
              });
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
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Edit User',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                            ),
                          ),
                          Text(
                            user.role.toApiValue().toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // General API Error (only if backend fails)
                  if (apiError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              apiError!,
                              style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Full Name (required)
                  CustomTextField(
                    label: 'Full Name *',
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
                    label: 'Email Address *',
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
                  if (user.role == UserRole.intern) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Assign Mentor (Optional)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                          ),
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
                        hintText: isLoadingMentors ? 'Loading mentors...' : 'Select Mentor (or None)',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('None (Unassigned)'),
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

                  // Phone (Required)
                  CustomTextField(
                    label: 'Phone *',
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
                    label: 'Department *',
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
                    label: 'Job Title *',
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
                    label: 'Joining Date (Optional)',
                    hintText: 'YYYY-MM-DD (e.g. 2026-09-01)',
                    controller: joiningDateController,
                    errorText: dateError,
                    readOnly: true,
                    prefixIcon: Icons.calendar_month_outlined,
                    suffixIcon: joiningDateController.text.isNotEmpty
                        ? IconButton(
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
                    text: 'Save Changes',
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

                      final nationalPhoneDigits = _extractNationalPhoneDigits(phone)!;

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
                        };

                        if (user.role == UserRole.intern) {
                          payload['mentor_id'] = selectedMentorId != null
                              ? int.tryParse(selectedMentorId!) ?? selectedMentorId
                              : null;
                        }

                        await ref.read(appStateProvider.notifier).updateUser(user.id, payload);
                        nav.pop();
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text('User $name updated successfully'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        if (mounted) {
                          _loadUsers();
                        }
                      } catch (e) {
                        setModalState(() {
                          isSaving = false;
                          apiError = e.toString().replaceAll('ApiException: ', '');
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

  void _confirmDeleteUser(UserModel user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete User',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Text('Are you sure you want to delete ${user.name}? This user will be moved to the Recycle Bin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(appStateProvider.notifier).deleteUser(user.id);
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('${user.name} moved to Recycle Bin'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete: $e'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleUserActive(UserModel user) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider.notifier).toggleUserActive(user.id);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('${user.name} is now ${user.isActive ? 'deactivated' : 'activated'}'),
          backgroundColor: user.isActive ? AppColors.warning : AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to toggle active status: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = state.currentUser;
    final isAdmin = currentUser.role == UserRole.admin || currentUser.role == UserRole.superadmin;
    final title = isAdmin ? 'User Management' : 'My Interns';

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

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Add User',
            icon: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary),
            onPressed: _showCreateUserDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search by name or email...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _currentPage = 1;
                                _loadUsers(page: 1);
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                if (isAdmin) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedRoleFilter,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down_rounded),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'intern', child: Text('Interns')),
                        DropdownMenuItem(value: 'mentor', child: Text('Mentors')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedRoleFilter = val;
                            _currentPage = 1;
                          });
                          _loadUsers(page: 1);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Users Count Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _totalUsers > 0
                      ? 'Showing ${filtered.length} of $_totalUsers users'
                      : '${filtered.length} ${filtered.length == 1 ? 'user' : 'users'} found',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          // User Cards List
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadUsers,
              child: _isLoading && filtered.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_search_outlined, size: 54, color: isDark ? Colors.white24 : Colors.black26),
                              const SizedBox(height: 12),
                              Text(
                                'No users found',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Try adjusting your search or filters',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final u = filtered[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () => User360ProfileDialog.show(context, userId: u.id, fallbackUser: u),
                                        child: AppAvatar(url: u.avatarUrl, size: 46, fallbackText: u.name),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () => User360ProfileDialog.show(context, userId: u.id, fallbackUser: u),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                u.name,
                                                style: GoogleFonts.outfit(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                u.email,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  StatusChip(
                                                    label: u.role.toApiValue().toUpperCase(),
                                                    statusType: u.role == UserRole.mentor
                                                        ? StatusType.warning
                                                        : u.role == UserRole.admin
                                                            ? StatusType.info
                                                            : StatusType.primary,
                                                  ),
                                                  StatusChip(
                                                    label: u.isActive ? 'ACTIVE' : 'INACTIVE',
                                                    statusType: u.isActive ? StatusType.success : StatusType.neutral,
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        icon: const Icon(Icons.more_vert_rounded),
                                        onSelected: (action) {
                                          if (action == 'preview') {
                                            User360ProfileDialog.show(context, userId: u.id, fallbackUser: u);
                                          } else if (action == 'edit') {
                                            _showEditUserDialog(u);
                                          } else if (action == 'toggle') {
                                            _toggleUserActive(u);
                                          } else if (action == 'delete') {
                                            _confirmDeleteUser(u);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'preview',
                                            child: Row(
                                              children: [
                                                Icon(Icons.visibility_outlined, size: 18),
                                                SizedBox(width: 8),
                                                Text('360° Profile'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit_outlined, size: 18),
                                                SizedBox(width: 8),
                                                Text('Edit User'),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'toggle',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  u.isActive ? Icons.block_flipped : Icons.check_circle_outline,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Text(u.isActive ? 'Deactivate' : 'Activate'),
                                              ],
                                            ),
                                          ),
                                          if (isAdmin && u.id != currentUser.id)
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                                                  SizedBox(width: 8),
                                                  Text('Delete User', style: TextStyle(color: AppColors.danger)),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  // Additional Enriched Info Rows
                                  if (u.role == UserRole.intern ||
                                      (u.jobTitle != null && u.jobTitle!.isNotEmpty) ||
                                      (u.department != null && u.department!.isNotEmpty) ||
                                      (u.joiningDate != null && u.joiningDate!.isNotEmpty)) ...[
                                    const SizedBox(height: 10),
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),

                                    // Intern Mentor Enrichment Display
                                    if (u.role == UserRole.intern)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.school_outlined,
                                              size: 15,
                                              color: u.mentorName != null ? AppColors.primary : Colors.grey,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Mentor: ',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.white70 : Colors.black87,
                                              ),
                                            ),
                                            Text(
                                              u.mentorName ?? 'Unassigned',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: u.mentorName != null
                                                    ? (isDark ? Colors.white : AppColors.primary)
                                                    : Colors.grey,
                                                fontStyle: u.mentorName == null ? FontStyle.italic : FontStyle.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // Department / Job Title
                                    if ((u.jobTitle != null && u.jobTitle!.isNotEmpty) ||
                                        (u.department != null && u.department!.isNotEmpty))
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.work_outline, size: 14, color: Colors.grey),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                [
                                                  if (u.jobTitle != null && u.jobTitle!.isNotEmpty) u.jobTitle!,
                                                  if (u.department != null && u.department!.isNotEmpty) u.department!,
                                                ].join(' • '),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark ? Colors.white60 : Colors.grey.shade700,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // Joining Date
                                    if (u.joiningDate != null && u.joiningDate!.isNotEmpty)
                                      Row(
                                        children: [
                                          const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Joined: ${u.joiningDate}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white38 : Colors.black45,
                                            ),
                                          ),
                                        ],
                                      ),
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
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark ? AppColors.borderDark : AppColors.borderLight,
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Page info
              Text(
                'Page $_currentPage of $_totalPages${_totalUsers > 0 ? ' ($_totalUsers total)' : ''}',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                ),
              ),

              // Navigation controls
              Row(
                children: [
                  // Previous button
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(
                        color: _currentPage > 1 && !_isLoading
                            ? (isDark ? AppColors.borderDark : AppColors.borderLight)
                            : Colors.transparent,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _currentPage > 1 && !_isLoading
                        ? () => _loadUsers(page: _currentPage - 1)
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chevron_left_rounded,
                          size: 18,
                          color: _currentPage > 1 && !_isLoading
                              ? (isDark ? Colors.white : AppColors.textPrimaryLight)
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Prev',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _currentPage > 1 && !_isLoading
                                ? (isDark ? Colors.white : AppColors.textPrimaryLight)
                                : (isDark ? Colors.white24 : Colors.black26),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Current Page Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$_currentPage',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Next button
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(
                        color: _currentPage < _totalPages && !_isLoading
                            ? (isDark ? AppColors.borderDark : AppColors.borderLight)
                            : Colors.transparent,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _currentPage < _totalPages && !_isLoading
                        ? () => _loadUsers(page: _currentPage + 1)
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Next',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _currentPage < _totalPages && !_isLoading
                                ? (isDark ? Colors.white : AppColors.textPrimaryLight)
                                : (isDark ? Colors.white24 : Colors.black26),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _currentPage < _totalPages && !_isLoading
                              ? (isDark ? Colors.white : AppColors.textPrimaryLight)
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
