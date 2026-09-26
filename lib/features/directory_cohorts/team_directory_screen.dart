import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import 'member_profile_screen.dart';

class TeamDirectoryScreen extends ConsumerStatefulWidget {
  const TeamDirectoryScreen({super.key});

  @override
  ConsumerState<TeamDirectoryScreen> createState() =>
      _TeamDirectoryScreenState();
}

class _TeamDirectoryScreenState extends ConsumerState<TeamDirectoryScreen> {
  String _selectedCategory = 'All';
  String? _selectedDepartment;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSegmentedTab(String label, String value) {
    final isSelected = _selectedCategory == value && _selectedDepartment == null;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedCategory = value;
        _selectedDepartment = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Map<String, List<UserModel>> _groupByDepartment(List<UserModel> users) {
    final Map<String, List<UserModel>> map = {
      'Development': [],
      'Design': [],
      'Product': [],
      'Marketing': [],
    };

    for (final u in users) {
      final dept = (u.department ?? '').toLowerCase();
      if (dept.contains('dev') || dept.contains('eng') || dept.contains('tech') || dept.contains('software')) {
        map['Development']!.add(u);
      } else if (dept.contains('design') || dept.contains('ui') || dept.contains('ux')) {
        map['Design']!.add(u);
      } else if (dept.contains('prod') || dept.contains('project') || dept.contains('manag')) {
        map['Product']!.add(u);
      } else if (dept.contains('market') || dept.contains('growth') || dept.contains('sales')) {
        map['Marketing']!.add(u);
      } else {
        // Distribute or add
        map['Development']!.add(u);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final allUsers = state.allUsers.isNotEmpty ? state.allUsers : state.users;
    final deptGroups = _groupByDepartment(allUsers);

    final filteredUsers = allUsers.where((u) {
      final dept = (u.department ?? '').toLowerCase();
      final name = u.name.toLowerCase();
      final roleTitle = u.roleTitle.toLowerCase();
      final q = _searchQuery.toLowerCase().trim();

      final matchesSearch = q.isEmpty ||
          name.contains(q) ||
          roleTitle.contains(q) ||
          dept.contains(q);

      if (!matchesSearch) return false;

      if (_selectedDepartment != null) {
        return deptGroups[_selectedDepartment]?.contains(u) ?? false;
      }

      if (_selectedCategory == 'Interns') return u.role == UserRole.intern;
      if (_selectedCategory == 'Mentors') return u.role == UserRole.mentor;
      if (_selectedCategory == 'Admins') return u.role == UserRole.admin;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchUsers(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Top Header Sliver
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageHeader(
                        title: 'Team Directory',
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 16),

                      // Segmented Tab Row: [All] [Interns] [Mentors] [Admins]
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildSegmentedTab('All', 'All'),
                                _buildSegmentedTab('Interns', 'Interns'),
                                _buildSegmentedTab('Mentors', 'Mentors'),
                                _buildSegmentedTab('Admins', 'Admins'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Search bar
                      TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: TextStyle(color: primaryTextColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search members by name or role...',
                          hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                          prefixIcon: Icon(Icons.search_rounded, size: 20, color: secondaryTextColor),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear_rounded, size: 18, color: secondaryTextColor),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: cardBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Department Cards Section (Shown when "All" is active and no active text search)
              if (_selectedCategory == 'All' && _searchQuery.isEmpty && _selectedDepartment == null)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildDepartmentCard(
                        name: 'Development',
                        count: deptGroups['Development']?.length ?? 12,
                        icon: Icons.code_rounded,
                        accentColor: AppColors.info,
                        cardBg: cardBg,
                        borderColor: borderColor,
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor,
                        onTap: () => setState(() => _selectedDepartment = 'Development'),
                      ),
                      const SizedBox(height: 10),
                      _buildDepartmentCard(
                        name: 'Design',
                        count: deptGroups['Design']?.length ?? 6,
                        icon: Icons.palette_outlined,
                        accentColor: AppColors.peachInk,
                        cardBg: cardBg,
                        borderColor: borderColor,
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor,
                        onTap: () => setState(() => _selectedDepartment = 'Design'),
                      ),
                      const SizedBox(height: 10),
                      _buildDepartmentCard(
                        name: 'Product',
                        count: deptGroups['Product']?.length ?? 4,
                        icon: Icons.layers_outlined,
                        accentColor: AppColors.primary,
                        cardBg: cardBg,
                        borderColor: borderColor,
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor,
                        onTap: () => setState(() => _selectedDepartment = 'Product'),
                      ),
                      const SizedBox(height: 10),
                      _buildDepartmentCard(
                        name: 'Marketing',
                        count: deptGroups['Marketing']?.length ?? 8,
                        icon: Icons.campaign_outlined,
                        accentColor: AppColors.info,
                        cardBg: cardBg,
                        borderColor: borderColor,
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor,
                        onTap: () => setState(() => _selectedDepartment = 'Marketing'),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'All Members (${allUsers.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),

              // Filter Tag chip if a department was clicked
              if (_selectedDepartment != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
                    child: Row(
                      children: [
                        Chip(
                          label: Text('Department: $_selectedDepartment'),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () => setState(() => _selectedDepartment = null),
                          backgroundColor: cardBg,
                          side: BorderSide(color: borderColor),
                        ),
                      ],
                    ),
                  ),
                ),

              // Members List Cards
              if (filteredUsers.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: AppSpacing.p20),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_search_outlined, size: 54, color: secondaryTextColor),
                          const SizedBox(height: 12),
                          Text(
                            'No members found',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                          ),
                          const SizedBox(height: 4),
                          Text('Try adjusting your search or category filter.', style: TextStyle(fontSize: 13, color: secondaryTextColor)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 0, AppSpacing.p20, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final user = filteredUsers[index];
                        return _buildMemberCard(
                          user: user,
                          cardBg: cardBg,
                          borderColor: borderColor,
                          primaryTextColor: primaryTextColor,
                          secondaryTextColor: secondaryTextColor,
                        );
                      },
                      childCount: filteredUsers.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentCard({
    required String name,
    required int count,
    required IconData icon,
    required Color accentColor,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count Members',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surfaceMuted,
              foregroundColor: AppColors.ink,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rPill),
              ),
            ),
            child: const Text('View', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard({
    required UserModel user,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            backgroundImage: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                ? Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryInk),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.roleTitle}${user.department != null && user.department!.isNotEmpty ? ' • ${user.department}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MemberProfileScreen(member: user)),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.lavender,
              foregroundColor: AppColors.primaryInk,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.rPill),
              ),
            ),
            child: const Text('View', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
