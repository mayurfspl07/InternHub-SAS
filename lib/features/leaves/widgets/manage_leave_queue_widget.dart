import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/models/leave_model.dart';
import '../leave_repository.dart';
import 'leave_attachment_viewer.dart';
import 'review_leave_dialog.dart';

class ManageLeaveQueueWidget extends StatefulWidget {
  const ManageLeaveQueueWidget({super.key});

  @override
  State<ManageLeaveQueueWidget> createState() => _ManageLeaveQueueWidgetState();
}

class _ManageLeaveQueueWidgetState extends State<ManageLeaveQueueWidget> {
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
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final requests = _response?.requests ?? [];
    final totalCount = _response?.total ?? requests.length;
    final totalPages = _response?.total_pages ?? 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Row & Segmented Tabs Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Manage Leave Requests ($totalCount)',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
              ),
              // Segmented Status Pill
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStatusTab('pending', 'Pending', isDark),
                    _buildStatusTab('approved', 'Approved', isDark),
                    _buildStatusTab('rejected', 'Rejected', isDark),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Loading, Error, or Queue List
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          else if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 36, color: AppColors.danger),
                  const SizedBox(height: 8),
                  Text(_errorMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => _fetchQueue(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (requests.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(
                    Icons.done_all_rounded,
                    size: 40,
                    color: isDark ? Colors.white30 : AppColors.textTertiaryLight,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No $_activeStatus leave requests found',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                    ),
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
                return _buildQueueCard(req, srNo, isDark);
              },
            ),

            const SizedBox(height: 18),
            Divider(height: 1, color: isDark ? AppColors.borderDark : AppColors.borderLight),
            const SizedBox(height: 14),

            // Pagination Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Page $_currentPage of $totalPages ($totalCount ${totalCount == 1 ? 'request' : 'requests'})',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      onPressed: _currentPage > 1
                          ? () => _fetchQueue(page: _currentPage - 1)
                          : null,
                      child: const Text('< Prev', style: TextStyle(fontSize: 11.5)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.cardYellow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_currentPage',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      onPressed: _currentPage < totalPages
                          ? () => _fetchQueue(page: _currentPage + 1)
                          : null,
                      child: const Text('Next >', style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusTab(String key, String label, bool isDark) {
    final isSelected = _activeStatus == key;

    return GestureDetector(
      onTap: () => _onTabChanged(key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (key == 'pending' ? AppColors.cardYellow : (isDark ? AppColors.primary : Colors.black87))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (key == 'pending' ? Colors.black : Colors.white)
                : (isDark ? Colors.white60 : AppColors.textSecondaryLight),
          ),
        ),
      ),
    );
  }

  Widget _buildQueueCard(LeaveRequest req, int srNo, bool isDark) {
    final initial = req.userName.isNotEmpty ? req.userName[0].toLowerCase() : 'i';
    final statusColor = req.isApproved
        ? AppColors.success
        : (req.isRejected ? AppColors.danger : AppColors.warning);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDark : const Color(0xFFE5E7EB),
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
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                ),
                child: Center(
                  child: Text(
                    '$srNo',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Circular Avatar with initial
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  req.userName,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimaryLight,
                  ),
                ),
              ),

              // Status Pill
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
          const SizedBox(height: 10),

          // Row 2: Duration, Type, Days
          Row(
            children: [
              Expanded(
                child: Text(
                  '${req.start_date} → ${req.end_date}',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  req.typeLabel,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${req.days} day(s)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
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
                  'Reason: "${req.reason}"',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                  ),
                ),
              ),
              if (req.hasAttachment) ...[
                const SizedBox(width: 8),
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
                        Icon(Icons.attach_file_rounded, size: 14, color: AppColors.primary),
                        SizedBox(width: 3),
                        Text(
                          'Attachment',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.primary),
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
            Divider(height: 1, color: isDark ? AppColors.borderDark : AppColors.borderLight),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 13,
                  color: isDark ? Colors.white38 : AppColors.textTertiaryLight,
                ),
                const SizedBox(width: 4),
                Text(
                  'Reviewed by ${req.displayReviewer ?? 'Mentor'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                  ),
                ),
                if (req.displayComment.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '("${req.displayComment}")',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                      ),
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
                    backgroundColor: AppColors.cardYellow,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.check_rounded, size: 16, color: Colors.black),
                  label: Text(
                    'Approve',
                    style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black),
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
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.danger),
                  label: Text(
                    'Reject',
                    style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.danger),
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
