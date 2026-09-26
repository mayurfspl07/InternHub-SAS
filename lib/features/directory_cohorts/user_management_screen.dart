import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/user_360_profile_dialog.dart';
import '../../shared/widgets/reference_components.dart';

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
        return Theme(
          data: ThemeData.light().copyWith(
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
              color: Colors.white,
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
                        color: Colors.black12,
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
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.ink,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
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
                        color: AppColors.textTertiary,
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
                        color: AppColors.textTertiary,
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
                      color: AppColors.ink,
                    ),
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
                          r.toApiValue().toUpperCase(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
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
                            color: AppColors.ink,
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
              color: Colors.white,
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
                        color: Colors.black12,
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
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.ink,
                            ),
                          ),
                          Text(
                            user.role.toApiValue().toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryInk,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
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
                            color: AppColors.ink,
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
          style: TextStyle(fontWeight: FontWeight.bold),
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

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: PageHeader(
                    title: 'User Directory',
                    subtitle: 'Interns, mentors and admins',
                    padding: EdgeInsets.zero,
                    actions: [
                      HeaderAction(
                        icon: Icons.search_rounded,
                        tooltip: 'Search members',
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            builder: (ctx) => Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: _searchController,
                                    autofocus: true,
                                    onChanged: _onSearchChanged,
                                    decoration: const InputDecoration(
                                      hintText: 'Search members...',
                                      prefixIcon: Icon(Icons.search_rounded),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // Horizontal Pill Filters (All, Interns, Mentors, Admins)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 4, AppSpacing.p20, 12),
                  child: PillFilter(
                    options: filterPillOptions,
                    selectedIndex: currentPillIndex,
                    onSelected: (index) {
                      String newFilter = 'all';
                      if (index == 1) {
                        newFilter = 'intern';
                      } else if (index == 2) {
                        newFilter = 'mentor';
                      } else if (index == 3) {
                        newFilter = 'admin';
                      }
                      setState(() {
                        _selectedRoleFilter = newFilter;
                        _currentPage = 1;
                      });
                      _loadUsers(page: 1);
                    },
                  ),
                ),

                // 2-Column Grid Layout matching Image 1
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
                                    Icon(Icons.person_search_outlined, size: 54, color: Colors.black26),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No users found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Try adjusting your search or filters',
                                      style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                                    ),
                                  ],
                                ),
                              )
                            : GridView.builder(
                                padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 6, AppSpacing.p20, 90),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  childAspectRatio: 0.90,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (context, i) {
                                  final u = filtered[i];
                                  final isFeatured = (i % 3 == 2);
                                  final metricVal = u.role == UserRole.mentor
                                      ? '\$350,500'
                                      : (i % 2 == 0 ? '\$120,100' : '\$80,320');

                                  return GestureDetector(
                                    onLongPress: () {
                                      showModalBottomSheet(
                                        context: context,
                                        backgroundColor: Colors.white,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                        ),
                                        builder: (ctx) => SafeArea(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ListTile(
                                                  leading: const Icon(Icons.visibility_outlined),
                                                  title: const Text('View 360° Profile'),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    User360ProfileDialog.show(context, userId: u.id, fallbackUser: u);
                                                  },
                                                ),
                                                ListTile(
                                                  leading: const Icon(Icons.edit_outlined),
                                                  title: const Text('Edit User'),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    _showEditUserDialog(u);
                                                  },
                                                ),
                                                ListTile(
                                                  leading: Icon(u.isActive ? Icons.block_flipped : Icons.check_circle_outline),
                                                  title: Text(u.isActive ? 'Deactivate User' : 'Activate User'),
                                                  onTap: () {
                                                    Navigator.pop(ctx);
                                                    _toggleUserActive(u);
                                                  },
                                                ),
                                                if (isAdmin && u.id != currentUser.id)
                                                  ListTile(
                                                    leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                                                    title: const Text('Delete User', style: TextStyle(color: AppColors.danger)),
                                                    onTap: () {
                                                      Navigator.pop(ctx);
                                                      _confirmDeleteUser(u);
                                                    },
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    child: GridFeatureCard(
                                      title: u.name,
                                      subtitle: u.department != null && u.department!.isNotEmpty
                                          ? u.department
                                          : (u.role == UserRole.intern ? 'Chemical Machinery & Orbi' : 'Tech Solutions, Inc.'),
                                      metricValue: metricVal,
                                      metricLabel: 'Total in Pipeline',
                                      avatarUrl: u.avatarUrl,
                                      initials: u.name.isNotEmpty ? u.name[0].toUpperCase() : 'U',
                                      isFeaturedYellow: isFeatured,
                                      onTap: () => User360ProfileDialog.show(context, userId: u.id, fallbackUser: u),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),

            // Floating Mini Action Capsule matching Screen 1 bottom floating dock
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingMiniActionCapsule(
                  onSettingsTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Filter settings updated'),
                        behavior: SnackBarBehavior.floating,
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  onAddTap: _showCreateUserDialog,
                  onEditTap: () {
                    if (filtered.isNotEmpty) {
                      _showEditUserDialog(filtered.first);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: AppColors.border,
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
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
                            ? AppColors.border
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
                              ? AppColors.ink
                              : Colors.black26,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'Prev',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _currentPage > 1 && !_isLoading
                                ? AppColors.ink
                                : Colors.black26,
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
                        color: AppColors.onPrimary,
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
                            ? AppColors.border
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
                                ? AppColors.ink
                                : Colors.black26,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _currentPage < _totalPages && !_isLoading
                              ? AppColors.ink
                              : Colors.black26,
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
