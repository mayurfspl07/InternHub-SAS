import 'package:flutter/material.dart';
import '../models/dashboard_models.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/capsule_bar_chart.dart';

// ==========================================
// TOKENS & PALETTE
// ==========================================
class DashboardChartColors {
  // Task Colors
  static const Color taskDone = AppColors.olive;
  static const Color taskInProgress = AppColors.primary;
  static const Color taskTodo = AppColors.taupe;
  static const Color taskTesting = AppColors.chartLavender;
  static const Color taskOverdue = AppColors.chartPeach;

  // Project Colors
  static const Color projectPlanning = AppColors.taupe;
  static const Color projectActive = AppColors.primary;
  static const Color projectCompleted = AppColors.olive;
  static const Color projectOnHold = AppColors.sand;

  // Attendance Colors
  static const Color attendancePresent = AppColors.primary;
  static const Color attendanceAbsent = AppColors.cocoa;
  static const Color attendanceLeave = AppColors.chartLavender;
}

// ==========================================
// 1) ATTENDANCE AREA / BAR CHART
// ==========================================
class DashboardAttendanceChart extends StatelessWidget {
  final List<DashboardAttendancePoint> points;
  final String title;
  final String subtitle;

  const DashboardAttendanceChart({
    super.key,
    required this.points,
    this.title = 'Attendance & Hours Trend',
    this.subtitle = 'Hours logged over recent sessions',
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final validPoints = points.where((p) => p.date.isNotEmpty).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: secondaryTextColor),
                  ),
                ],
              ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: DashboardChartColors.attendancePresent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Hours',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (validPoints.isEmpty)
            SizedBox(
              height: 180,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 36, color: secondaryTextColor),
                    const SizedBox(height: 8),
                    Text(
                      'No attendance logged yet',
                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: CustomPaint(
                size: const Size(double.infinity, 180),
                painter: _AttendanceAreaChartPainter(
                  points: validPoints,
                  accentColor: DashboardChartColors.attendancePresent,
                  textColor: secondaryTextColor,
                  gridColor: borderColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttendanceAreaChartPainter extends CustomPainter {
  final List<DashboardAttendancePoint> points;
  final Color accentColor;
  final Color textColor;
  final Color gridColor;

  _AttendanceAreaChartPainter({
    required this.points,
    required this.accentColor,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPadding = 32.0;
    const rightPadding = 12.0;
    const bottomPadding = 24.0;
    const topPadding = 12.0;

    final chartWidth = size.width - leftPadding - rightPadding;
    final chartHeight = size.height - topPadding - bottomPadding;

    // Find max hours
    double maxHours = 8.0;
    for (final p in points) {
      if (p.hours > maxHours) maxHours = p.hours;
    }
    // Round max to multiple of 2
    maxHours = ((maxHours / 2).ceil() * 2).toDouble();
    if (maxHours < 4) maxHours = 4;

    // Grid lines (3 horizontal lines: 0, max/2, max)
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    final ySteps = [0.0, maxHours / 2, maxHours];
    for (final step in ySteps) {
      final y = topPadding + chartHeight - (step / maxHours) * chartHeight;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width - rightPadding, y), gridPaint);

      textPainter.text = TextSpan(
        text: '${step.toInt()}h',
        style: AppTypography.label.copyWith(color: textColor, fontSize: 10, fontWeight: FontWeight.w500),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(leftPadding - textPainter.width - 6, y - textPainter.height / 2));
    }

    final count = points.length;
    final dx = count > 1 ? chartWidth / (count - 1) : chartWidth / 2;

    final linePath = Path();
    final fillPath = Path();

    final List<Offset> pointOffsets = [];

    for (int i = 0; i < count; i++) {
      final p = points[i];
      final x = count > 1 ? leftPadding + (i * dx) : leftPadding + chartWidth / 2;
      final y = topPadding + chartHeight - ((p.hours.clamp(0.0, maxHours)) / maxHours) * chartHeight;
      final offset = Offset(x, y);
      pointOffsets.add(offset);

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, topPadding + chartHeight);
        fillPath.lineTo(x, y);
      } else {
        // Smooth bezier curve
        final prev = pointOffsets[i - 1];
        final midX = (prev.dx + x) / 2;
        linePath.cubicTo(midX, prev.dy, midX, y, x, y);
        fillPath.cubicTo(midX, prev.dy, midX, y, x, y);
      }

      // X-axis label
      String label = p.date;
      if (label.length >= 5) {
        // e.g. "2026-09-16" -> "09/16" or "Wed"
        final parts = label.split('-');
        if (parts.length >= 3) {
          label = '${parts[1]}/${parts[2]}';
        }
      }
      textPainter.text = TextSpan(
        text: label,
        style: AppTypography.label.copyWith(color: textColor, fontSize: 10, fontWeight: FontWeight.w500),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - bottomPadding + 6),
      );
    }

    // Complete fill path
    final last = pointOffsets.last;
    fillPath.lineTo(last.dx, topPadding + chartHeight);
    fillPath.close();

    // Draw area gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withValues(alpha: 0.35),
          accentColor.withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(leftPadding, topPadding, chartWidth, chartHeight));
    canvas.drawPath(fillPath, fillPaint);

    // Draw stroke line
    final strokePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, strokePaint);

    // Draw point circles
    final pointPaint = Paint()..color = accentColor;
    final innerPaint = Paint()..color = Colors.white;

    for (final pt in pointOffsets) {
      canvas.drawCircle(pt, 5.0, pointPaint);
      canvas.drawCircle(pt, 2.5, innerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AttendanceAreaChartPainter oldDelegate) => true;
}

