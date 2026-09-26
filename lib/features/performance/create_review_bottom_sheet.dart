import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';

class CreateReviewBottomSheet extends ConsumerStatefulWidget {
  const CreateReviewBottomSheet({super.key});

  @override
  ConsumerState<CreateReviewBottomSheet> createState() =>
      _CreateReviewBottomSheetState();
}

class _CreateReviewBottomSheetState
    extends ConsumerState<CreateReviewBottomSheet> {
  String? _selectedInternId;
  double _overallRating = 4.5;
  double _technicalRating = 4.5;
  double _communicationRating = 4.5;
  double _initiativeRating = 4.5;
  final _periodController = TextEditingController(text: 'Q3 2026 Milestone');
  final _strengthsController = TextEditingController(
      text: 'Superb widget modularity and clean architectural patterns.');
  final _improvementController = TextEditingController(
      text: 'Continue mastering platform channels and edge-case handling.');
  final _feedbackController = TextEditingController(
      text: 'Outstanding velocity and valuable contributor to the sprint team.');
  bool _isLoading = false;

  @override
  void dispose() {
    _periodController.dispose();
    _strengthsController.dispose();
    _improvementController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final interns = ref
        .read(appStateProvider)
        .users
        .where((u) => u.role == UserRole.intern)
        .toList();

    final targetInternId = _selectedInternId ?? (interns.isNotEmpty ? interns.first.id : '');
    if (targetInternId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an intern to review')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final payload = {
        'intern_id': targetInternId,
        'overall_rating': _overallRating,
        'technical_rating': _technicalRating,
        'communication_rating': _communicationRating,
        'initiative_rating': _initiativeRating,
        'strengths': _strengthsController.text.trim(),
        'improvements': _improvementController.text.trim(),
        'feedback': _feedbackController.text.trim(),
        'evaluation_period': _periodController.text.trim(),
      };

      await ref.read(appStateProvider.notifier).createReview(payload);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⭐ 360 Performance Review Published!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish review: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final interns = state.users.where((u) => u.role == UserRole.intern).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
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

            Text(
              'Submit 360 Performance Review ⭐',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Evaluate intern milestones, competencies, and areas for growth.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),

            // Intern Selector
            if (interns.isNotEmpty) ...[
              Text(
                'Select Intern',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedInternId ?? interns.first.id,
                    isExpanded: true,
                    dropdownColor: Colors.white,
                    items: interns.map((u) {
                      return DropdownMenuItem<String>(
                        value: u.id,
                        child: Text(u.name),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedInternId = val),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            CustomTextField(
              label: 'Evaluation Period',
              controller: _periodController,
            ),
            const SizedBox(height: 16),

            // Rating Sliders
            Text(
              'Overall Rating: ${_overallRating.toStringAsFixed(1)} / 5.0',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Slider(
              value: _overallRating,
              min: 1.0,
              max: 5.0,
              divisions: 8,
              activeColor: AppColors.primary,
              onChanged: (val) => setState(() => _overallRating = val),
            ),

            Text(
              'Technical Proficiency: ${_technicalRating.toStringAsFixed(1)} / 5.0',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Slider(
              value: _technicalRating,
              min: 1.0,
              max: 5.0,
              divisions: 8,
              activeColor: AppColors.primary,
              onChanged: (val) => setState(() => _technicalRating = val),
            ),

            Text(
              'Communication & Collaboration: ${_communicationRating.toStringAsFixed(1)} / 5.0',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Slider(
              value: _communicationRating,
              min: 1.0,
              max: 5.0,
              divisions: 8,
              activeColor: AppColors.info,
              onChanged: (val) => setState(() => _communicationRating = val),
            ),

            Text(
              'Initiative & Ownership: ${_initiativeRating.toStringAsFixed(1)} / 5.0',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Slider(
              value: _initiativeRating,
              min: 1.0,
              max: 5.0,
              divisions: 8,
              activeColor: AppColors.success,
              onChanged: (val) => setState(() => _initiativeRating = val),
            ),
            const SizedBox(height: 12),

            CustomTextField(
              label: 'Key Strengths',
              controller: _strengthsController,
              maxLines: 2,
            ),
            const SizedBox(height: 14),

            CustomTextField(
              label: 'Areas for Improvement',
              controller: _improvementController,
              maxLines: 2,
            ),
            const SizedBox(height: 14),

            CustomTextField(
              label: 'General Feedback',
              controller: _feedbackController,
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            CustomButton(
              text: _isLoading ? 'Publishing...' : 'Publish Evaluation',
              onPressed: _isLoading ? () {} : _handleSubmit,
            ),
          ],
        ),
      ),
    );
  }
}
