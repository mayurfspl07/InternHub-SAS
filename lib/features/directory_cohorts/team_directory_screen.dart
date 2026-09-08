import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final users = state.allUsers.isNotEmpty ? state.allUsers : state.users;

    final filteredUsers = users.where((u) {
      final dept = (u.department ?? '').toLowerCase();
      final name = u.name.toLowerCase();
      final roleTitle = u.roleTitle.toLowerCase();
      final q = _searchQuery.toLowerCase().trim();

      final matchesSearch = q.isEmpty ||
          name.contains(q) ||
          roleTitle.contains(q) ||
          dept.contains(q);

      if (!matchesSearch) return false;

      if (_selectedCategory == 'Interns') return u.role == UserRole.intern;
      if (_selectedCategory == 'Mentors') return u.role == UserRole.mentor;
      if (_selectedCategory == 'Admins') return u.role == UserRole.admin;
      return true;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(appStateProvider.notifier).fetchUsers(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Team Directory 👥',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _isSearching = !_isSearching),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? AppColors.borderDark : AppColors.borderLight,
                            ),
                          ),
                          child: Icon(
                            _isSearching ? Icons.close_rounded : Icons.search_rounded,
                            size: 20,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_isSearching)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 6),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search by name, role or department...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),

                const SizedBox(height: 8),

                // Filter Pills Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                  child: Row(
                    children: ['All', 'Interns', 'Mentors', 'Admins'].map((cat) {
                      final isSelected = _selectedCategory == cat;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.actionCircleDark
                                : (isDark ? AppColors.surfaceDark : Colors.white),
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.actionCircleDark
                                  : (isDark ? AppColors.borderDark : AppColors.borderLight),
                            ),
                          ),
                          child: Text(
                            cat,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : AppColors.textSecondaryLight),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),

                if (filteredUsers.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(40),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        Icon(Icons.person_search_outlined, size: 54, color: isDark ? Colors.white38 : AppColors.textSecondaryLight),
                        const SizedBox(height: 12),
                        Text(
                          'No members found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Try adjusting your search or category filter.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // 2-Column Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.86,
                    ),
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      Color cardBg;
                      if (index % 4 == 2) {
                        cardBg = AppColors.cardYellow;
                      } else if (index % 4 == 3) {
                        cardBg = const Color(0xFFEDE9FE);
                      } else {
                        cardBg = isDark ? AppColors.surfaceDark : Colors.white;
                      }

                      final hasCustomBg = cardBg != Colors.white && cardBg != AppColors.surfaceDark;

                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MemberProfileScreen(member: user)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(24),
                            border: isDark || cardBg == Colors.white
                                ? Border.all(
                                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                                  )
                                : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Avatar + Name
                              Row(
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
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      user.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: hasCustomBg
                                            ? Colors.black87
                                            : (isDark ? Colors.white : AppColors.textPrimaryLight),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              Text(
                                '${user.roleTitle}${user.department != null && user.department!.isNotEmpty ? ' • ${user.department}' : ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasCustomBg
                                      ? Colors.black54
                                      : (isDark ? Colors.white60 : AppColors.textSecondaryLight),
                                ),
                              ),

                              // Metric Pipeline + Arrow Action Button
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '⭐ ${user.performanceRating.toStringAsFixed(1)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: hasCustomBg
                                              ? Colors.black87
                                              : (isDark ? Colors.white : AppColors.textPrimaryLight),
                                        ),
                                      ),
                                      Text(
                                        '🔥 ${user.attendanceStreak}d Streak',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: const BoxDecoration(
                                      color: AppColors.actionCircleDark,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.arrow_outward_rounded,
                                      size: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
