import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/user_360_profile_dialog.dart';

class MemberProfileScreen extends StatelessWidget {
  final UserModel member;

  const MemberProfileScreen({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.badge_outlined),
            tooltip: 'View 360° Profile',
            onPressed: () => User360ProfileDialog.show(context, userId: member.id, fallbackUser: member),
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
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary),
                      )
                    : null,
              ),
              const SizedBox(height: 16),

              Text(
                member.name,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textPrimaryLight,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${member.roleTitle}${member.department != null && member.department!.isNotEmpty ? ' • ${member.department}' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCircleAction(Icons.email_outlined, () {}, isDark),
                  const SizedBox(width: 12),
                  _buildCircleAction(Icons.phone_outlined, () {}, isDark),
                  const SizedBox(width: 12),
                  _buildCircleAction(Icons.calendar_today_outlined, () {}, isDark),
                  const SizedBox(width: 12),
                  _buildCircleAction(Icons.badge_outlined, () => User360ProfileDialog.show(context, userId: member.id, fallbackUser: member), isDark),
                ],
              ),
              const SizedBox(height: 28),

              // Stats Grid
              Row(
                children: [
                  _buildStatBox('Rating', '⭐ ${member.performanceRating.toStringAsFixed(1)}', const Color(0xFFD1FAE5), isDark),
                  const SizedBox(width: 10),
                  _buildStatBox('Streak', '🔥 ${member.attendanceStreak}d', const Color(0xFFFEF3C7), isDark),
                  const SizedBox(width: 10),
                  _buildStatBox('Coins', '🟡 ${member.streakCoins}', const Color(0xFFFFEDD5), isDark),
                ],
              ),
              const SizedBox(height: 24),

              // Detailed Info Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Detailed Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.textPrimaryLight,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildInfoRow('Email', member.email, Icons.email_outlined, isDark),
                    _buildInfoRow('Phone', member.phone ?? 'Not provided', Icons.phone_outlined, isDark),
                    _buildInfoRow('Location', member.location, Icons.location_on_outlined, isDark),
                    _buildInfoRow('Cohort', member.cohortName ?? 'General Cohort', Icons.school_outlined, isDark),
                    if (member.mentorName != null && member.mentorName!.isNotEmpty)
                      _buildInfoRow('Mentor', member.mentorName!, Icons.person_outline, isDark),
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
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Skills & Competencies',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
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
                              color: isDark ? const Color(0xFF2B3040) : AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            ),
                            child: Text(
                              skill,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
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

  Widget _buildCircleAction(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : const Color(0xFFF3F4F6),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
        child: Icon(icon, size: 20, color: isDark ? Colors.white : AppColors.textPrimaryLight),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : color,
          borderRadius: BorderRadius.circular(20),
          border: isDark ? Border.all(color: AppColors.borderDark) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
