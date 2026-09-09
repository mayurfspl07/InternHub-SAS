import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/profile_overview_model.dart';
import '../../shared/models/user_model.dart';
import 'app_avatar.dart';
import 'status_chip.dart';

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
    final overview = await ref.read(appStateProvider.notifier).fetchUserOverview(widget.userId);
    if (mounted) {
      setState(() {
        _overview = overview;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = _overview?.user ?? widget.fallbackUser;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                AppAvatar(
                  url: user?.avatarUrl,
                  size: 56,
                  borderColor: AppColors.primary,
                  borderWidth: 2,
                  fallbackText: user?.name ?? 'User',
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'User Profile',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          StatusChip(
                            label: user?.role.toApiValue().toUpperCase() ?? 'INTERN',
                            statusType: StatusType.info,
                          ),
                          const SizedBox(width: 8),
                          if (user?.department != null && user!.department!.isNotEmpty)
                            Text(
                              user.department!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Tabs
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: isDark ? Colors.white60 : Colors.grey.shade600,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Projects'),
              Tab(text: 'Tasks'),
              Tab(text: 'Attendance'),
            ],
          ),

          // Tab content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Overview Tab
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          _buildDetailRow(context, 'Role Title', user?.roleTitle ?? 'N/A'),
                          _buildDetailRow(context, 'Department', user?.department ?? 'N/A'),
                          _buildDetailRow(context, 'Phone', user?.phone ?? 'N/A'),
                          _buildDetailRow(context, 'Joining Date', user?.joiningDate ?? 'N/A'),
                          _buildDetailRow(context, 'Mentor', user?.mentorName ?? 'None assigned'),
                          if (user?.skills.isNotEmpty ?? false)
                            _buildDetailRow(context, 'Skills', user!.skills.join(', ')),
                          if (user?.bio != null && user!.bio!.isNotEmpty)
                            _buildDetailRow(context, 'Bio', user.bio!),
                          const SizedBox(height: 16),
                          if (_overview?.stats.isNotEmpty ?? false) ...[
                            Text(
                              'Key Performance Indicators',
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: _overview!.stats.entries.map((e) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.surfaceDark : const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        e.key.replaceAll('_', ' ').toUpperCase(),
                                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        e.value.toString(),
                                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),

                      // Projects Tab
                      _overview?.projects.isEmpty ?? true
                          ? const Center(child: Text('No active projects'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _overview!.projects.length,
                              itemBuilder: (ctx, i) {
                                final p = _overview!.projects[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text('${(p.progress * 100).toInt()}% complete • ${p.totalTasks} tasks'),
                                    trailing: StatusChip(label: p.status.toUpperCase(), statusType: StatusType.success),
                                  ),
                                );
                              },
                            ),

                      // Tasks Tab
                      _overview?.tasks.isEmpty ?? true
                          ? const Center(child: Text('No assigned tasks'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _overview!.tasks.length,
                              itemBuilder: (ctx, i) {
                                final t = _overview!.tasks[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(t.projectName),
                                    trailing: StatusChip(label: t.status.label, statusType: StatusType.info),
                                  ),
                                );
                              },
                            ),

                      // Attendance Tab
                      _overview?.attendance.isEmpty ?? true
                          ? const Center(child: Text('No attendance history found'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _overview!.attendance.length,
                              itemBuilder: (ctx, i) {
                                final a = _overview!.attendance[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    title: Text(a.date.length >= 10 ? a.date.substring(0, 10) : a.date),
                                    subtitle: Text(a.locationAddress),
                                    trailing: StatusChip(label: a.status.toUpperCase(), statusType: StatusType.success),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white54 : AppColors.textSecondaryLight,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
