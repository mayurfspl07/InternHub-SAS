import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/state/app_state_provider.dart';
import '../../../shared/models/user_model.dart';
import '../../announcements/widgets/announcement_dialog.dart';
import '../../attendance/checkin_checkout_screen.dart';
import '../../performance/widgets/performance_review_dialog.dart';

class _QuickAction {
  final String label;
  final String hint;
  final IconData icon;
  final Color tint;
  final Color ink;
  final void Function(BuildContext sheetContext) onTap;

  const _QuickAction({
    required this.label,
    required this.hint,
    required this.icon,
    required this.tint,
    required this.ink,
    required this.onTap,
  });
}

/// Bottom sheet opened by the center "+" of the bottom nav. Every action
/// reuses an existing screen, route or dialog.
class QuickActionSheet {
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    required UserRole role,
    required ValueChanged<int> onSelectTab,
  }) {
    final actions = _actionsFor(context, ref, role, onSelectTab);

    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 0, AppSpacing.p20, AppSpacing.p20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick actions', style: AppTypography.section),
              const SizedBox(height: 4),
              Text('Jump straight into the things you do most.', style: AppTypography.caption),
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [for (final action in actions) _ActionTile(action: action)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<_QuickAction> _actionsFor(
    BuildContext context,
    WidgetRef ref,
    UserRole role,
    ValueChanged<int> onSelectTab,
  ) {
    void closeThen(BuildContext sheetContext, VoidCallback next) {
      Navigator.pop(sheetContext);
      next();
    }

    if (role == UserRole.intern) {
      return [
        _QuickAction(
          label: 'Check in / out',
          hint: 'Selfie + location',
          icon: Icons.fingerprint_rounded,
          tint: AppColors.butter,
          ink: AppColors.butterInk,
          onTap: (c) => closeThen(c, () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckinCheckoutScreen()));
          }),
        ),
        _QuickAction(
          label: 'Apply leave',
          hint: 'Request time off',
          icon: Icons.beach_access_rounded,
          tint: AppColors.peach,
          ink: AppColors.peachInk,
          onTap: (c) => closeThen(c, () => onSelectTab(3)),
        ),
        _QuickAction(
          label: 'Post standup',
          hint: "Today's update",
          icon: Icons.chat_bubble_outline_rounded,
          tint: AppColors.lavender,
          ink: AppColors.lavenderInk,
          onTap: (c) => closeThen(c, () => Navigator.pushNamed(context, '/standup')),
        ),
        _QuickAction(
          label: 'Assignments',
          hint: 'Submit your work',
          icon: Icons.assignment_outlined,
          tint: AppColors.sage,
          ink: AppColors.sageInk,
          onTap: (c) => closeThen(c, () => Navigator.pushNamed(context, '/intern-assignments')),
        ),
      ];
    }

    return [
      _QuickAction(
        label: 'New announcement',
        hint: 'Notify everyone',
        icon: Icons.campaign_outlined,
        tint: AppColors.butter,
        ink: AppColors.butterInk,
        onTap: (c) => closeThen(c, () async {
          final created = await AnnouncementDialog.show(context);
          if (created == true) ref.read(appStateProvider.notifier).fetchAnnouncements();
        }),
      ),
      _QuickAction(
        label: 'Write review',
        hint: 'Rate an intern',
        icon: Icons.stars_outlined,
        tint: AppColors.peach,
        ink: AppColors.peachInk,
        onTap: (c) => closeThen(c, () async {
          final created = await PerformanceReviewDialog.show(context);
          if (created == true) ref.read(appStateProvider.notifier).fetchReviews();
        }),
      ),
      _QuickAction(
        label: 'Invite intern',
        hint: 'Share a join link',
        icon: Icons.link_rounded,
        tint: AppColors.lavender,
        ink: AppColors.lavenderInk,
        onTap: (c) => closeThen(c, () => Navigator.pushNamed(context, '/invite-links')),
      ),
      _QuickAction(
        label: 'Announcements',
        hint: 'All notices',
        icon: Icons.notifications_none_rounded,
        tint: AppColors.sage,
        ink: AppColors.sageInk,
        onTap: (c) => closeThen(c, () => Navigator.pushNamed(context, '/announcements')),
      ),
      if (role == UserRole.admin || role == UserRole.superadmin)
        _QuickAction(
          label: 'Users',
          hint: 'Manage the directory',
          icon: Icons.people_outline_rounded,
          tint: AppColors.sand,
          ink: AppColors.ink,
          onTap: (c) => closeThen(c, () => Navigator.pushNamed(context, '/admin')),
        ),
    ];
  }
}

class _ActionTile extends StatelessWidget {
  final _QuickAction action;

  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: action.tint,
      borderRadius: BorderRadius.circular(AppSpacing.rTile),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        onTap: () => action.onTap(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                child: Icon(action.icon, size: 19, color: action.ink),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.cardTitle),
                  const SizedBox(height: 2),
                  Text(
                    action.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: AppColors.ink.withValues(alpha: 0.65)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