// ==========================================
class DashboardStatusDistributionBar extends StatelessWidget {
  final String title;
  final Map<String, int> statusCounts;
  final Map<String, Color> colorMap;
  final String emptyLabel;

  const DashboardStatusDistributionBar({
    super.key,
    required this.title,
    required this.statusCounts,
    required this.colorMap,
    this.emptyLabel = 'No items found',
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final entries = statusCounts.entries.where((e) => e.value > 0).toList();
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.rCard),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: primaryTextColor,
                ),
              ),
              Text(
                '$total Total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (total <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                emptyLabel,
                style: TextStyle(fontSize: 13, color: secondaryTextColor),
              ),
            )
          else ...[
            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: entries.map((entry) {
                    final flex = (entry.value * 1000 / total).round().clamp(1, 1000);
                    final color = colorMap[entry.key.toLowerCase()] ?? AppColors.textTertiary;
                    return Expanded(
                      flex: flex,
                      child: Container(color: color),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: entries.map((entry) {
                final color = colorMap[entry.key.toLowerCase()] ?? AppColors.textTertiary;
                final displayName = _formatStatusLabel(entry.key);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$displayName: ',
                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                    ),
                    Text(
                      '${entry.value}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _formatStatusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'in_progress':
      case 'inprogress':
      case 'doing':
        return 'In Progress';
      case 'done':
      case 'completed':
        return 'Completed';
      case 'todo':
      case 'pending':
        return 'To Do';
      case 'testing':
      case 'review':
        return 'In Review';
      case 'on_hold':
      case 'onhold':
        return 'On Hold';
      case 'planning':
        return 'Planning';
      case 'active':
        return 'Active';
      default:
        return raw.substring(0, 1).toUpperCase() + (raw.length > 1 ? raw.substring(1) : '');
    }
  }
}

// ==========================================
// 4) CAPSULE CHARTS (reference "Emotions" style)
// ==========================================

/// Present / absent / on-leave split as capsule bars.
class DashboardPresenceCapsules extends StatelessWidget {
  final String title;
  final String? subtitle;
  final int present;
  final int absent;
  final int onLeave;

  const DashboardPresenceCapsules({
    super.key,
    required this.title,
    this.subtitle,
    required this.present,
    required this.absent,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    final total = present + absent + onLeave;
    double share(int n) => total == 0 ? 0 : n / total;

    return CapsuleBarChart(
      title: title,
      subtitle: subtitle,
      barHeight: 150,
      data: [
        CapsuleBarDatum(label: 'Present', fraction: share(present), valueLabel: '$present', color: DashboardChartColors.attendancePresent),
        CapsuleBarDatum(label: 'Absent', fraction: share(absent), valueLabel: '$absent', color: DashboardChartColors.attendanceAbsent),
        CapsuleBarDatum(label: 'On leave', fraction: share(onLeave), valueLabel: '$onLeave', color: DashboardChartColors.attendanceLeave),
      ],
    );
  }
}

/// Task status split (done / doing / to do / review, plus overdue) as capsule bars.
class DashboardTaskCapsules extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Map<String, int> taskStatus;
  final int overdue;

  const DashboardTaskCapsules({
    super.key,
    required this.title,
    this.subtitle,
    required this.taskStatus,
    this.overdue = 0,
  });

  @override
  Widget build(BuildContext context) {
    final done = taskStatus['done'] ?? taskStatus['completed'] ?? 0;
    final doing = taskStatus['in_progress'] ?? taskStatus['doing'] ?? 0;
    final todo = taskStatus['todo'] ?? taskStatus['pending'] ?? 0;
    final review = taskStatus['testing'] ?? taskStatus['review'] ?? 0;
    final total = done + doing + todo + review;
    double share(int n) => total == 0 ? 0 : n / total;

    return CapsuleBarChart(
      title: title,
      subtitle: subtitle ?? (total == 0 ? 'No tasks assigned yet' : '$total tasks in total'),
      data: [
        CapsuleBarDatum(label: 'Done', fraction: share(done), valueLabel: '$done', color: DashboardChartColors.taskDone),
        CapsuleBarDatum(label: 'Doing', fraction: share(doing), valueLabel: '$doing', color: DashboardChartColors.taskInProgress),
        CapsuleBarDatum(label: 'To do', fraction: share(todo), valueLabel: '$todo', color: DashboardChartColors.taskTodo),
        CapsuleBarDatum(label: 'Review', fraction: share(review), valueLabel: '$review', color: DashboardChartColors.taskTesting),
        if (overdue > 0)
          CapsuleBarDatum(label: 'Overdue', fraction: share(overdue).clamp(0, 1), valueLabel: '$overdue', color: DashboardChartColors.taskOverdue),
      ],
    );
  }
}
