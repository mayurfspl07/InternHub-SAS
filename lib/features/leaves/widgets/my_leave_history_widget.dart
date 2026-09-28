import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/leave_model.dart';
import 'leave_attachment_viewer.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../core/utils/formatters.dart';

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

  String _formatDate(String dateStr) => formatDate(dateStr, fallback: '—');

  @override
  Widget build(BuildContext context) {
    final list = _filteredRequests;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
              const SizedBox(height: 2),
              Text(
                'Track status, approved duration, and mentor reviews.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
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
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
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
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: isSelected
                ? AppColors.onPrimary
                : AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildRequestItem(LeaveRequest req, int srNo) {

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
                    style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatDateRange(req.start_date, req.end_date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
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
                  style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip.fromString(req.status),
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
                  style: AppTypography.label.copyWith(color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  req.reason,
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                ),
              ),
              if (req.hasAttachment) ...[
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => LeaveAttachmentViewer.openAttachment(
                    context,
                    leaveId: req.id,
                    filename: req.attachment_name,
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.attach_file_rounded, size: 14, color: AppColors.primaryInk),
                        SizedBox(width: 2),
                        Text(
                          'Attachment',
                          style: AppTypography.label.copyWith(color: AppColors.primaryInk),
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
                        style: AppTypography.label.copyWith(fontStyle: req.displayReviewer == null ? FontStyle.italic : FontStyle.normal, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Applied on
              Text(
                'Applied ${_formatDate(req.created_at)}',
                style: AppTypography.label,
              ),
            ],
          ),

          // If reviewer left a comment, show it below
          if (req.displayComment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.ink.withValues(alpha: 0.03),
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
                      style: AppTypography.label.copyWith(fontStyle: FontStyle.italic, color: AppColors.ink),
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
