import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/leave_model.dart';
import '../leave_repository.dart';
import 'leave_attachment_viewer.dart';
import 'review_leave_dialog.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../shared/widgets/pagination_bar.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../shared/widgets/app_avatar.dart';
import '../../../core/utils/formatters.dart';

class ManageLeaveQueueWidget extends StatefulWidget {
  const ManageLeaveQueueWidget({super.key});

  @override
  State<ManageLeaveQueueWidget> createState() => ManageLeaveQueueWidgetState();
}

class ManageLeaveQueueWidgetState extends State<ManageLeaveQueueWidget> {
  /// Reload the current page (pull-to-refresh on the Approvals tab).
  Future<void> reload() => _fetchQueue();

  String _activeStatus = 'pending'; // pending | approved | rejected
  int _currentPage = 1;
  bool _isLoading = false;
  PaginatedLeaveResponse? _response;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchQueue();
  }

  Future<void> _fetchQueue({int? page, String? status}) async {
    final targetPage = page ?? _currentPage;
    final targetStatus = status ?? _activeStatus;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await LeaveRepository().getManage(
        page: targetPage,
        status: targetStatus,
      );

      if (mounted) {
        setState(() {
          _response = res;
          _currentPage = targetPage;
          _activeStatus = targetStatus;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = apiErrorMessage(e);
        });
      }
    }
  }

  void _onTabChanged(String newStatus) {
    if (_activeStatus == newStatus && _response != null) return;
    _fetchQueue(page: 1, status: newStatus);
  }

  @override
  Widget build(BuildContext context) {
    final requests = _response?.requests ?? [];
    final totalCount = _response?.total ?? requests.length;
    final totalPages = _response?.total_pages ?? 1;

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
          // Title, then the status filter on its own row so neither is squeezed on a phone.
          Text(
            'Leave requests ($totalCount)',
            style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _buildStatusTab('pending', 'Pending'),
                _buildStatusTab('approved', 'Approved'),
                _buildStatusTab('rejected', 'Rejected'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Loading, Error, or Queue List
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (_errorMessage != null)
            LoadErrorView(
              title: "Couldn't load leave requests",
              message: _errorMessage!,
              onRetry: () => _fetchQueue(),
              compact: true,
            )
          else if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.done_all_rounded,
                    size: 40,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No $_activeStatus leave requests',
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: requests.length,
              separatorBuilder: (_, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final req = requests[index];
                final srNo = ((_currentPage - 1) * (_response?.page_size ?? 10)) + index + 1;
                return _buildQueueCard(req, srNo);
              },
            ),

            const SizedBox(height: 18),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 14),

            PaginationBar(
              page: _currentPage,
              totalPages: totalPages,
              totalItems: totalCount,
              itemLabel: 'requests',
              isLoading: _isLoading,
              onPageChanged: (p) => _fetchQueue(page: p),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusTab(String key, String label) {
    final isSelected = _activeStatus == key;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        child: InkWell(
          onTap: () => _onTabChanged(key),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQueueCard(LeaveRequest req, int srNo) {

    return Container(
      padding: const EdgeInsets.all(14),
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
          // Row 1: Sr No, Intern Avatar & Name, Status Pill
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
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

              AppAvatar(size: 28, fallbackText: req.userName),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  req.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 8),
              StatusChip.fromString(req.status),
            ],
          ),
          const SizedBox(height: 10),

          // Dates, then type and length
          Text(
            formatDateRange(req.start_date, req.end_date),
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  req.typeLabel,
                  style: AppTypography.label.copyWith(color: AppColors.ink),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  plural(req.days, 'day'),
                  style: AppTypography.label.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Reason & Attachment
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  req.reason,
                  style: AppTypography.caption.copyWith(fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                ),
              ),
              if (req.hasAttachment) ...[
                const SizedBox(width: 8),
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
                        SizedBox(width: 3),
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

          // If already reviewed, show reviewer details
          if (req.displayReviewer != null || req.displayComment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 13,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Reviewed by ${req.displayReviewer ?? 'a reviewer'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                if (req.displayComment.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '("${req.displayComment}")',
                      style: AppTypography.label.copyWith(fontStyle: FontStyle.italic, color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ],

          // Actions for PENDING requests (Approve / Reject buttons)
          if (req.isPending) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Approve Button (Yellow background)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.ink,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 44),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16, color: AppColors.ink),
                  label: Text(
                    'Approve',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                  onPressed: () {
                    ReviewLeaveDialog.show(
                      context,
                      request: req,
                      isApprove: true,
                      onSuccess: () => _fetchQueue(),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Reject Button (Outlined Red)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerInk,
                    side: const BorderSide(color: AppColors.danger, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: const Size(0, 44),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.dangerInk),
                  label: Text(
                    'Reject',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.dangerInk),
                  ),
                  onPressed: () {
                    ReviewLeaveDialog.show(
                      context,
                      request: req,
                      isApprove: false,
                      onSuccess: () => _fetchQueue(),
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
