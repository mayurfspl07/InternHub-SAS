import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/user_360_profile_dialog.dart';

class MemberProfileScreen extends StatelessWidget {
  final UserModel member;

  const MemberProfileScreen({super.key, required this.member});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: pageAppBar(
        context,
        title: 'Member Profile',
        actions: [
          HeaderAction(
            icon: Icons.badge_outlined,
            tooltip: 'View 360° Profile',
            onTap: () => User360ProfileDialog.show(context, userId: member.id, fallbackUser: member),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.p20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar & Name Card
              CircleAvatar(
                radius: 46,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                backgroundImage: (member.avatarUrl != null && member.avatarUrl!.isNotEmpty)
                    ? NetworkImage(member.avatarUrl!)
                    : null,
                child: (member.avatarUrl == null || member.avatarUrl!.isEmpty)
                    ? Text(
                        member.name.isNotEmpty ? member.name[0].toUpperCase() : 'U',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primaryInk),
                      )
                    : null,
              ),
              const SizedBox(height: 16),

              Text(
                member.name,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${member.roleTitle}${member.department != null && member.department!.isNotEmpty ? ' • ${member.department}' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCircleAction(Icons.email_outlined, () {}),
                  const SizedBox(width: 12),
                  _buildCircleAction(Icons.phone_outlined, () {}),
                  const SizedBox(width: 12),
                  _buildCircleAction(Icons.calendar_today_outlined, () {}),
                  const SizedBox(width: 12),
                  _buildCircleAction(Icons.badge_outlined, () => User360ProfileDialog.show(context, userId: member.id, fallbackUser: member)),
                ],
              ),
              const SizedBox(height: 28),

              // Stats Grid
              Row(
                children: [
                  _buildStatBox('Rating', '⭐ ${member.performanceRating.toStringAsFixed(1)}', AppColors.successSoft),
                  const SizedBox(width: 10),
                  _buildStatBox('Streak', '🔥 ${member.attendanceStreak}d', AppColors.warningSoft),
                  const SizedBox(width: 10),
                  _buildStatBox('Coins', '🟡 ${member.streakCoins}', AppColors.peach),
                ],
              ),
              const SizedBox(height: 24),

              // Detailed Info Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detailed Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildInfoRow('Email', member.email, Icons.email_outlined),
                    _buildInfoRow('Phone', member.phone ?? 'Not provided', Icons.phone_outlined),
                    _buildInfoRow('Location', member.location, Icons.location_on_outlined),
                    _buildInfoRow('Cohort', member.cohortName ?? 'General Cohort', Icons.school_outlined),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Skills & Competencies',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
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
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryInk,
                              ),
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

  Widget _buildCircleAction(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          shape: BoxShape.circle,
          border: Border.all(
            color: AppColors.border,
          ),
        ),
        child: Icon(icon, size: 20, color: AppColors.ink),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
