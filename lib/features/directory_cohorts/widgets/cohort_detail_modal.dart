import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../shared/models/cohort_model.dart';
import '../../../shared/models/user_model.dart';
import '../cohorts_repository.dart';
import '../../../core/constants/app_colors.dart';

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

  bool get canManage => canManageCohorts(widget.currentUser);

  @override
  void initState() {
    super.initState();
    _cohort = widget.initialCohort;
    _fetchDetail();
  }

  @override
  void dispose() {
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
          _errorMessage = e.toString();
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

  Future<void> _searchInterns(String query) async {
    setState(() => _isLoadingInterns = true);
    try {
      final options = await CohortsRepository().getInternOptions(search: query);
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
      if (mounted) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Member added to cohort'),
            backgroundColor: AppColors.success,
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add member: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _confirmRemoveMember(CohortMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Remove Member?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(
            'Are you sure you want to remove "${member.displayName}" from "${_cohort.name}"?',
            style: const TextStyle(fontSize: 14),
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
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${member.displayName} removed from cohort'),
              backgroundColor: AppColors.success,
            ),
          );
          await _fetchDetail();
          widget.onDataChanged();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to remove member: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Upcoming':
        bg = AppColors.infoSoft;
        fg = AppColors.info;
        break;
      case 'Completed':
        bg = AppColors.surfaceMuted;
        fg = AppColors.textSecondary;
        break;
      case 'Active Batch':
      case 'Active':
      default:
        bg = AppColors.warningSoft;
        fg = AppColors.warning;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Colors.white;
    final cardBg = AppColors.surfaceMuted;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final members = _cohort.members ?? [];
    final enrolledCount = members.isNotEmpty ? members.length : (_cohort.memberCount ?? 0);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _cohort.name,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTextColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildStatusBadge(_cohort.statusLabel),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_outlined, size: 13, color: secondaryTextColor),
                              const SizedBox(width: 5),
                              Text(
                                _cohort.dateRangeFormatted,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: secondaryTextColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.people_outline_rounded, size: 14, color: secondaryTextColor),
                              const SizedBox(width: 5),
                              Text(
                                '$enrolledCount Enrolled',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
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
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),

              // Members Header with Action Button ("Add Member")
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Members ($enrolledCount)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                      ),
                    ),
                    if (canManage)
                      TextButton.icon(
                        onPressed: _showAddPicker ? () => setState(() => _showAddPicker = false) : _openAddPicker,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.butterInk,
                          backgroundColor: AppColors.primarySoft,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: Icon(
                          _showAddPicker ? Icons.close_rounded : Icons.person_add_alt_1_rounded,
                          size: 16,
                          color: AppColors.butterInk,
                        ),
                        label: Text(
                          _showAddPicker ? 'Close Picker' : 'Add Member',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                          'Select Intern to Add',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _internSearchController,
                          onChanged: (val) => _searchInterns(val),
                          style: TextStyle(fontSize: 13, color: primaryTextColor),
                          decoration: InputDecoration(
                            hintText: 'Search interns by name or email...',
                            hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                            isDense: true,
                            prefixIcon: Icon(Icons.search_rounded, size: 18, color: secondaryTextColor),
                            filled: true,
                            fillColor: Colors.white,
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
                                'No available interns found',
                                style: TextStyle(fontSize: 13, color: secondaryTextColor),
                              ),
                            ),
                          )
                        else
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
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
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                                  ),
                                  subtitle: opt.displaySubtitle.isNotEmpty
                                      ? Text(opt.displaySubtitle, style: TextStyle(fontSize: 11, color: secondaryTextColor))
                                      : null,
                                  trailing: ElevatedButton(
                                    onPressed: () => _addMember(opt.userId),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: AppColors.ink,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      elevation: 0,
                                    ),
                                    child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
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
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 36),
                                const SizedBox(height: 8),
                                Text('Failed to load members', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(_errorMessage!, style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: _fetchDetail,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
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
                                        'No members enrolled yet',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: primaryTextColor,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        canManage
                                            ? 'Click "Add Member" to assign interns to this cohort.'
                                            : 'No interns have been added to this cohort yet.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: secondaryTextColor,
                                        ),
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

                                  String joinedStr = '';
                                  if (member.joinedAt != null && member.joinedAt!.isNotEmpty) {
                                    final dt = DateTime.tryParse(member.joinedAt!);
                                    if (dt != null) {
                                      joinedStr = 'Joined ${DateFormat('MMM d, yyyy').format(dt.toLocal())}';
                                    }
                                  }

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
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: AppColors.warningSoft,
                                          child: Text(
                                            member.initials,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: AppColors.warningInk,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        // Name, Email, Dept
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                member.displayName,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: primaryTextColor,
                                                ),
                                              ),
                                              if (member.displayEmail.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  member.displayEmail,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: secondaryTextColor,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 3),
                                              Row(
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
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.w600,
                                                          color: primaryTextColor,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  if (joinedStr.isNotEmpty)
                                                    Text(
                                                      joinedStr,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: secondaryTextColor,
                                                      ),
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
                                            color: AppColors.danger.withValues(alpha: 0.8),
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
    );
  }
}
