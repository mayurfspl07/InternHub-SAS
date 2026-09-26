import 'package:flutter/material.dart';
import '../../../shared/models/profile_overview_model.dart';
import '../../../shared/models/user_model.dart';
import '../profile_repository.dart';
import '../../../core/constants/app_colors.dart';

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

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: nationalPhoneDigits(widget.user.phone));
    _skillsController = TextEditingController(text: formatSkills(widget.user.skills));
    _bioController = TextEditingController(text: widget.user.bio ?? '');
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _skillsController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  List<String> get _liveSkills {
    return skillList(_skillsController.text);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

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
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update profile: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogBg = Colors.white;
    final borderColor = AppColors.border;
    final fieldBg = Colors.white;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    const coralColor = AppColors.primary;

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Title, Sparkle Icon, & Close button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: AppColors.primaryInk,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Profile Details',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Update your contact details, skill competencies, and personal summary.',
                          style: TextStyle(
                            fontSize: 12,
                            color: secondaryTextColor,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: borderColor),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // PHONE NUMBER
              Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: AppColors.primaryInk),
                  const SizedBox(width: 6),
                  Text(
                    'PHONE NUMBER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '+91 9876543210',
                  hintStyle: TextStyle(color: secondaryTextColor, fontSize: 14),
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: coralColor, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Primary mobile contact number.',
                style: TextStyle(fontSize: 11, color: secondaryTextColor),
              ),
              const SizedBox(height: 20),

              // SKILLS (COMMA SEPARATED)
              Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 16, color: AppColors.primaryInk),
                  const SizedBox(width: 6),
                  Text(
                    'SKILLS (COMMA SEPARATED)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _skillsController,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. ReactJS, Python, Flutter, Docker',
                  hintStyle: TextStyle(color: secondaryTextColor, fontSize: 14),
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: coralColor, width: 1.5),
                  ),
                ),
              ),

              // Live chip preview
              if (_liveSkills.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _liveSkills.map((skill) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Text(
                        skill,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 20),

              // BIO / SUMMARY
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 16, color: AppColors.primaryInk),
                  const SizedBox(width: 6),
                  Text(
                    'BIO / SUMMARY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: primaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bioController,
                maxLines: 4,
                minLines: 3,
                style: TextStyle(color: primaryTextColor, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Tell us about yourself, background, or goals...',
                  hintStyle: TextStyle(color: secondaryTextColor, fontSize: 14),
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: coralColor, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Submit Button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox.shrink()
                      : const Icon(Icons.check_rounded, size: 18),
                  label: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: coralColor,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: coralColor.withValues(alpha: 0.6),
                    disabledForegroundColor: AppColors.textSecondary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
