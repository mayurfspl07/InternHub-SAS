import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/user_360_profile_dialog.dart';
import '../../core/constants/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/app_avatar.dart';

class MemberProfileScreen extends StatelessWidget {
  final UserModel member;

  const MemberProfileScreen({super.key, required this.member});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(context, title: 'Profile'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.p20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar & Name Card
              AppAvatar(url: member.avatarUrl, fallbackText: member.name, size: 92),
              const SizedBox(height: 16),

              Text(
                member.name,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 4),
              Text(
                [member.roleTitle, if ((member.department ?? '').isNotEmpty) member.department!].join(' · '),
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // Labelled actions; one entry for the full (360) profile.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (member.email.isNotEmpty)
                    _action(Icons.email_outlined, 'Email', () => _open(context, Uri(scheme: 'mailto', path: member.email))),
                  if ((member.phone ?? '').trim().isNotEmpty)
                    _action(Icons.phone_outlined, 'Call', () => _open(context, Uri(scheme: 'tel', path: member.phone!.replaceAll(' ', '')))),
                  _action(
                    Icons.insights_outlined,
                    'Work & attendance',
                    () => User360ProfileDialog.show(context, userId: member.id, fallbackUser: member),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Detailed Info Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Details',
                      style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    const SizedBox(height: 14),
                    _buildInfoRow('Email', member.email, Icons.email_outlined),
                    _buildInfoRow('Phone', member.phone ?? 'Not provided', Icons.phone_outlined),
                    _buildInfoRow('Status', member.isActive ? 'Active' : 'Inactive', Icons.toggle_on_outlined),
                    if ((member.joiningDate ?? '').isNotEmpty)
                      _buildInfoRow('Joined', formatDate(member.joiningDate), Icons.event_outlined),
                    if (member.internshipDurationMonths != null)
                      _buildInfoRow(
                        'Internship',
                        plural(member.internshipDurationMonths!, 'month') +
                            ((member.internshipEndDate ?? '').isNotEmpty ? ' · ends ${formatDate(member.internshipEndDate)}' : ''),
                        Icons.school_outlined,
                      ),
                    if (member.isPaid != null)
                      _buildInfoRow(
                        'Stipend',
                        member.isPaid == true
                            ? (member.stipendAmount != null ? '₹${member.stipendAmount!.toStringAsFixed(0)} / month' : 'Paid')
                            : 'Unpaid',
                        Icons.payments_outlined,
                      ),
                    if (member.mentorName != null && member.mentorName!.isNotEmpty)
                      _buildInfoRow('Mentor', member.mentorName!, Icons.person_outline),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Skills Chips
              if (member.skills.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Skills',
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: member.skills.map((skill) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            ),
                            child: Text(
                              skill,
                              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.primaryInk),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 44),
        shape: const StadiumBorder(),
      ),
    );
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(uri.scheme == 'tel' ? 'No app on this phone can make calls' : 'No email app found')),
      );
    }
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Text(label, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
