import 'package:flutter/material.dart';
import '../mail_repository.dart';
import '../models/mail_models.dart';
import '../../../core/constants/app_colors.dart';

class MailConfigPanel extends StatefulWidget {
  final OrgSmtpConfig initialConfig;
  final MailRepository repository;
  final ValueChanged<OrgSmtpConfig> onConfigUpdated;

  const MailConfigPanel({
    super.key,
    required this.initialConfig,
    required this.repository,
    required this.onConfigUpdated,
  });

  @override
  State<MailConfigPanel> createState() => _MailConfigPanelState();
}

class _MailConfigPanelState extends State<MailConfigPanel> {
  late OrgSmtpConfig _savedConfig;

  // Form State
  late bool _isEnabled;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  bool _isChangingPassword = false;
  late TextEditingController _senderEmailController;
  late TextEditingController _senderNameController;
  late OrgSmtpEncryption _encryption;

  // Notification switches
  late bool _notifyWelcome;
  late bool _notifyLeaveRequest;
  late bool _notifyLeaveDecision;
  late bool _notifyAssignmentNew;
  late bool _notifyAssignmentSubmit;
  late bool _notifyAssignmentGrade;
  late bool _notifyTaskAssigned;
  late bool _notifyAttendanceAlert;

  // Test Email
  final TextEditingController _testEmailController = TextEditingController();
  bool _isTesting = false;
  TestOrgSmtpResponse? _testResult;

  // Save State
  bool _isSaving = false;

