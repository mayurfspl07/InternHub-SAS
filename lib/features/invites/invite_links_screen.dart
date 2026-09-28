import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../core/constants/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../directory_cohorts/widgets/intern_terms_section.dart';

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
  final Set<String> _reviewing = {};

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
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
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
    bool mentorsRequested = false;
    bool mentorsLoading = isAdmin;
    String? mentorsError;
    String? mentorId;
    String? error;
    bool isCreating = false;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          // Load mentors once, after the sheet is already on screen.
          if (isAdmin && !mentorsRequested) {
            mentorsRequested = true;
            ApiClient().get('/api/users/mentors').then((res) {
              if (!ctx.mounted) return;
              setModalState(() {
                mentors = res is Map && res['mentors'] is List
                    ? (res['mentors'] as List).whereType<Map<String, dynamic>>().toList()
                    : const [];
                mentorsLoading = false;
              });
            }).catchError((Object e) {
              if (!ctx.mounted) return;
              setModalState(() {
                mentorsLoading = false;
                mentorsError = "Couldn't load mentors. You can still create the link.";
              });
            });
          }
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New invite link', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                CustomTextField(
                  label: 'Label',
                  hintText: 'e.g. Pune campus drive 2026',
                  helperText: 'Only your team sees this',
                  controller: labelController,
                  textCapitalization: TextCapitalization.sentences,
                ),
                if (isAdmin) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: mentorId,
                    decoration: InputDecoration(
                      labelText: 'Mentor for new interns (optional)',
                      hintText: mentorsLoading ? 'Loading mentors…' : null,
                      helperText: mentorsError,
                    ),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('No mentor')),
                      ...mentors.map((m) => DropdownMenuItem<String>(
                            value: m['id']?.toString(),
                            child: Text(m['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: mentorsLoading ? null : (v) => setModalState(() => mentorId = v),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
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
                      nav.pop(true);
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
    if (created == true && mounted) _toast('Link created. Copy or share it below.');
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
      failure: "Couldn't regenerate the link",
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
      failure: "Couldn't turn off the links",
    );
  }

  Future<void> _delete(InviteLinkModel link) async {
    if (!await _confirm('Delete "${link.label}"?', 'People can no longer sign up with this link.', 'Delete')) {
      return;
    }
    await _run(
      () => ref.read(appStateProvider.notifier).deleteInviteLink(link.id),
      success: 'Invite link deleted',
      failure: "Couldn't delete the link",
    );
  }

  /// Asks the reviewer for the intern's duration (its leaves become their leave allowance).
  Future<int?> _pickDuration(SignupRequestModel req) {
    int? months;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Approve ${req.name}?'),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Choose their internship duration. It sets how many leave days they get.', style: AppTypography.caption),
              const SizedBox(height: 16),
              InternDurationField(value: months, onChanged: (v) => setDlg(() => months = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: months == null ? null : () => Navigator.pop(ctx, months),
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _review(SignupRequestModel req, {required bool approve}) async {
    if (_reviewing.contains(req.id)) return;
    if (!approve &&
        !await _confirm('Reject ${req.name}?', "They won't get an account. They can ask for a new invite later.", 'Reject')) {
      return;
    }
    int? months;
    if (approve) {
      months = await _pickDuration(req);
      if (months == null || !mounted) return;
    }
    setState(() => _reviewing.add(req.id));
    await _run(
      () => ref.read(appStateProvider.notifier).reviewSignupRequest(req.id, approve: approve, durationMonths: months),
      success: approve ? '${req.name} approved' : '${req.name} rejected',
      failure: approve ? "Couldn't approve" : "Couldn't reject",
    );
    if (mounted) setState(() => _reviewing.remove(req.id));
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
        title: user.isAdmin ? 'Invite links & sign-ups' : 'Invite links',
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
        Text(title, textAlign: TextAlign.center, style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(subtitle, textAlign: TextAlign.center, style: AppTypography.caption),
        ),
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.r20),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(link.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(
                    label: link.isActive ? 'Active' : 'Off',
                    statusType: link.isActive ? StatusType.success : StatusType.neutral,
                  ),
                ],
              ),
              if (link.mentorName != null) ...[
                const SizedBox(height: 4),
                Text('Mentor: ${link.mentorName}', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
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
                        style: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
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
                      'created ${formatDate(link.createdAt)}'
                      '${link.createdByName != null ? ' by ${link.createdByName}' : ''}',
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                    ),
                  ),
                  if (canDelete)
                    IconButton(
                      tooltip: 'Delete link',
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.dangerInk),
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
        final busy = _reviewing.contains(req.id);
        final details = [
          if (req.inviteLabel != null) 'Link: ${req.inviteLabel}',
          if (req.mentorName != null) 'Mentor: ${req.mentorName}',
          if (req.department != null) 'Department: ${req.department}',
          if (req.phone != null) 'Phone: ${req.phone}',
          'Requested ${formatDate(req.createdAt)}',
        ];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(req.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700))),
                  const SizedBox(width: 8),
                  const StatusChip(label: 'Pending', statusType: StatusType.warning),
                ],
              ),
              const SizedBox(height: 4),
              Text(req.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              ...details.map((d) => Text(d, style: AppTypography.caption.copyWith(color: AppColors.textSecondary))),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: busy ? null : () => _review(req, approve: false),
                    style: TextButton.styleFrom(foregroundColor: AppColors.dangerInk, minimumSize: const Size(0, 44)),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: busy ? null : () => _review(req, approve: true),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Approve'),
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
