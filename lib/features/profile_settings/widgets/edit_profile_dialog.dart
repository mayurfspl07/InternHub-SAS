import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/models/profile_overview_model.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../profile_repository.dart';
import '../../../core/api/api_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';

class EditProfileDialog extends StatefulWidget {
  final UserModel user;
  final ValueChanged<UserModel> onSuccess;

  const EditProfileDialog({
    super.key,
    required this.user,
    required this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required UserModel user,
    required ValueChanged<UserModel> onSuccess,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditProfileDialog(
        user: user,
        onSuccess: onSuccess,
      ),
    );
  }

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late final TextEditingController _phoneController;
  late final TextEditingController _skillsController;
  late final TextEditingController _bioController;
  late final String _initialPhone;
  late final String _initialSkills;
  late final String _initialBio;

  bool _isSaving = false;
  String? _phoneError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _initialPhone = nationalPhoneDigits(widget.user.phone);
    _initialSkills = formatSkills(widget.user.skills);
    _initialBio = widget.user.bio ?? '';
    _phoneController = TextEditingController(text: _initialPhone);
    _skillsController = TextEditingController(text: _initialSkills);
    _bioController = TextEditingController(text: _initialBio);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _skillsController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  bool get _isDirty =>
      _phoneController.text != _initialPhone ||
      _skillsController.text != _initialSkills ||
      _bioController.text != _initialBio;

  String? _validatePhone(String value) {
    final digits = value.trim();
    if (digits.isEmpty) return null; // phone is optional
    if (!ApiConfig.isValidPhone(digits)) return 'Enter a valid 10-digit mobile number';
    return null;
  }

  Future<void> _save() async {
    final phoneError = _validatePhone(_phoneController.text);
    if (phoneError != null) {
      setState(() => _phoneError = phoneError);
      return;
    }
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    try {
      final updated = await ProfileRepository().updateProfile(
        phone: _phoneController.text,
        skills: _skillsController.text,
        bio: _bioController.text,
      );

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSuccess(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveError = apiErrorMessage(e);
        });
      }
    }
  }

  /// Leaving with unsaved edits asks first.
  Future<void> _close() async {
    if (_isSaving) return;
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text("Your edits haven't been saved."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.dangerInk),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final liveSkills = skillList(_skillsController.text);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Edit profile', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _isSaving ? null : _close,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Your name, email and role are managed by your admin.',
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: 20),
                      CustomTextField(
                        label: 'Mobile number (optional)',
                        hintText: '98765 43210',
                        prefixIcon: Icons.phone_outlined,
                        prefixText: '+91 ',
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.telephoneNumberNational],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        errorText: _phoneError,
                        enabled: !_isSaving,
                        onChanged: (v) => setState(() => _phoneError = null),
                      ),
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'Skills',
                        hintText: 'e.g. Flutter, Python, Figma',
                        helperText: 'Separate skills with commas',
                        prefixIcon: Icons.auto_awesome_outlined,
                        controller: _skillsController,
                        textInputAction: TextInputAction.next,
                        enabled: !_isSaving,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (liveSkills.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final skill in liveSkills)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(skill, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      CustomTextField(
                        label: 'About',
                        hintText: 'Your background and what you work on',
                        controller: _bioController,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        enabled: !_isSaving,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (_saveError != null) ...[
                        const SizedBox(height: 12),
                        Text(_saveError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: _isSaving ? null : _close, child: const Text('Cancel')),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isSaving || !_isDirty ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              minimumSize: const Size(96, 44),
                              elevation: 0,
                              shape: const StadiumBorder(),
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                                  )
                                : const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
