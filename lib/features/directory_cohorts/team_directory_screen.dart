import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/reference_components.dart';
import 'member_profile_screen.dart';
import '../../core/constants/app_typography.dart';

class TeamDirectoryScreen extends ConsumerStatefulWidget {
  const TeamDirectoryScreen({super.key});

  @override
  ConsumerState<TeamDirectoryScreen> createState() => _TeamDirectoryScreenState();
}

class _TeamDirectoryScreenState extends ConsumerState<TeamDirectoryScreen> {
  static const _categories = ['All', 'Interns', 'Mentors', 'Admins'];
  static const _noDepartment = 'No department';
  static const _deptColors = [AppColors.infoInk, AppColors.peachInk, AppColors.primaryInk, AppColors.successInk, AppColors.lavenderInk];

  int _category = 0;
  String? _selectedDepartment;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // The directory needs everyone in the organization, not just the first page.
    Future.microtask(() => ref.read(appStateProvider.notifier).fetchAllUsers());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Members grouped by their real `department`, largest group first.
  Map<String, List<UserModel>> _groupByDepartment(List<UserModel> users) {
    final map = <String, List<UserModel>>{};
    for (final u in users) {
      final dept = (u.department ?? '').trim();
      map.putIfAbsent(dept.isEmpty ? _noDepartment : dept, () => []).add(u);
    }
    final entries = map.entries.toList()
      ..sort((a, b) {
        if (a.key == _noDepartment) return 1;
        if (b.key == _noDepartment) return -1;
        return b.value.length.compareTo(a.value.length);
      });
    return Map.fromEntries(entries);
  }

  void _openMember(UserModel user) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberProfileScreen(member: user)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final allUsers = state.allUsers;

    Widget header = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
      child: PageHeader(
        title: 'Team directory',
        subtitle: allUsers.isEmpty ? null : plural(allUsers.length, 'member'),
        showBack: Navigator.canPop(context),
        padding: EdgeInsets.zero,
      ),
    );

    if (state.usersLoading && allUsers.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(child: Column(children: [header, const Expanded(child: Center(child: CircularProgressIndicator()))])),
      );
    }
    if (state.usersError != null && allUsers.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          child: Column(
            children: [
              header,
              Expanded(
                child: LoadErrorView(
                  title: "Couldn't load the team",
                  message: state.usersError!,
                  onRetry: () => ref.read(appStateProvider.notifier).fetchAllUsers(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final deptGroups = _groupByDepartment(allUsers);
    final q = _searchQuery.toLowerCase().trim();
    final filteredUsers = allUsers.where((u) {
      final matchesSearch = q.isEmpty ||
          u.name.toLowerCase().contains(q) ||
          u.roleTitle.toLowerCase().contains(q) ||
          (u.department ?? '').toLowerCase().contains(q);
      if (!matchesSearch) return false;
      if (_selectedDepartment != null) return deptGroups[_selectedDepartment]?.contains(u) ?? false;
      return switch (_category) {
        1 => u.role == UserRole.intern,
        2 => u.role == UserRole.mentor,
        3 => u.isAdmin,
        _ => true,
      };
    }).toList();
    final showDepartments = _category == 0 && q.isEmpty && _selectedDepartment == null && deptGroups.length > 1;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchAllUsers(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: header),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 0, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search by name, role or department',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Clear search',
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PillFilter(
                        options: _categories,
                        selectedIndex: _selectedDepartment == null ? _category : -1,
                        onSelected: (i) => setState(() {
                          _category = i;
                          _selectedDepartment = null;
                        }),
                      ),
                    ],
                  ),
                ),
              ),

              if (showDepartments)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('Departments', style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      for (final (i, entry) in deptGroups.entries.indexed) ...[
                        _buildDepartmentCard(
                          name: entry.key,
                          count: entry.value.length,
                          accentColor: _deptColors[i % _deptColors.length],
                          onTap: () => setState(() => _selectedDepartment = entry.key),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Everyone (${allUsers.length})',
                          style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ]),
                  ),
                ),

              if (_selectedDepartment != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 0, AppSpacing.p20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        label: Text(_selectedDepartment!, overflow: TextOverflow.ellipsis),
                        deleteButtonTooltipMessage: 'Show everyone',
                        onDeleted: () => setState(() => _selectedDepartment = null),
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),

              if (filteredUsers.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: AppSpacing.p20),
                    child: Column(
                      children: [
                        const Icon(Icons.person_search_outlined, size: 54, color: AppColors.textTertiary),
                        const SizedBox(height: 12),
                        Text(
                          q.isNotEmpty ? 'Nobody matches "$_searchQuery"' : 'Nobody here yet',
                          textAlign: TextAlign.center,
                          style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          q.isNotEmpty ? 'Try another name or department.' : 'Try another filter.',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 0, AppSpacing.p20, 32),
                  sliver: SliverList.separated(
                    itemCount: filteredUsers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _buildMemberCard(filteredUsers[index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile({required VoidCallback onTap, required Widget child}) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.soft),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: child),
        ),
      ),
    );
  }

  Widget _buildDepartmentCard({
    required String name,
    required int count,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return _tile(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.14), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(Icons.apartment_rounded, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(plural(count, 'member'), style: AppTypography.caption),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildMemberCard(UserModel user) {
    return _tile(
      onTap: () => _openMember(user),
      child: Row(
        children: [
          AppAvatar(url: user.avatarUrl, fallbackText: user.name, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  [user.roleTitle, if ((user.department ?? '').isNotEmpty) user.department!].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}