  final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _savedConfig = widget.initialConfig;
    _hostController = TextEditingController();
    _portController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _senderEmailController = TextEditingController();
    _senderNameController = TextEditingController();
    _populateFromConfig(_savedConfig);
  }

  @override
  void didUpdateWidget(covariant MailConfigPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialConfig != widget.initialConfig) {
      _savedConfig = widget.initialConfig;
      _populateFromConfig(_savedConfig);
    }
  }

  void _populateFromConfig(OrgSmtpConfig config) {
    _isEnabled = config.isEnabled;
    _hostController.text = config.host;
    _portController.text = config.port > 0 ? config.port.toString() : '587';
    _usernameController.text = config.username;
    _passwordController.text = '';
    _isChangingPassword = false;
    _senderEmailController.text = config.senderEmail;
    _senderNameController.text = config.senderName;
    _encryption = config.encryption;

    _notifyWelcome = config.notifyWelcome;
    _notifyLeaveRequest = config.notifyLeaveRequest;
    _notifyLeaveDecision = config.notifyLeaveDecision;
    _notifyAssignmentNew = config.notifyAssignmentNew;
    _notifyAssignmentSubmit = config.notifyAssignmentSubmit;
    _notifyAssignmentGrade = config.notifyAssignmentGrade;
    _notifyTaskAssigned = config.notifyTaskAssigned;
    _notifyAttendanceAlert = config.notifyAttendanceAlert;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _senderEmailController.dispose();
    _senderNameController.dispose();
    _testEmailController.dispose();
    super.dispose();
  }

  bool _isFormDirty() {
    final port = int.tryParse(_portController.text.trim()) ?? 0;
    if (_isEnabled != _savedConfig.isEnabled) return true;
    if (_hostController.text.trim() != _savedConfig.host) return true;
    if (port != _savedConfig.port) return true;
    if (_usernameController.text.trim() != _savedConfig.username) return true;
    if (_encryption != _savedConfig.encryption) return true;
    if (_senderEmailController.text.trim() != _savedConfig.senderEmail) return true;
    if (_senderNameController.text.trim() != _savedConfig.senderName) return true;
    if (_isChangingPassword && _passwordController.text.isNotEmpty) return true;
    return false;
  }

  void _resetForm() {
    setState(() {
      _populateFromConfig(_savedConfig);
      _testResult = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Form reset to saved settings.', style: const TextStyle()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendTestEmail() async {
    final target = _testEmailController.text.trim();
    if (target.isEmpty || !_emailRegex.hasMatch(target)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid target email address for testing.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final isDirty = _isFormDirty();
    final port = int.tryParse(_portController.text.trim()) ?? 587;
    final host = _hostController.text.trim();

    if (isDirty && host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMTP Host is required to test unsaved configuration.'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final payload = <String, dynamic>{
      'target_email': target,
    };

    if (isDirty) {
      payload['host'] = host;
      payload['port'] = port > 0 ? port : 587;
      payload['username'] = _usernameController.text.trim();
      payload['encryption'] = _encryption.toApi();
      payload['sender_name'] = _senderNameController.text.trim().isNotEmpty
          ? _senderNameController.text.trim()
          : 'InternHub Workspace';
      payload['sender_email'] = _senderEmailController.text.trim().isNotEmpty
          ? _senderEmailController.text.trim()
          : target;

      if (_isChangingPassword && _passwordController.text.isNotEmpty) {
        payload['password'] = _passwordController.text;
      }
    }

    try {
      final res = await widget.repository.testSmtp(payload);
      if (mounted) {
        setState(() {
          _testResult = res;
          _isTesting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResult = TestOrgSmtpResponse(
            success: false,
            message: e.toString().replaceAll('Exception: ', ''),
          );
          _isTesting = false;
        });
      }
    }
  }

  Future<void> _saveConfig() async {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      _showError('Port must be a valid integer between 1 and 65535.');
      return;
    }

    if (_isEnabled) {
      if (_hostController.text.trim().isEmpty) {
        _showError('SMTP Host is required when Custom SMTP is active.');
        return;
      }
      if (_usernameController.text.trim().isEmpty) {
        _showError('SMTP Username is required when Custom SMTP is active.');
        return;
      }
      if (!_savedConfig.hasPassword && _passwordController.text.isEmpty) {
        _showError('SMTP Password is required when enabling Custom SMTP.');
        return;
      }
      if (_isChangingPassword && _passwordController.text.isEmpty) {
        _showError('Please enter a new password or click "Keep Saved Password".');
        return;
      }
    }

    final senderEmail = _senderEmailController.text.trim();
    if (senderEmail.isNotEmpty && !_emailRegex.hasMatch(senderEmail)) {
      _showError('Sender Email is not a valid email address.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final payload = <String, dynamic>{
      'is_enabled': _isEnabled,
      'host': _hostController.text.trim(),
      'port': port,
      'username': _usernameController.text.trim(),
      'encryption': _encryption.toApi(),
      'sender_name': _senderNameController.text.trim(),
      'sender_email': senderEmail,
      'notify_welcome': _notifyWelcome,
      'notify_leave_request': _notifyLeaveRequest,
      'notify_leave_decision': _notifyLeaveDecision,
      'notify_assignment_new': _notifyAssignmentNew,
      'notify_assignment_submit': _notifyAssignmentSubmit,
      'notify_assignment_grade': _notifyAssignmentGrade,
      'notify_task_assigned': _notifyTaskAssigned,
      'notify_attendance_alert': _notifyAttendanceAlert,
    };

    if (_isChangingPassword && _passwordController.text.isNotEmpty) {
      payload['password'] = _passwordController.text;
    }

    try {
      final updated = await widget.repository.saveSmtpConfig(payload);
      if (mounted) {
        setState(() {
          _savedConfig = updated;
          _populateFromConfig(updated);
          _isSaving = false;
        });
        widget.onConfigUpdated(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mail configuration saved successfully.', style: const TextStyle()),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        _showError('Failed to save configuration: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
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
          // CARD 1: CUSTOM SMTP SERVICE
          _buildCard(
            cardBg,
            borderColor,
            Column(
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
                            _isEnabled ? 'Custom SMTP Active' : 'Custom SMTP Disabled',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: primaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isEnabled
                                ? 'Custom tenant SMTP is active and will be used for all outgoing emails.'
                                : 'Platform SMTP fallback will be used for outgoing system notifications.',
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isEnabled,
                      activeTrackColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() {
                          _isEnabled = val;
                        });
                      },
                    ),
                  ],
                ),
                if (!_isEnabled) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.info),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'When disabled, event notification preferences below remain active, but emails are dispatched using the platform\'s shared default SMTP server.',
                            style: TextStyle(fontSize: 12, color: AppColors.infoInk),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // CARD 2: SMTP SERVER CONFIGURATION
          _buildCard(
            cardBg,
            borderColor,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SMTP Server Configuration',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 14),

                // Host
                _buildFieldLabel('SMTP Host', isRequired: _isEnabled, secondaryTextColor: secondaryTextColor),
                const SizedBox(height: 6),
                TextField(
                  controller: _hostController,
                  decoration: _inputDecoration('smtp.sendgrid.net', borderColor),
                  style: TextStyle(fontSize: 14, color: primaryTextColor),
                ),
                const SizedBox(height: 14),

                // Port & Port chips
                _buildFieldLabel('SMTP Port', isRequired: true, secondaryTextColor: secondaryTextColor),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('587', borderColor),
                        style: TextStyle(fontSize: 14, color: primaryTextColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildPortChip('587', OrgSmtpEncryption.tls),
                          _buildPortChip('465', OrgSmtpEncryption.ssl),
                          _buildPortChip('25', OrgSmtpEncryption.none),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Username
                _buildFieldLabel('SMTP Username', isRequired: _isEnabled, secondaryTextColor: secondaryTextColor),
                const SizedBox(height: 6),
                TextField(
                  controller: _usernameController,
                  decoration: _inputDecoration('e.g. apikey or user@domain.com', borderColor),
                  style: TextStyle(fontSize: 14, color: primaryTextColor),
                ),
                const SizedBox(height: 14),

                // Encryption Segmented Radio
                _buildFieldLabel('Encryption', isRequired: true, secondaryTextColor: secondaryTextColor),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildEncryptionChip('TLS (rec. 587)', OrgSmtpEncryption.tls),
                    _buildEncryptionChip('SSL (465)', OrgSmtpEncryption.ssl),
                    _buildEncryptionChip('None (25)', OrgSmtpEncryption.none),
                  ],
                ),
                const SizedBox(height: 14),

                // Password UX
                _buildFieldLabel('SMTP Password', isRequired: _isEnabled && !_savedConfig.hasPassword, secondaryTextColor: secondaryTextColor),
                const SizedBox(height: 6),
                if (_savedConfig.hasPassword && !_isChangingPassword)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              '••••••••••••••••',
                              style: TextStyle(fontSize: 16, color: secondaryTextColor, letterSpacing: 2),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Encrypted & Stored',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isChangingPassword = true;
                            });
                          },
                          child: const Text('Change Password'),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        enableSuggestions: false,
                        autocorrect: false,
                        decoration: _inputDecoration('Enter new password', borderColor),
                        style: TextStyle(fontSize: 14, color: primaryTextColor),
                      ),
                      if (_savedConfig.hasPassword) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _passwordController.clear();
                                _isChangingPassword = false;
                              });
                            },
                            icon: const Icon(Icons.undo_rounded, size: 16),
                            label: const Text('Keep Saved Password'),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // CARD 3: SENDER IDENTITY
          _buildCard(
            cardBg,
            borderColor,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sender Identity',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 14),
                _buildFieldLabel('Sender Name (Optional)', secondaryTextColor: secondaryTextColor),
                const SizedBox(height: 6),
                TextField(
                  controller: _senderNameController,
                  decoration: _inputDecoration('e.g. InternHub Workspace', borderColor),
                  style: TextStyle(fontSize: 14, color: primaryTextColor),
                ),
                const SizedBox(height: 14),
                _buildFieldLabel('Sender Email (Optional)', secondaryTextColor: secondaryTextColor),
                const SizedBox(height: 6),
                TextField(
                  controller: _senderEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration('notifications@yourcompany.com', borderColor),
                  style: TextStyle(fontSize: 14, color: primaryTextColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // CARD 4: EMAIL NOTIFICATION PREFERENCES
          _buildCard(
            cardBg,
            borderColor,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email Notification Preferences',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose which organization events trigger outgoing emails to users.',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
                const SizedBox(height: 12),
                _buildNotificationTile('Welcome / Invite', 'Send email when a new user is invited', _notifyWelcome, (v) => setState(() => _notifyWelcome = v), borderColor),
                _buildNotificationTile('Leave Application', 'Notify mentors/admins when an intern submits a leave request', _notifyLeaveRequest, (v) => setState(() => _notifyLeaveRequest = v), borderColor),
                _buildNotificationTile('Leave Decision', 'Notify interns when their leave is approved or rejected', _notifyLeaveDecision, (v) => setState(() => _notifyLeaveDecision = v), borderColor),
                _buildNotificationTile('New Assignment', 'Notify interns when a new assignment is posted', _notifyAssignmentNew, (v) => setState(() => _notifyAssignmentNew = v), borderColor),
                _buildNotificationTile('Assignment Submitted', 'Notify reviewers when an intern submits a solution', _notifyAssignmentSubmit, (v) => setState(() => _notifyAssignmentSubmit = v), borderColor),
                _buildNotificationTile('Assignment Graded', 'Notify interns when their assignment is reviewed/graded', _notifyAssignmentGrade, (v) => setState(() => _notifyAssignmentGrade = v), borderColor),
                _buildNotificationTile('Task Assigned / Reassigned', 'Notify team members when assigned to tasks', _notifyTaskAssigned, (v) => setState(() => _notifyTaskAssigned = v), borderColor),
                _buildNotificationTile('Attendance Alert', 'Notify supervisors of abnormal absence or clock-in delay', _notifyAttendanceAlert, (v) => setState(() => _notifyAttendanceAlert = v), borderColor, isLast: true),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // CARD 5: TEST EMAIL DELIVERY
          _buildCard(
            cardBg,
            borderColor,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Test Email Delivery',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Verify outgoing SMTP connectivity by sending a test message.',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
                const SizedBox(height: 14),
                _buildFieldLabel('Recipient Email *', secondaryTextColor: secondaryTextColor),
                const SizedBox(height: 6),
                TextField(
                  controller: _testEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration('admin@example.com', borderColor),
                  style: TextStyle(fontSize: 14, color: primaryTextColor),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: _isTesting ? null : _sendTestEmail,
                    icon: _isTesting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      _isTesting ? 'Sending Test...' : 'Send Test Email',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _testResult!.success
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _testResult!.success
                            ? AppColors.success.withValues(alpha: 0.3)
                            : AppColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _testResult!.success ? Icons.check_circle_rounded : Icons.error_rounded,
                          size: 18,
                          color: _testResult!.success ? AppColors.success : AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testResult!.message,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _testResult!.success ? AppColors.success : AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // FOOTER ACTIONS
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : _resetForm,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Reset',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveConfig,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _isSaving ? 'Saving Changes...' : 'Save Changes',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ==========================================
  // HELPER WIDGETS
  // ==========================================

  Widget _buildCard(Color bg, Color border, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }

  Widget _buildFieldLabel(String label, {bool isRequired = false, required Color secondaryTextColor}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secondaryTextColor),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          const Text('*', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
        ],
      ],
    );
  }

  InputDecoration _inputDecoration(String hint, Color borderColor) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _buildPortChip(String portStr, OrgSmtpEncryption defaultEnc) {
    final isSelected = _portController.text.trim() == portStr;
    return ChoiceChip(
      label: Text(portStr),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _portController.text = portStr;
            _encryption = defaultEnc;
          });
        }
      },
    );
  }

  Widget _buildEncryptionChip(String label, OrgSmtpEncryption enc) {
    final isSelected = _encryption == enc;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _encryption = enc;
          });
        }
      },
    );
  }

  Widget _buildNotificationTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    Color borderColor, {
    bool isLast = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: value,
                activeTrackColor: AppColors.primary,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: borderColor),
      ],
    );
  }
}
