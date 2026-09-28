import 'dart:async';
import 'package:flutter/material.dart';
import '../../../shared/models/cohort_model.dart';
import '../../../shared/models/user_model.dart';
import '../cohorts_repository.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_typography.dart';
import '../../../shared/widgets/load_error_view.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/status_chip.dart';
import '../../../shared/widgets/app_avatar.dart';

class CohortDetailModal extends StatefulWidget {
  final Cohort initialCohort;
  final UserModel currentUser;
  final VoidCallback onDataChanged;

  const CohortDetailModal({
    super.key,
    required this.initialCohort,
    required this.currentUser,
    required this.onDataChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required Cohort cohort,
    required UserModel currentUser,
    required VoidCallback onDataChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CohortDetailModal(
        initialCohort: cohort,
        currentUser: currentUser,
        onDataChanged: onDataChanged,
      ),
    );
  }

  @override
  State<CohortDetailModal> createState() => _CohortDetailModalState();
}

class _CohortDetailModalState extends State<CohortDetailModal> {
  late Cohort _cohort;
  bool _isLoading = true;
  bool _isAddingMember = false;
  String? _errorMessage;

  // Add member picker state
  bool _showAddPicker = false;
  bool _isLoadingInterns = false;
  final TextEditingController _internSearchController = TextEditingController();
  List<CohortInternOption> _internOptions = [];
  Timer? _searchDebounce;
  // Latest search sent; slower responses for older queries are dropped.
  String _activeQuery = '';

  bool get canManage => canManageCohorts(widget.currentUser);

