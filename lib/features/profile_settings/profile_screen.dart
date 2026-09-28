import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/profile_overview_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/load_error_view.dart';
import 'change_password_dialog.dart';
import 'profile_repository.dart';
import 'widgets/edit_profile_dialog.dart';
import '../../core/constants/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/status_chip.dart';
import '../../shared/widgets/logout_confirm_dialog.dart';
import '../projects_tasks/project_detail_screen.dart';

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
  bool _uploadingPhoto = false;
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
          _errorMessage = apiErrorMessage(e);
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

  Future<void> _changePhoto() async {
    if (_uploadingPhoto) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploadingPhoto = true);
    try {
      await ref.read(appStateProvider.notifier).uploadAvatar(File(picked.path));
      if (mounted) setState(() => _profileUser = _profileUser?.copyWith(avatarUrl: ref.read(appStateProvider).currentUser.avatarUrl));
      messenger.showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: "Couldn't upload the photo");
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
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
              // Avatar with a camera badge; the badge's tap area is 44px even though it looks smaller.
              SizedBox(
                width: 104,
                height: 100,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AppAvatar(url: avatarUrl, fallbackText: user.name, size: 92),
                          if (_uploadingPhoto)
                            Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                color: AppColors.ink.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.surface),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Semantics(
                        button: true,
                        label: 'Change profile photo',
                        child: Tooltip(
                          message: 'Change photo',
                          child: InkResponse(
                            onTap: _uploadingPhoto ? null : _changePhoto,
                            radius: 24,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cardBg, width: 2.5),
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, size: 16, color: AppColors.onPrimary),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Name
              Text(
                user.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
              ),
              const SizedBox(height: 4),

              // Role & Department Subtitle
              Text(
                [user.roleTitle, if ((user.department ?? '').isNotEmpty) user.department!].join(' · '),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: secondaryTextColor),
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
                title: 'Edit profile',
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                onTap: _openEditDialog,
              ),
              Divider(height: 1, color: borderColor),
              _buildOptionItem(
                icon: Icons.lock_outline_rounded,
                title: 'Change password',
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                onTap: () => ChangePasswordDialog.show(context),
              ),

            ],
          ),
        ),
        const SizedBox(height: 18),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () => showLogoutConfirmDialog(context, ref),
            icon: const Icon(Icons.logout_rounded, size: 20),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.dangerInk,
              side: const BorderSide(color: AppColors.danger),
              textStyle: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rPill)),
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(color: secondaryTextColor),
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
                style: AppTypography.bodyStrong.copyWith(color: primaryTextColor),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: secondaryTextColor),
          ],
        ),
      ),
    );
  }

  Widget _editButton() => TextButton.icon(
        onPressed: _openEditDialog,
        icon: const Icon(Icons.edit_outlined, size: 16),
        label: const Text('Edit'),
        style: TextButton.styleFrom(foregroundColor: AppColors.primaryInk, minimumSize: const Size(44, 44)),
      );

  Widget _buildDetailRow(String label, String value, IconData icon, Color primaryTextColor, Color secondaryTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryInk),
          const SizedBox(width: 12),
          Text(label, style: AppTypography.caption),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: value.startsWith('Not ') ? secondaryTextColor : primaryTextColor),
            ),
          ),
        ],
      ),
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
                        'Details',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _editButton(),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Phone', user.phone ?? 'Not added', Icons.phone_outlined, primaryTextColor, secondaryTextColor),
          Divider(height: 1, color: borderColor),
          _buildDetailRow('Department', user.department ?? 'Not set', Icons.business_outlined, primaryTextColor, secondaryTextColor),
          Divider(height: 1, color: borderColor),
          _buildDetailRow('Job title', user.jobTitle ?? 'Not set', Icons.badge_outlined, primaryTextColor, secondaryTextColor),
          Divider(height: 1, color: borderColor),
          _buildDetailRow('Joined', formatDate(user.joiningDate, fallback: 'Not set'), Icons.calendar_month_outlined, primaryTextColor, secondaryTextColor),
          if (_isIntern && user.internshipDurationMonths != null) ...[
            Divider(height: 1, color: borderColor),
            _buildDetailRow(
              'Internship',
              plural(user.internshipDurationMonths!, 'month') +
                  ((user.internshipEndDate ?? '').isNotEmpty ? ' · ends ${formatDate(user.internshipEndDate)}' : ''),
              Icons.hourglass_bottom_rounded,
              primaryTextColor,
              secondaryTextColor,
            ),
          ],
          if (_isIntern) ...[
            Divider(height: 1, color: borderColor),
            _buildDetailRow('Mentor', user.mentorName ?? 'Not assigned', Icons.school_outlined, primaryTextColor, secondaryTextColor),
          ],
          if (user.organizationName != null && user.organizationName!.isNotEmpty) ...[
            Divider(height: 1, color: borderColor),
            _buildDetailRow('Organization', user.organizationName!, Icons.corporate_fare_outlined, primaryTextColor, secondaryTextColor),
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
              Icon(Icons.military_tech_outlined, size: 20, color: AppColors.primaryInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Skills',
                  style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                ),
              ),
              _editButton(),
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
                    Text('Add skills', style: AppTypography.caption.copyWith(color: secondaryTextColor)),
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
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: primaryTextColor),
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
              Icon(Icons.description_outlined, size: 18, color: AppColors.primaryInk),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'About',
                  style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                ),
              ),
              _editButton(),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            (bio != null && bio.trim().isNotEmpty)
                ? bio.trim()
                : 'Add a short summary of your background and what you work on.',
            style: AppTypography.caption.copyWith(color: (bio != null && bio.trim().isNotEmpty) ? primaryTextColor : secondaryTextColor, fontStyle: (bio != null && bio.trim().isNotEmpty) ? FontStyle.normal : FontStyle.italic, height: 1.5),
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
                  Expanded(
                    child: Text(
                      'Projects (${projects.length})',
                      style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (projects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    "You aren't on any projects yet.",
                    style: AppTypography.caption.copyWith(color: secondaryTextColor, fontStyle: FontStyle.italic),
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
                    final column = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                p.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusChip.fromString(p.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (p.progress / 100).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: AppColors.border,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${p.progress.toInt()}% done',
                              style: AppTypography.label.copyWith(color: secondaryTextColor),
                            ),
                            if (p.endDate != null && p.endDate!.isNotEmpty)
                              Text(
                                'Due ${formatDate(p.endDate)}',
                                style: AppTypography.label.copyWith(color: secondaryTextColor),
                              ),
                          ],
                        ),
                      ],
                    );
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ProjectDetailScreen(projectId: p.id)),
                      ),
                      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: column),
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
                    'Attendance · last 30 days',
                    style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildAttendanceStatTile('Present', '${attSummary?.present ?? 0}', AppColors.successInk),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAttendanceStatTile('Late', '${attSummary?.late ?? 0}', AppColors.warningInk),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAttendanceStatTile('Half day', '${attSummary?.halfDay ?? 0}', AppColors.infoInk),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildAttendanceStatTile('Absent or leave', '${attSummary?.absentIncludingLeave ?? 0}', AppColors.dangerInk),
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
                    'Leave',
                    style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildLeaveStatTile('Requested', '${leaveSummary?.total ?? 0}', primaryTextColor, secondaryTextColor)),
                  Expanded(child: _buildLeaveStatTile('Approved', '${leaveSummary?.approved ?? 0}', AppColors.successInk, secondaryTextColor)),
                  Expanded(child: _buildLeaveStatTile('Pending', '${leaveSummary?.pending ?? 0}', AppColors.warningInk, secondaryTextColor)),
                  Expanded(child: _buildLeaveStatTile('Rejected', '${leaveSummary?.rejected ?? 0}', AppColors.dangerInk, secondaryTextColor)),
                ],
              ),
              if (balance != null) ...[
                const SizedBox(height: 18),
                Divider(height: 1, color: borderColor),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      'Leave balance',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: secondaryTextColor),
                    ),
                    Text(
                      '${balance.remaining} of ${balance.quota} days left',
                      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(count, style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: accentColor)),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: AppTypography.label.copyWith(color: accentColor),
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
          style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: valueColor),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.label.copyWith(color: secondaryTextColor),
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
                  child: LoadErrorView(
                    title: "Couldn't load your profile",
                    message: _errorMessage!,
                    onRetry: _loadProfileData,
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
