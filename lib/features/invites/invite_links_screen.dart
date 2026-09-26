import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/status_chip.dart';

class InviteLinksScreen extends ConsumerStatefulWidget {
  const InviteLinksScreen({super.key});

  @override
  ConsumerState<InviteLinksScreen> createState() => _InviteLinksScreenState();
}

class _InviteLinksScreenState extends ConsumerState<InviteLinksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await ref.read(appStateProvider.notifier).fetchInviteLinks();
    if (mounted) setState(() => _isLoading = false);
  }

  void _showCreateInviteDialog() {
    final labelController = TextEditingController();
    bool isCreating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Generate New Invite Link',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Link Label / Description',
                  hintText: 'e.g. Summer 2026 Batch A Onboarding',
                  controller: labelController,
                ),
                const SizedBox(height: 20),
                CustomButton(
                  text: 'Generate Link',
                  isLoading: isCreating,
                  onPressed: () async {
                    if (labelController.text.trim().isEmpty) return;
                    setModalState(() => isCreating = true);
                    final nav = Navigator.of(ctx);
                    try {
                      await ApiClient().post('/api/admin/invite-link', body: {
                        'label': labelController.text.trim(),
                      });
                      nav.pop();
                      if (mounted) {
                        _loadData();
                      }
                    } catch (_) {
                      setModalState(() => isCreating = false);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _reviewSignupRequest(String id, String decision) async {
    try {
      await ApiClient().post('/api/admin/intern-signup-requests/$id/review', body: {
        'decision': decision,
      });
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request $decision successfully.'),
            backgroundColor: decision == 'approved' ? AppColors.success : AppColors.danger,
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final inviteLinks = state.inviteLinks;
    final signups = state.signupRequests;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(
        context,
        title: 'Invite & Signups',
        actions: [
          HeaderAction(icon: Icons.add_link_rounded, tooltip: 'New invite link', onTap: _showCreateInviteDialog),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.rPill),
            ),
            child: TabBar(
              controller: _tabController,
              tabs: [
                Tab(height: 36, text: 'Invite Links (${inviteLinks.length})'),
                Tab(height: 36, text: 'Signups (${signups.length})'),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Invite Links Tab
                RefreshIndicator(
                  onRefresh: _loadData,
                  child: inviteLinks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.link_off_rounded, size: 48, color: AppColors.textTertiary),
                              const SizedBox(height: 12),
                              const Text('No invite links active', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Tap + to create a shareable invite link.', style: TextStyle(color: AppColors.textSecondary)),
                            ],
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(18),
                          children: [
                            // Hero Share Card (Screen 8 & 17)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(AppSpacing.r24),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Share Invite Link',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      const Icon(Icons.share_rounded, color: AppColors.ink, size: 20),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Invite new interns to join your team directly.',
                                    style: TextStyle(color: AppColors.ink.withValues(alpha: 0.70), fontSize: 12),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            inviteLinks.isNotEmpty ? 'https://internhub.app/join/${inviteLinks.first.token}' : 'https://internhub.app/join/...',
                                            style: const TextStyle(color: AppColors.ink, fontSize: 12, overflow: TextOverflow.ellipsis),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: () {
                                            if (inviteLinks.isNotEmpty) {
                                              Clipboard.setData(ClipboardData(text: 'https://internhub.app/join/${inviteLinks.first.token}'));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Invite URL copied to clipboard!')),
                                              );
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppColors.ink,
                                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                            ),
                                            child: const Text(
                                              'Copy',
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            Text(
                              'Generated Links',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 12),

                            ...inviteLinks.map((link) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(AppSpacing.r20),
                                  boxShadow: AppShadows.soft,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            link.label,
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        StatusChip(
                                          label: link.isActive ? 'ACTIVE' : 'INACTIVE',
                                          statusType: link.isActive ? StatusType.success : StatusType.neutral,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceMuted,
                                        borderRadius: BorderRadius.circular(AppSpacing.r12),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              link.token,
                                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.primaryInk),
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: link.token));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Invite token copied to clipboard!')),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Used: ${link.usageCount} times',
                                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                        Text(
                                          'Created: ${link.createdAt.toIso8601String().substring(0, 10)}',
                                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                ),

                // Signup Requests Tab
                RefreshIndicator(
                  onRefresh: _loadData,
                  child: signups.isEmpty
                      ? const Center(
                          child: Text('No pending signup requests'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: signups.length,
                          itemBuilder: (context, i) {
                            final req = signups[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.soft,
      ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(req.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      StatusChip(label: req.status.toUpperCase(), statusType: StatusType.warning),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(req.email, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                                  if (req.department != null) Text('Dept: ${req.department}', style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    runSpacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: () => _reviewSignupRequest(req.id, 'rejected'),
                                        child: const Text('Reject', style: TextStyle(color: AppColors.danger)),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: () => _reviewSignupRequest(req.id, 'approved'),
                                        child: const Text('Approve'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
