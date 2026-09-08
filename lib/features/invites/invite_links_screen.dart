import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
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
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Generate New Invite Link',
                  style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inviteLinks = state.inviteLinks;
    final signups = state.signupRequests;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Invite & Signups',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link_rounded, color: AppColors.primary),
            onPressed: _showCreateInviteDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark ? Colors.white60 : Colors.grey.shade600,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'Invite Links (${inviteLinks.length})'),
            Tab(text: 'Signup Requests (${signups.length})'),
          ],
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
                              const Icon(Icons.link_off_rounded, size: 48, color: Colors.grey),
                              const SizedBox(height: 12),
                              const Text('No invite links active', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('Tap + to create a shareable invite link.', style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: inviteLinks.length,
                          itemBuilder: (context, i) {
                            final link = inviteLinks[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
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
                                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      StatusChip(
                                        label: link.isActive ? 'ACTIVE' : 'INACTIVE',
                                        statusType: link.isActive ? StatusType.success : StatusType.neutral,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(8),
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
                                          icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.primary),
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
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                      Text(
                                        'Created: ${link.createdAt.toIso8601String().substring(0, 10)}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
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
                                color: isDark ? AppColors.surfaceDark : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(req.name, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                                      StatusChip(label: req.status.toUpperCase(), statusType: StatusType.warning),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(req.email, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                  if (req.department != null) Text('Dept: ${req.department}', style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
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
