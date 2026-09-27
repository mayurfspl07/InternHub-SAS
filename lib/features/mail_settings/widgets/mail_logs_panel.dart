import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../mail_repository.dart';
import '../models/mail_models.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class MailLogsPanel extends StatefulWidget {
  final MailRepository repository;

  const MailLogsPanel({super.key, required this.repository});

  @override
  State<MailLogsPanel> createState() => _MailLogsPanelState();
}

class _MailLogsPanelState extends State<MailLogsPanel> {
  bool _isLoading = true;
  String? _errorMessage;
  SmtpDeliveryLogsResponse? _response;

  // Filter State
  String _selectedEmailType = 'all';
  String _selectedStatus = 'all';
  int _currentPage = 1;
  int _pageSize = 20;

  final List<Map<String, String>> _emailTypes = const [
    {'value': 'all', 'label': 'All Types'},
    {'value': 'welcome', 'label': 'Welcome'},
    {'value': 'leave_request', 'label': 'Leave Req'},
    {'value': 'leave_decision', 'label': 'Leave Dec'},
    {'value': 'assignment_new', 'label': 'New Task/Assign'},
    {'value': 'assignment_submit', 'label': 'Submitted'},
    {'value': 'assignment_grade', 'label': 'Graded'},
    {'value': 'task_assigned', 'label': 'Task Assigned'},
    {'value': 'test', 'label': 'Test'},
  ];

  final List<Map<String, String>> _statuses = const [
    {'value': 'all', 'label': 'All Statuses'},
    {'value': 'sent', 'label': 'Sent'},
    {'value': 'failed', 'label': 'Failed'},
    {'value': 'simulated', 'label': 'Simulated'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await widget.repository.getDeliveryLogs(
        page: _currentPage,
        pageSize: _pageSize,
        emailType: _selectedEmailType,
        status: _selectedStatus,
      );
      if (mounted) {
        setState(() {
          _response = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _onEmailTypeChanged(String? type) {
    if (type != null && type != _selectedEmailType) {
      setState(() {
        _selectedEmailType = type;
        _currentPage = 1;
      });
      _fetchLogs();
    }
  }

  void _onStatusChanged(String? status) {
    if (status != null && status != _selectedStatus) {
      setState(() {
        _selectedStatus = status;
        _currentPage = 1;
      });
      _fetchLogs();
    }
  }

  void _onPageSizeChanged(int? size) {
    if (size != null && size != _pageSize) {
      setState(() {
        _pageSize = size;
        _currentPage = 1;
      });
      _fetchLogs();
    }
  }

  String _formatDateTime(String raw) {
    if (raw.isEmpty) return '';
    DateTime? dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateFormat('MMM d, yyyy, h:mm:ss a').format(dt);
  }

  void _showLogDetailsDialog(SmtpDeliveryLog log) {

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Log Details #${log.id}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              _buildStatusBadge(log.status),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Event Type', log.typeDisplay),
                _buildDetailRow('Recipient', log.recipientName != null ? '${log.recipientName} (${log.recipientEmail})' : log.recipientEmail),
                _buildDetailRow('Subject', log.subject),
                _buildDetailRow('Sent At', _formatDateTime(log.sentAt)),
                if (log.errorMessage != null && log.errorMessage!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Error Message:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.dangerSoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                    ),
                    child: SelectableText(
                      log.errorMessage!,
                      style: const TextStyle(fontSize: 12, color: AppColors.danger, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (log.errorMessage != null && log.errorMessage!.trim().isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: log.errorMessage!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error copied to clipboard'), behavior: SnackBarBehavior.floating),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy Error'),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FILTERS STRIP
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Delivery Filters',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primaryTextColor),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Refresh Logs',
                      onPressed: _fetchLogs,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Email Type Filter
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedEmailType,
                        decoration: _filterInputDecoration('Type', borderColor),
                        style: TextStyle(fontSize: 12, color: primaryTextColor),
                        isExpanded: true,
                        items: _emailTypes.map((t) {
                          return DropdownMenuItem<String>(
                            value: t['value'],
                            child: Text(t['label']!, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: _onEmailTypeChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status Filter
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedStatus,
                        decoration: _filterInputDecoration('Status', borderColor),
                        style: TextStyle(fontSize: 12, color: primaryTextColor),
                        isExpanded: true,
                        items: _statuses.map((s) {
                          return DropdownMenuItem<String>(
                            value: s['value'],
                            child: Text(s['label']!, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: _onStatusChanged,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Page Size
                    SizedBox(
                      width: 80,
                      child: DropdownButtonFormField<int>(
                        initialValue: _pageSize,
                        decoration: _filterInputDecoration('Rows', borderColor),
                        style: TextStyle(fontSize: 12, color: primaryTextColor),
                        items: const [
                          DropdownMenuItem<int>(value: 10, child: Text('10')),
                          DropdownMenuItem<int>(value: 20, child: Text('20')),
                          DropdownMenuItem<int>(value: 50, child: Text('50')),
                        ],
                        onChanged: _onPageSizeChanged,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // CONTENT
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 36, color: AppColors.danger),
                    const SizedBox(height: 10),
                    Text(
                      'Failed to load delivery logs',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(_errorMessage!, style: TextStyle(fontSize: 12, color: secondaryTextColor), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _fetchLogs,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_response == null || _response!.logs.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
              child: Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.mark_email_read_outlined, size: 28, color: secondaryTextColor),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No email delivery logs found',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primaryTextColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Emails dispatched by your organization will appear here.',
                    style: TextStyle(fontSize: 12, color: secondaryTextColor),
                  ),
                ],
              ),
            )
          else ...[
            // LOGS LIST
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _response!.logs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final log = _response!.logs[index];

                return InkWell(
                  onTap: () => _showLogDetailsDialog(log),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  _buildTypeBadge(log.typeDisplay),
                                  _buildStatusBadge(log.status),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDateTime(log.sentAt),
                              style: TextStyle(fontSize: 11, color: secondaryTextColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          log.subject,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.person_outline_rounded, size: 14, color: secondaryTextColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                log.recipientName != null
                                    ? '${log.recipientName} (${log.recipientEmail})'
                                    : log.recipientEmail,
                                style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (log.isFailed && log.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              log.errorMessage!,
                              style: const TextStyle(fontSize: 11, color: AppColors.danger),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // PAGINATION BAR
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Page ${_response!.page} of ${_response!.totalPages} (${_response!.total} logs)',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _currentPage > 1
                          ? () {
                              setState(() {
                                _currentPage--;
                              });
                              _fetchLogs();
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Previous'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _currentPage < _response!.totalPages
                          ? () {
                              setState(() {
                                _currentPage++;
                              });
                              _fetchLogs();
                            }
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Next'),
                    ),
                  ],
                ),
              ],
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ==========================================
  // BADGES & HELPERS
  // ==========================================

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label = status.toUpperCase();

    switch (status.toLowerCase()) {
      case 'sent':
        bg = AppColors.success.withValues(alpha: 0.15);
        fg = AppColors.success;
        break;
      case 'failed':
        bg = AppColors.danger.withValues(alpha: 0.15);
        fg = AppColors.danger;
        break;
      case 'simulated':
        bg = AppColors.info.withValues(alpha: 0.15);
        fg = AppColors.info;
        break;
      default:
        bg = AppColors.textTertiary.withValues(alpha: 0.15);
        fg = AppColors.textTertiary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryInk,
        ),
      ),
    );
  }

  InputDecoration _filterInputDecoration(String label, Color borderColor) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12),
      isDense: true,
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: borderColor),
      ),
    );
  }
}