  @override
  void initState() {
    super.initState();
    _cohort = widget.initialCohort;
    _fetchDetail();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _internSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final updated = await CohortsRepository().getCohort(_cohort.id);
      if (mounted) {
        setState(() {
          _cohort = updated;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = apiErrorMessage(e);
        });
      }
    }
  }

  Future<void> _openAddPicker() async {
    setState(() {
      _showAddPicker = true;
      _isLoadingInterns = true;
      _internSearchController.clear();
    });
    await _searchInterns('');
  }

  void _onInternSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () => _searchInterns(query));
  }

  Future<void> _searchInterns(String query) async {
    _activeQuery = query;
    setState(() => _isLoadingInterns = true);
    try {
      final options = await CohortsRepository().getInternOptions(search: query);
      if (query != _activeQuery) return;
      // Filter OUT user_ids already enrolled in cohort
      final existingIds = (_cohort.members ?? []).map((m) => m.userId).toSet();
      final filtered = options.where((o) => !existingIds.contains(o.userId)).toList();

      if (mounted) {
        setState(() {
          _internOptions = filtered;
          _isLoadingInterns = false;
        });
      }
    } catch (_) {
      if (mounted && query == _activeQuery) {
        setState(() {
          _internOptions = [];
          _isLoadingInterns = false;
        });
      }
    }
  }

  Future<void> _addMember(int userId) async {
    setState(() => _isAddingMember = true);
    try {
      await CohortsRepository().addMember(_cohort.id, userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to the cohort')));
        setState(() {
          _showAddPicker = false;
          _isAddingMember = false;
        });
        await _fetchDetail();
        widget.onDataChanged();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAddingMember = false);
        showApiError(context, e, prefix: "Couldn't add them");
      }
    }
  }

  Future<void> _confirmRemoveMember(CohortMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Remove ${member.displayName}?', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
          content: Text(
            'They leave "${_cohort.name}". Their account and work are not affected.',
            style: AppTypography.body.copyWith(color: AppColors.ink),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: AppColors.surface,
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await CohortsRepository().removeMember(_cohort.id, member.userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${member.displayName} removed')));
          await _fetchDetail();
          widget.onDataChanged();
        }
      } catch (e) {
        if (mounted) {
          showApiError(context, e, prefix: "Couldn't remove ${member.displayName}");
        }
      }
    }
  }

  Widget _buildStatusBadge(String status) {
    final type = switch (status) {
      'Active' => StatusType.success,
      'Upcoming' => StatusType.info,
      _ => StatusType.neutral,
    };
    return StatusChip(label: status, statusType: type);
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = AppColors.surface;
    final cardBg = AppColors.surfaceMuted;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final members = _cohort.members ?? [];
    final enrolledCount = members.isNotEmpty ? members.length : (_cohort.memberCount ?? 0);

    // Lift the sheet above the keyboard while searching for interns.
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // Header bar with Cohort Info and Close
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.butter,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primary, width: 1.2),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        color: AppColors.butterInk,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _cohort.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                          ),
                          const SizedBox(height: 6),
                          // Wraps on narrow phones instead of overflowing.
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildStatusBadge(_cohort.statusLabel),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today_outlined, size: 13, color: secondaryTextColor),
                                  const SizedBox(width: 5),
                                  Text(_cohort.dateRangeFormatted, style: AppTypography.caption),
                                ],
                              ),
                              Text(plural(enrolledCount, 'intern'), style: AppTypography.caption),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                      color: secondaryTextColor,
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Description section (if present)
              if (_cohort.description != null && _cohort.description!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(
                      _cohort.description!.trim(),
                      style: AppTypography.caption.copyWith(color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ),

              // Members Header with Action Button ("Add Member")
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                      'Interns ($enrolledCount)',
                      style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                    ),
                    ),
                    if (canManage)
                      TextButton.icon(
                        onPressed: _showAddPicker ? () => setState(() => _showAddPicker = false) : _openAddPicker,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.butterInk,
                          backgroundColor: AppColors.primarySoft,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(0, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: Icon(
                          _showAddPicker ? Icons.close_rounded : Icons.person_add_alt_1_rounded,
                          size: 16,
                          color: AppColors.butterInk,
                        ),
                        label: Text(
                          _showAddPicker ? 'Done' : 'Add intern',
                          style: AppTypography.caption.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),

              // Add member picker container
              if (_showAddPicker)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary, width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add an intern',
                          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _internSearchController,
                          onChanged: _onInternSearchChanged,
                          textInputAction: TextInputAction.search,
                          style: AppTypography.caption.copyWith(color: primaryTextColor),
                          decoration: InputDecoration(
                            hintText: 'Search by name or email',
                            hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
                            isDense: true,
                            prefixIcon: Icon(Icons.search_rounded, size: 18, color: secondaryTextColor),
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: borderColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_isLoadingInterns || _isAddingMember)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        else if (_internOptions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: Text(
                                _internSearchController.text.isEmpty ? 'Every intern is already in this cohort' : 'No interns match that search',
                                style: AppTypography.caption.copyWith(color: secondaryTextColor),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 200),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _internOptions.length,
                              separatorBuilder: (_, _) => Divider(height: 1, color: borderColor),
                              itemBuilder: (context, idx) {
                                final opt = _internOptions[idx];
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  title: Text(
                                    opt.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600, color: primaryTextColor),
                                  ),
                                  subtitle: opt.displaySubtitle.isNotEmpty
                                      ? Text(opt.displaySubtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.label)
                                      : null,
                                  trailing: ElevatedButton(
                                    onPressed: () => _addMember(opt.userId),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: AppColors.onPrimary,
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      minimumSize: const Size(0, 40),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 0,
                                    ),
                                    child: const Text('Add'),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // Members List or Loading/Empty States
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _errorMessage != null
                        ? LoadErrorView(title: "Couldn't load this cohort", message: _errorMessage!, onRetry: _fetchDetail, compact: true)
                        : members.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.people_outline_rounded,
                                        size: 48,
                                        color: AppColors.textTertiary,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No interns yet',
                                        style: AppTypography.cardTitle.copyWith(color: primaryTextColor),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        canManage
                                            ? 'Tap "Add intern" to add people to this cohort.'
                                            : 'Interns appear here once they are added.',
                                        textAlign: TextAlign.center,
                                        style: AppTypography.caption.copyWith(color: secondaryTextColor),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                itemCount: members.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final member = members[index];

                                  final joined = formatDate(member.joinedAt);
                                  final joinedStr = joined.isEmpty ? '' : 'Added $joined';

                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      children: [
                                        // Initials Avatar
                                        AppAvatar(fallbackText: member.displayName, size: 40),
                                        const SizedBox(width: 14),
                                        // Name, Email, Dept
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                member.displayName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                                              ),
                                              if (member.displayEmail.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  member.displayEmail,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: AppTypography.caption.copyWith(color: secondaryTextColor),
                                                ),
                                              ],
                                              const SizedBox(height: 3),
                                              Wrap(
                                                spacing: 0,
                                                runSpacing: 4,
                                                crossAxisAlignment: WrapCrossAlignment.center,
                                                children: [
                                                  if (member.department != null && member.department!.isNotEmpty) ...[
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.border,
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        member.department!,
                                                        style: AppTypography.label.copyWith(color: primaryTextColor),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  if (joinedStr.isNotEmpty)
                                                    Text(
                                                      joinedStr,
                                                      style: AppTypography.label.copyWith(color: secondaryTextColor),
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Remove Action (if canManage)
                                        if (canManage)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 20),
                                            color: AppColors.dangerInk,
                                            tooltip: 'Remove from cohort',
                                            onPressed: () => _confirmRemoveMember(member),
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
      },
    ),
    );
  }
}
