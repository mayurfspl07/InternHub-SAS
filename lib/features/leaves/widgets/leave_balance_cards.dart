import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/leave_model.dart';

class LeaveBalanceCards extends StatelessWidget {
  final LeaveBalance balance;
  final LeaveSummary? summary;
  final int totalRequests;

  const LeaveBalanceCards({
    super.key,
    required this.balance,
    this.summary,
    this.totalRequests = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final quota = balance.quota > 0 ? balance.quota : 15;
    final used = balance.used;
    final remaining = balance.remaining;
    final usedPct = min(100, (used / quota * 100).round());
    final pendingDays = balance.pending ?? summary?.days_pending ?? 0;
    final approvedCount = summary?.approved ?? 0;
    final pendingCount = summary?.pending ?? 0;
    final rejectedCount = summary?.rejected ?? 0;
    final totalCount = summary?.total ?? totalRequests;
    final freeAfterPending = balance.available_after_pending ?? (remaining - pendingDays);

    return Column(
      children: [
        // Row 1: Available Leave & Days Taken
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildCard(
                  isDark: isDark,
                  bgColor: isDark ? const Color(0xFF1E1B2E) : const Color(0xFFEDE9FE),
                  borderColor: isDark ? AppColors.primary.withValues(alpha: 0.3) : const Color(0xFFDDD6FE),
                  icon: Icons.beach_access_rounded,
                  iconColor: AppColors.primary,
                  title: 'AVAILABLE LEAVE',
                  value: '$remaining / $quota days',
                  subtitle: 'Remaining quota for this term',
                  footer: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (used / quota).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: isDark ? Colors.white12 : Colors.black12,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$usedPct% used',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                            ),
                          ),
                          Text(
                            '${remaining}d left',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCard(
                  isDark: isDark,
                  bgColor: isDark ? const Color(0xFF16232D) : const Color(0xFFE0F2FE),
                  borderColor: isDark ? AppColors.accent.withValues(alpha: 0.3) : const Color(0xFFBAE6FD),
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: const Color(0xFF0284C7),
                  title: 'DAYS TAKEN',
                  value: '$used days',
                  subtitle: '$approvedCount request approved',
                  footer: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Approved:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                        Text(
                          '$approvedCount',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Row 2: Pending Review & Requests History
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildCard(
                  isDark: isDark,
                  bgColor: isDark ? const Color(0xFF282416) : const Color(0xFFFEF9C3),
                  borderColor: isDark ? AppColors.warning.withValues(alpha: 0.3) : const Color(0xFFFDE68A),
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFFD97706),
                  title: 'PENDING REVIEW',
                  value: '$pendingDays days',
                  subtitle: '$pendingCount request awaiting approval',
                  footer: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'In queue:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                        Text(
                          '$pendingCount',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCard(
                  isDark: isDark,
                  bgColor: isDark ? AppColors.surfaceDark : const Color(0xFFF3F4F6),
                  borderColor: isDark ? AppColors.borderDark : const Color(0xFFE5E7EB),
                  icon: Icons.military_tech_outlined,
                  iconColor: isDark ? Colors.white70 : Colors.black54,
                  title: 'REQUESTS HISTORY',
                  value: '$totalCount total',
                  subtitle: '$rejectedCount rejected • ${freeAfterPending}d free',
                  footer: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Rejected:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                        Text(
                          '$rejectedCount',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required bool isDark,
    required Color bgColor,
    required Color borderColor,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    required Widget footer,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                  ),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? Colors.white10 : Colors.white,
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
            ),
          ),
          footer,
        ],
      ),
    );
  }
}
