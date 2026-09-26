import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/models/attendance_model.dart';
import '../../shared/widgets/status_chip.dart';

class AttendanceDetailsModal extends StatelessWidget {
  final AttendanceRecord record;

  const AttendanceDetailsModal({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final checkInStr = DateFormat('hh:mm a').format(record.checkInTime);
    final checkOutStr = record.checkOutTime != null
        ? DateFormat('hh:mm a').format(record.checkOutTime!)
        : 'In Progress';
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(record.dateTime);

    final hoursWorked = record.workingHours != null
        ? '${record.workingHours!.inHours}h ${record.workingHours!.inMinutes.remainder(60)}m'
        : (record.checkOutTime != null
            ? '${record.checkOutTime!.difference(record.checkInTime).inHours}h ${record.checkOutTime!.difference(record.checkInTime).inMinutes.remainder(60)}m'
            : 'In Progress');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Record',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                StatusChip.fromAttendance(record.statusEnum),
              ],
            ),
            const SizedBox(height: 24),

            // Working Hours Badge
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildTimeColumn('Check-In', checkInStr, Icons.login_rounded),
                  Container(width: 1, height: 36, color: AppColors.border),
                  _buildTimeColumn('Check-Out', checkOutStr, Icons.logout_rounded),
                  Container(width: 1, height: 36, color: AppColors.border),
                  _buildTimeColumn('Total Hours', hoursWorked, Icons.timer_outlined),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Audit Metadata
            _buildAuditRow('User Name', record.userName ?? '—'),
            _buildAuditRow('GPS Coordinates', '${record.latitude.toStringAsFixed(5)}, ${record.longitude.toStringAsFixed(5)}'),
            _buildAuditRow('Geofence Verification', record.isInsideGeofence ? 'Passed (Authorized)' : 'Outside Geofence'),
            _buildAuditRow('Address', record.locationAddress),
            if (record.overrideReason != null && record.overrideReason!.isNotEmpty)
              _buildAuditRow('Override Reason', record.overrideReason!),

            // Photo preview if available
            if (record.selfieUrl != null && record.selfieUrl!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Verification Selfie', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  record.selfieUrl!,
                  height: 140,
                  width: 140,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 100,
                    width: 100,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.broken_image_rounded, color: AppColors.textTertiary),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryInk),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildAuditRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
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
