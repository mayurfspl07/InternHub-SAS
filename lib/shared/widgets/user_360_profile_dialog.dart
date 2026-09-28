import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/profile_overview_model.dart';
import '../../shared/models/user_model.dart';
import 'load_error_view.dart';
import 'status_chip.dart';
import 'reference_components.dart';
import '../../core/constants/app_typography.dart';

class User360ProfileDialog extends ConsumerStatefulWidget {
  final String userId;
  final UserModel? fallbackUser;

  const User360ProfileDialog({
    super.key,
    required this.userId,
    this.fallbackUser,
  });

  static Future<void> show(
    BuildContext context, {
    String? userId,
    UserModel? fallbackUser,
  }) {
    final uid = userId ?? fallbackUser?.id ?? '';
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => User360ProfileDialog(userId: uid, fallbackUser: fallbackUser),
    );
  }

  @override
  ConsumerState<User360ProfileDialog> createState() => _User360ProfileDialogState();
}

class _User360ProfileDialogState extends ConsumerState<User360ProfileDialog> with SingleTickerProviderStateMixin {
  UserProfileOverview? _overview;
  bool _isLoading = true;
  String? _error;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadOverview();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final overview = await ref.read(appStateProvider.notifier).fetchUserOverview(widget.userId);
      if (mounted) {
        setState(() {
          _overview = overview;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(e);
          _isLoading = false;
        });
      }
    }
  }

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
        ),
      );

  Widget _row({required String title, String? subtitle, Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.rTile),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.caption),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  Widget _overviewTab(UserModel? user) {
    final stats = _overview?.stats ?? const {};
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        CustomerHeroHeader(
          name: user?.name ?? 'Member',
          subtitle: [
            if (user?.roleTitle != null && user!.roleTitle.isNotEmpty) user.roleTitle,
            if (user?.department != null && user!.department!.isNotEmpty) user.department!,
          ].join(' · '),
          avatarUrl: user?.avatarUrl,
        ),
        const SizedBox(height: 24),
        Text('Details', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        _buildDetailRow('Email', user?.email ?? '—'),
        _buildDetailRow('Department', user?.department ?? '—'),
        _buildDetailRow('Phone', user?.phone ?? '—'),
        _buildDetailRow('Joined', formatDate(user?.joiningDate, fallback: '—')),
        if (user?.role == UserRole.intern) _buildDetailRow('Mentor', user?.mentorName ?? 'Not assigned'),
        if (user?.skills.isNotEmpty ?? false) _buildDetailRow('Skills', user!.skills.join(', ')),
        if (user?.bio != null && user!.bio!.isNotEmpty) _buildDetailRow('About', user.bio!),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('At a glance', style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final e in stats.entries)
                if (e.value is num || e.value is String)
                  Container(
                    constraints: const BoxConstraints(minWidth: 96),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.value.toString(), style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(humanize(e.key).replaceAll(' 30d', ' (30 days)'), style: AppTypography.label),
                      ],
                    ),
                  ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _overview?.user ?? widget.fallbackUser;
    final ov = _overview;

    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      content = LoadErrorView(title: "Couldn't load this profile", message: _error!, onRetry: _loadOverview);
    } else {
      content = TabBarView(
        controller: _tabController,
        children: [
          _overviewTab(user),
          (ov?.projects.isEmpty ?? true)
              ? _empty('Not on any projects')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final p in ov!.projects)
                      _row(
                        title: p.name,
                        subtitle: [
                          '${p.progress.round()}% done',
                          if (p.internCount != null) plural(p.internCount!, 'intern'),
                          if (p.endDate != null) 'Due ${formatDate(p.endDate)}',
                        ].join(' · '),
                        trailing: StatusChip.fromString(p.status),
                      ),
                  ],
                ),
          (ov?.tasks.isEmpty ?? true)
              ? _empty('No tasks assigned')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final t in ov!.tasks)
                      _row(
                        title: t.title,
                        subtitle: [
                          t.projectName ?? 'Project #${t.projectId}',
                          if (t.dueDate != null) 'Due ${formatDate(t.dueDate)}',
                        ].join(' · '),
                        trailing: StatusChip.fromString(t.status),
                      ),
                  ],
                ),
          (ov?.attendance.isEmpty ?? true)
              ? _empty('No attendance recorded yet')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final a in ov!.attendance)
                      _row(
                        title: formatDate(a.date),
                        subtitle: a.checkIn == null
                            ? 'No check-in'
                            : [
                                'In ${formatTime(a.checkIn, fallback: a.checkIn!)}',
                                if (a.checkOut != null) 'Out ${formatTime(a.checkOut, fallback: a.checkOut!)}',
                                if (a.hours != null && a.hours! > 0) formatHours(a.hours),
                              ].join(' · '),
                        trailing: StatusChip.fromString(a.status),
                      ),
                  ],
                ),
        ],
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    user?.name ?? 'Profile',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.section.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppSpacing.rPill),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(height: 40, text: 'Overview'),
                Tab(height: 40, text: 'Projects${ov == null ? '' : ' (${ov.projects.length})'}'),
                Tab(height: 40, text: 'Tasks${ov == null ? '' : ' (${ov.tasks.length})'}'),
                const Tab(height: 40, text: 'Attendance'),
              ],
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: AppTypography.caption)),
          Expanded(
            child: Text(value, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: AppColors.ink)),
          ),
        ],
      ),
    );
  }
}
