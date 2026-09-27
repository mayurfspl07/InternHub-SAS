import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/invite_model.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/status_chip.dart';

/// Invite links (create, share, regenerate, deactivate, delete) and the sign-up requests
/// they produce (approve / reject). Admins manage every link of the organization;
/// mentors manage the links they created.
class InviteLinksScreen extends ConsumerStatefulWidget {
  const InviteLinksScreen({super.key});

  @override
  ConsumerState<InviteLinksScreen> createState() => _InviteLinksScreenState();
}

class _InviteLinksScreenState extends ConsumerState<InviteLinksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() => ref.read(appStateProvider.notifier).fetchInviteLinks();

  void _toast(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _run(Future<void> Function() action, {required String success, required String failure}) async {
    try {
      await action();
      if (mounted) _toast(success);
    } catch (e) {
      if (mounted) showApiError(context, e, prefix: failure);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action, style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _showCreateInviteDialog() async {
    final isAdmin = ref.read(appStateProvider).currentUser.isAdmin;
    final labelController = TextEditingController();
    List<Map<String, dynamic>> mentors = const [];
    String? mentorId;
    String? error;
    bool isCreating = false;

    if (isAdmin) {
      try {
        final res = await ApiClient().get('/api/users/mentors');
        mentors = res is Map && res['mentors'] is List
            ? (res['mentors'] as List).whereType<Map<String, dynamic>>().toList()
            : const [];
      } catch (e) {
        if (mounted) showApiError(context, e, prefix: 'Could not load mentors');
      }
    }
    if (!mounted) return;

    await showModalBottomSheet(
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('New invite link', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Label',
                  hintText: 'e.g. Pune campus drive 2026',
                  controller: labelController,
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: mentorId,
                    decoration: const InputDecoration(labelText: 'Mentor for new interns (optional)'),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('No mentor')),
                      ...mentors.map((m) => DropdownMenuItem<String>(
                            value: m['id']?.toString(),
                            child: Text(m['name']?.toString() ?? ''),
                          )),
                    ],
                    onChanged: (v) => setModalState(() => mentorId = v),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
                const SizedBox(height: 20),
                CustomButton(
                  text: 'Create link',
                  isLoading: isCreating,
                  onPressed: () async {
                    if (labelController.text.trim().isEmpty) {
                      setModalState(() => error = 'Give the link a label.');
                      return;
                    }
                    setModalState(() {
                      isCreating = true;
                      error = null;
                    });
                    final nav = Navigator.of(ctx);
                    try {
                      await ref
                          .read(appStateProvider.notifier)
                          .createInviteLink(label: labelController.text.trim(), mentorId: mentorId);
                      nav.pop();
                    } catch (e) {
                      setModalState(() {
                        isCreating = false;
                        error = apiErrorMessage(e);
                      });
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

  Future<void> _regenerate() async {
    if (!await _confirm(
      'Regenerate invite link?',
      'All active links of your organization stop working and a new one is created.',
      'Regenerate',
    )) {
      return;
    }
    await _run(
      () => ref.read(appStateProvider.notifier).regenerateInviteLink(),
      success: 'New invite link created',
      failure: 'Could not regenerate the link',
    );
  }

  Future<void> _deactivateAll() async {
    if (!await _confirm(
      'Turn off invite links?',
      'Every active invite link of your organization will stop accepting sign-ups.',
      'Turn off',
    )) {
      return;
    }
    await _run(
      () => ref.read(appStateProvider.notifier).deactivateInviteLinks(),
      success: 'Invite links turned off',
      failure: 'Could not turn off the links',
    );
  }

  Future<void> _delete(InviteLinkModel link) async {
    if (!await _confirm('Delete "${link.label}"?', 'People can no longer sign up with this link.', 'Delete')) {
      return;
    }
    await _run(
      () => ref.read(appStateProvider.notifier).deleteInviteLink(link.id),
      success: 'Invite link deleted',
      failure: 'Could not delete the link',
    );
  }

  Future<void> _review(SignupRequestModel req, {required bool approve}) async {
    await _run(
      () => ref.read(appStateProvider.notifier).reviewSignupRequest(req.id, approve: approve),
      success: approve ? '${req.name} approved' : '${req.name} rejected',
      failure: approve ? 'Could not approve' : 'Could not reject',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final links = state.inviteLinks;
    final signups = state.signupRequests;
    final loading = state.invitesLoading && links.isEmpty && signups.isEmpty;
    final error = state.invitesError;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: pageAppBar(
        context,
        title: 'Invites & sign-ups',
        actions: [
          HeaderAction(icon: Icons.add_link_rounded, tooltip: 'New invite link', onTap: _showCreateInviteDialog),
          if (user.isAdmin)
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.ink),
              onSelected: (v) => v == 'regenerate' ? _regenerate() : _deactivateAll(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'regenerate', child: Text('Regenerate link')),
                PopupMenuItem(value: 'deactivate', child: Text('Turn off all links')),
              ],
            ),
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
                Tab(height: 36, text: 'Links (${links.length})'),
                Tab(height: 36, text: 'Sign-ups (${signups.length})'),
              ],
            ),
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null && links.isEmpty && signups.isEmpty
              ? LoadErrorView(title: 'Couldn\'t load invites', message: error, onRetry: _loadData)
              : TabBarView(
                  controller: _tabController,
                  children: [
                    RefreshIndicator(onRefresh: _loadData, child: _buildLinks(links, user.id, user.isAdmin)),
                    RefreshIndicator(onRefresh: _loadData, child: _buildSignups(signups)),
                  ],
                ),
    );
  }

  Widget _empty(IconData icon, String title, String subtitle) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Icon(icon, size: 48, color: AppColors.textTertiary),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildLinks(List<InviteLinkModel> links, String userId, bool isAdmin) {
    if (links.isEmpty) {
      return _empty(Icons.link_off_rounded, 'No active invite links', 'Tap + to create a link you can share.');
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: links.map((link) {
        final canDelete = isAdmin || link.createdById == userId;
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
                children: [
                  Expanded(
                    child: Text(link.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  StatusChip(
                    label: link.isActive ? 'Active' : 'Off',
                    statusType: link.isActive ? StatusType.success : StatusType.neutral,
                  ),
                ],
              ),
              if (link.mentorName != null) ...[
                const SizedBox(height: 4),
                Text('Mentor: ${link.mentorName}', style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppSpacing.r12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        link.url,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy link',
                      icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.primaryInk),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: link.url));
                        _toast('Invite link copied');
                      },
                    ),
                    IconButton(
                      tooltip: 'Share link',
                      icon: const Icon(Icons.share_rounded, size: 18, color: AppColors.primaryInk),
                      onPressed: () => Share.share('Join ${link.label} on InternHub: ${link.url}'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Used ${link.usageCount} ${link.usageCount == 1 ? 'time' : 'times'} · '
                      'created ${DateFormat('d MMM yyyy').format(link.createdAt)}'
                      '${link.createdByName != null ? ' by ${link.createdByName}' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      tooltip: 'Delete link',
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
                      onPressed: () => _delete(link),
                    ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSignups(List<SignupRequestModel> signups) {
    if (signups.isEmpty) {
      return _empty(Icons.how_to_reg_outlined, 'No sign-ups waiting', 'People who join with an invite link appear here.');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: signups.length,
      itemBuilder: (context, i) {
        final req = signups[i];
        final details = [
          if (req.inviteLabel != null) 'Link: ${req.inviteLabel}',
          if (req.mentorName != null) 'Mentor: ${req.mentorName}',
          if (req.department != null) 'Department: ${req.department}',
          if (req.phone != null) 'Phone: ${req.phone}',
          'Requested ${DateFormat('d MMM yyyy').format(req.createdAt)}',
        ];
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
                children: [
                  Expanded(child: Text(req.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  const StatusChip(label: 'Pending', statusType: StatusType.warning),
                ],
              ),
              const SizedBox(height: 4),
              Text(req.email, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              ...details.map((d) => Text(d, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _review(req, approve: false),
                    child: const Text('Reject', style: TextStyle(color: AppColors.danger)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _review(req, approve: true),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
