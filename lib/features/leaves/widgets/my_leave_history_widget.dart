import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/leave_model.dart';
import 'leave_attachment_viewer.dart';

class MyLeaveHistoryWidget extends StatefulWidget {
  final LeaveMineResponse mineData;
  final VoidCallback onRefresh;

  const MyLeaveHistoryWidget({
    super.key,
    required this.mineData,
    required this.onRefresh,
  });

  @override
  State<MyLeaveHistoryWidget> createState() => _MyLeaveHistoryWidgetState();
}

class _MyLeaveHistoryWidgetState extends State<MyLeaveHistoryWidget> {
  String _activeTab = 'all'; // all | approved | pending | rejected

  List<LeaveRequest> get _filteredRequests {
    final mine = widget.mineData;
    switch (_activeTab) {
      case 'approved':
        return mine.approved_requests ??
            mine.requests.where((r) => r.status.toLowerCase() == 'approved').toList();
      case 'pending':
        return mine.pending_requests ??
            mine.requests.where((r) => r.status.toLowerCase() == 'pending').toList();
      case 'rejected':
        return mine.rejected_requests ??
            mine.requests.where((r) => r.status.toLowerCase() == 'rejected').toList();
      case 'all':
      default:
        return mine.requests;
    }
  }

  int get _allCount => widget.mineData.requests.length;
  int get _approvedCount =>
      widget.mineData.approved_requests?.length ??
      widget.mineData.requests.where((r) => r.status.toLowerCase() == 'approved').length;
  int get _pendingCount =>
      widget.mineData.pending_requests?.length ??
      widget.mineData.requests.where((r) => r.status.toLowerCase() == 'pending').length;
  int get _rejectedCount =>
      widget.mineData.rejected_requests?.length ??
      widget.mineData.requests.where((r) => r.status.toLowerCase() == 'rejected').length;

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '—';
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return DateFormat('MMM d, yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredRequests;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'My Leave History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Track status, approved duration, and mentor reviews.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Horizontal Filter Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  _buildTabPill('all', 'All ($_allCount)'),
                  _buildTabPill('approved', 'Approved ($_approvedCount)'),
                  _buildTabPill('pending', 'Pending ($_pendingCount)'),
                  _buildTabPill('rejected', 'Rejected ($_rejectedCount)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Request List
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    size: 40,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No leave requests found in this view',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final req = list[index];
                final srNo = index + 1;
                return _buildRequestItem(req, srNo);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildTabPill(String tabKey, String label) {
    final isSelected = _activeTab == tabKey;

    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildRequestItem(LeaveRequest req, int srNo) {
    final statusColor = req.isApproved
        ? AppColors.success
        : (req.isRejected ? AppColors.danger : AppColors.warning);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Sr. No, Period, Days, Status badge
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.border,
                ),
                child: Center(
                  child: Text(
                    '$srNo',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${req.start_date} → ${req.end_date}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${req.days}d',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  req.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Second row: Type pill, Reason
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  req.typeLabel,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  req.reason,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (req.hasAttachment) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => LeaveAttachmentViewer.openAttachment(
                    context,
                    leaveId: req.id,
                    filename: req.attachment_name,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file_rounded, size: 14, color: AppColors.primaryInk),
                        SizedBox(width: 2),
                        Text(
                          'File',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 6),

          // Bottom metadata: Reviewer & Applied Date
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Reviewer
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 13,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        req.displayReviewer != null
                            ? '${req.displayReviewer}${req.reviewed_at != null ? ' • ${_formatDate(req.reviewed_at!)}' : ''}'
                            : 'Pending review',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: req.displayReviewer == null ? FontStyle.italic : FontStyle.normal,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Applied on
              Text(
                'Applied: ${_formatDate(req.created_at)}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),

          // If reviewer left a comment, show it below
          if (req.displayComment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 12,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      req.displayComment,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
