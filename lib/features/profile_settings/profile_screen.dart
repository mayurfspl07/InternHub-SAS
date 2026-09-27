import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_config.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/profile_overview_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/load_error_view.dart';
import 'change_password_dialog.dart';
import 'profile_repository.dart';
import 'settings_screen.dart';
import 'widgets/edit_profile_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const ProfileScreen({super.key, this.showBackButton = false});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ProfileRepository _repository = ProfileRepository();

  UserModel? _profileUser;
  UserProfileOverview? _overview;

  bool _isLoadingProfile = true;
  bool _isLoadingOverview = false;
  String? _errorMessage;

  UserModel get _activeUser => _profileUser ?? ref.read(appStateProvider).currentUser;
  bool get _isIntern => _activeUser.role == UserRole.intern;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() {
      _isLoadingProfile = true;
      _errorMessage = null;
    });

    try {
      final user = await _repository.getProfile();
      if (mounted) {
        setState(() {
          _profileUser = user;
          _isLoadingProfile = false;
        });

        // Query 2: GET /api/users/{id}/overview (interns and mentors get real stats there)
        if ((user.role == UserRole.intern || user.role == UserRole.mentor) && user.id.isNotEmpty) {
          _loadInternOverview(user.id);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _loadInternOverview(String userId) async {
    setState(() => _isLoadingOverview = true);
    try {
      final ov = await _repository.getUserOverview(userId);
      if (mounted) {
        setState(() {
          _overview = ov;
          _isLoadingOverview = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingOverview = false);
      }
    }
  }

  void _openEditDialog() {
    EditProfileDialog.show(
      context,
      user: _activeUser,
      onSuccess: (updated) {
        setState(() => _profileUser = updated);
        ref.read(appStateProvider.notifier).fetchCurrentUser();
      },
    );
  }

  void _confirmLogout() {

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.r28),
        ),
        title: const Text('Are you sure?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
          'You will be logged out from your account and returned to the login screen.',
          style: TextStyle(fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rPill),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(appStateProvider.notifier).logout();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _changePhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(appStateProvider.notifier).uploadAvatar(File(picked.path));
      if (mounted) setState(() => _profileUser = _profileUser?.copyWith(avatarUrl: ref.read(appStateProvider).currentUser.avatarUrl));
      messenger.showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: 'Could not upload the photo');
    }
  }

  /// Header numbers straight from GET /api/users/{id}/overview `stats`.
  List<(String, String)> _headerStats(UserModel user) {
    final stats = _overview?.stats ?? const {};
    String v(String key) => stats[key] == null ? '–' : stats[key].toString();
    if (user.role == UserRole.intern) {
      return [(v('active_tasks'), 'Open tasks'), (v('projects'), 'Projects'), (v('present_30d'), 'Days present (30d)')];
    }
    if (user.role == UserRole.mentor) {
      return [(v('interns'), 'Interns'), (v('projects'), 'Projects'), (v('tasks_assigned'), 'Tasks')];
    }
    return const [];
  }

  Widget _buildHeaderCard(Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor) {
    final user = _activeUser;
    final initial = user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';
    final headerStats = _headerStats(user);
    final avatarUrl = user.avatarUrl ?? ref.watch(appStateProvider).currentUser.avatarUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Centered Profile Card (Screen 14 in Reference UI)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppSpacing.r28),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            children: [
              // Centered Avatar with Edit camera badge
              Stack(
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: AppColors.primary,
                    backgroundImage: avatarUrl != null ? NetworkImage(ApiConfig.mediaUrl(avatarUrl)) : null,
                    child: avatarUrl != null
                        ? null
                        : Text(
                            initial,
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: AppColors.warningInk,
                            ),
                          ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _changePhoto,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: cardBg, width: 2.5),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Name
              Text(
                user.name,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: primaryTextColor,
                ),
              ),
              const SizedBox(height: 4),

              // Role & Department Subtitle
              Text(
                [user.roleTitle, if ((user.department ?? '').isNotEmpty) user.department!].join(' • '),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: secondaryTextColor,
                ),
              ),
              const SizedBox(height: 20),

              if (headerStats.isNotEmpty)
                Row(
                  children: [
                    for (var i = 0; i < headerStats.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(headerStats[i].$1, headerStats[i].$2, cardBg, borderColor,
                            primaryTextColor, secondaryTextColor),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Settings / Account Options (Screen 14 in Reference UI)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
          child: Column(
            children: [
              _buildOptionItem(
                icon: Icons.person_outline_rounded,
                title: 'My Profile',
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                onTap: _openEditDialog,
              ),
              Divider(height: 1, color: borderColor),
              _buildOptionItem(
                icon: Icons.settings_outlined,
                title: 'Settings',
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
              Divider(height: 1, color: borderColor),
              _buildOptionItem(
                icon: Icons.lock_outline_rounded,
                title: 'Change Password',
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                onTap: () => ChangePasswordDialog.show(context),
              ),

            ],
          ),
        ),
        const SizedBox(height: 18),

        // 3. Bottom Coral/Red Pill Button: Log Out (Screen 14 & 21 in Reference UI)
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _confirmLogout,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger, // Coral / Red from reference
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rPill),
              ),
            ),
            child: Text(
              'Log Out',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile(String value, String label, Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppSpacing.r16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ink),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primaryTextColor,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: secondaryTextColor),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color primaryTextColor, Color secondaryTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryInk),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: secondaryTextColor,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: value.startsWith('Not ') ? secondaryTextColor : primaryTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Quick metrics bar for Interns
  Widget _buildInternMetricsBar(Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor) {
    final ov = _overview;
    final totalProjects = ov?.totalProjectsCount ?? 0;
    final activeTasks = ov?.activeTasksCount ?? 0;
    final completedTasks = ov?.completedTasksCount ?? 0;
    final attSummary = ov?.resolvedAttendanceSummary;
    final presentDays = attSummary?.present ?? 0;

    final metrics = [
      {'label': 'Assigned Projects', 'value': '$totalProjects', 'icon': Icons.folder_special_outlined, 'color': AppColors.info},
      {'label': 'Active Tasks', 'value': '$activeTasks', 'icon': Icons.check_circle_outline_rounded, 'color': AppColors.primary},
      {'label': 'Completed Tasks', 'value': '$completedTasks', 'icon': Icons.task_alt_rounded, 'color': AppColors.success},
      {'label': 'Present (30d)', 'value': '$presentDays days', 'icon': Icons.calendar_today_rounded, 'color': AppColors.lavenderInk},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isWide ? 4 : 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: isWide ? 2.0 : 1.7,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, idx) {
            final m = metrics[idx];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.soft,
      ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        m['label'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: secondaryTextColor,
                        ),
                      ),
                      Icon(m['icon'] as IconData, size: 16, color: m['color'] as Color),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    m['value'] as String,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Left card: Contact & Account Information (Non-intern & Intern)
  Widget _buildContactCard(Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor) {
    final user = _activeUser;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: AppColors.primaryInk),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _isIntern ? 'Professional Details' : 'Contact & Account Information',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openEditDialog,
                icon: const Icon(Icons.edit_outlined, size: 13),
                label: const Text('Edit Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryTextColor,
                  side: BorderSide(color: borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow('PHONE NUMBER', user.phone ?? 'Not configured', Icons.phone_outlined, primaryTextColor, secondaryTextColor),
          Divider(height: 1, color: borderColor),
          _buildDetailRow('DEPARTMENT', user.department ?? 'Not assigned', Icons.business_outlined, primaryTextColor, secondaryTextColor),
          Divider(height: 1, color: borderColor),
          _buildDetailRow('JOB TITLE', user.jobTitle ?? 'Not specified', Icons.badge_outlined, primaryTextColor, secondaryTextColor),
          Divider(height: 1, color: borderColor),
          _buildDetailRow('JOINING DATE', user.joiningDate ?? 'Not set', Icons.calendar_month_outlined, primaryTextColor, secondaryTextColor),
          if (_isIntern) ...[
            Divider(height: 1, color: borderColor),
            _buildDetailRow('ASSIGNED MENTOR', user.mentorName ?? 'Not assigned', Icons.school_outlined, primaryTextColor, secondaryTextColor),
          ],
          if (user.organizationName != null && user.organizationName!.isNotEmpty) ...[
            Divider(height: 1, color: borderColor),
            _buildDetailRow('ORGANIZATION', user.organizationName!, Icons.corporate_fare_outlined, primaryTextColor, secondaryTextColor),
          ],
        ],
      ),
    );
  }

  // Skills & Competencies Card
  Widget _buildSkillsCard(Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor) {
    final skills = skillList(_activeUser.skills);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.military_tech_outlined, size: 20, color: AppColors.primaryInk),
                  const SizedBox(width: 8),
                  Text(
                    'Skills & Competencies',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _openEditDialog,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Add / Edit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (skills.isEmpty)
            InkWell(
              onTap: _openEditDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, style: BorderStyle.solid),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: secondaryTextColor),
                    const SizedBox(width: 6),
                    Text('+ Add skills', style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                  ],
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: skills.map((s) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text(
                    s,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // About & Summary Card
  Widget _buildAboutCard(Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor) {
    final bio = _activeUser.bio;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 18, color: AppColors.primaryInk),
                  const SizedBox(width: 8),
                  Text(
                    _isIntern ? 'About & Summary' : 'About & Professional Summary',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _openEditDialog,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Edit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            (bio != null && bio.trim().isNotEmpty)
                ? bio.trim()
                : 'No professional summary provided yet. Click Edit to add details about your experience and background.',
            style: TextStyle(
              fontSize: 13,
              color: (bio != null && bio.trim().isNotEmpty) ? primaryTextColor : secondaryTextColor,
              fontStyle: (bio != null && bio.trim().isNotEmpty) ? FontStyle.normal : FontStyle.italic,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // Right Column for Interns: Projects, Attendance, Leave
  Widget _buildInternRightColumn(Color cardBg, Color borderColor, Color primaryTextColor, Color secondaryTextColor) {
    if (_isLoadingOverview && _overview == null) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final ov = _overview;
    final projects = ov?.projects ?? [];
    final attSummary = ov?.resolvedAttendanceSummary;
    final leaveSummary = ov?.resolvedLeaveSummary;
    final balance = ov?.leaveBalance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Assigned Projects Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined, size: 18, color: AppColors.primaryInk),
                  const SizedBox(width: 8),
                  Text(
                    'Assigned Projects (${projects.length})',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (projects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No projects assigned currently.',
                    style: TextStyle(fontSize: 13, color: secondaryTextColor, fontStyle: FontStyle.italic),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: projects.length,
                  separatorBuilder: (_, _) => Divider(height: 20, color: borderColor),
                  itemBuilder: (context, idx) {
                    final p = projects[idx];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                p.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: secondaryTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (p.progress / 100).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${p.progress.toInt()}% completed',
                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                            ),
                            if (p.endDate != null && p.endDate!.isNotEmpty)
                              Text(
                                'Target: ${p.endDate}',
                                style: TextStyle(fontSize: 11, color: secondaryTextColor),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Attendance (Last 30 Days)
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 18, color: AppColors.primaryInk),
                  const SizedBox(width: 8),
                  Text(
                    'Attendance (Last 30 Days)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildAttendanceStatTile('Present', '${attSummary?.present ?? 0}', AppColors.success),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAttendanceStatTile('Late', '${attSummary?.late ?? 0}', AppColors.warning),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAttendanceStatTile('Half-Day', '${attSummary?.halfDay ?? 0}', AppColors.info),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAttendanceStatTile('Absent/Leave', '${attSummary?.absentIncludingLeave ?? 0}', AppColors.danger),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Leave Overview
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.soft,
      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.beach_access_outlined, size: 18, color: AppColors.primaryInk),
                  const SizedBox(width: 8),
                  Text(
                    'Leave Overview',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildLeaveStatTile('Total Applied', '${leaveSummary?.total ?? 0}', primaryTextColor, secondaryTextColor)),
                  Expanded(child: _buildLeaveStatTile('Approved', '${leaveSummary?.approved ?? 0}', AppColors.success, secondaryTextColor)),
                  Expanded(child: _buildLeaveStatTile('Pending', '${leaveSummary?.pending ?? 0}', AppColors.warning, secondaryTextColor)),
                  Expanded(child: _buildLeaveStatTile('Rejected', '${leaveSummary?.rejected ?? 0}', AppColors.danger, secondaryTextColor)),
                ],
              ),
              if (balance != null) ...[
                const SizedBox(height: 18),
                Divider(height: 1, color: borderColor),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Leave Quota Utilization',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secondaryTextColor),
                    ),
                    Text(
                      '${balance.remaining} of ${balance.quota} days left',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (balance.quota > 0 ? (balance.used / balance.quota) : 0.0).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceStatTile(String label, String count, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveStatTile(String label, String value, Color valueColor, Color secondaryTextColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: secondaryTextColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadProfileData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Top Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageHeader(
                        title: 'Profile',
                        showBack: widget.showBackButton && Navigator.canPop(context),
                        padding: EdgeInsets.zero,
                        actions: [
                          HeaderAction(icon: Icons.settings_outlined, tooltip: 'Settings', onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SettingsScreen()),
                              );
                            }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Loading / Error
              if (_isLoadingProfile && _profileUser == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (_errorMessage != null && _profileUser == null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'Failed to load profile',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 6),
                        Text(_errorMessage!, style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadProfileData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Shared Header Card
                        _buildHeaderCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                        const SizedBox(height: 20),

                        // Intern Metrics Bar (if intern)
                        if (_isIntern) ...[
                          _buildInternMetricsBar(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                          const SizedBox(height: 20),
                        ],

                        // Main Layout: Two Column on wider screens, stacked on mobile
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 768;

                            final leftSection = Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildContactCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                                const SizedBox(height: 16),
                                _buildSkillsCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                                const SizedBox(height: 16),
                                _buildAboutCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                              ],
                            );

                            if (!_isIntern) {
                              // Non-intern (Admin / Mentor / Superadmin)
                              if (isWide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: _buildContactCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      flex: 6,
                                      child: Column(
                                        children: [
                                          _buildSkillsCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                                          const SizedBox(height: 16),
                                          _buildAboutCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    _buildContactCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                                    const SizedBox(height: 16),
                                    _buildSkillsCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                                    const SizedBox(height: 16),
                                    _buildAboutCard(cardBg, borderColor, primaryTextColor, secondaryTextColor),
                                  ],
                                );
                              }
                            } else {
                              // Intern layout
                              final rightSection = _buildInternRightColumn(cardBg, borderColor, primaryTextColor, secondaryTextColor);

                              if (isWide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 5, child: leftSection),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 6, child: rightSection),
                                  ],
                                );
                              } else {
                                return Column(
                                  children: [
                                    leftSection,
                                    const SizedBox(height: 16),
                                    rightSection,
                                  ],
                                );
                              }
                            }
                          },
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
