import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import 'models/standup_models.dart';
import 'standup_repository.dart';

class StandupScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const StandupScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<StandupScreen> createState() => _StandupScreenState();
}

class _StandupScreenState extends ConsumerState<StandupScreen> {
  final StandupRepository _repository = StandupRepository();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _didController = TextEditingController();
  final TextEditingController _planController = TextEditingController();
  final TextEditingController _blockersController = TextEditingController();

  Timer? _debounceTimer;

  bool _isLoading = true;
  String? _errorMessage;
  bool _isSubmittingInline = false;

  List<StandupLog> _logs = [];
  StandupLog? _todayLog;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;

  String _searchQuery = '';
  String _selectedMood = 'all'; // all | great | good | okay | bad
  String _activeTab = 'my_standup'; // 'my_standup' | 'team_feed'
  DateTime _selectedDate = DateTime.now();
  String _formMood = 'great'; // great, good, okay, bad, terrible

  @override
  void initState() {
    super.initState();
    _fetchFeedAndToday();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _didController.dispose();
    _planController.dispose();
    _blockersController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = value.trim();
          _currentPage = 1;
        });
        _fetchFeed();
      }
    });
  }

  void _onMoodFilterTap(String mood) {
    setState(() {
      if (_selectedMood == mood) {
        _selectedMood = 'all';
      } else {
        _selectedMood = mood;
      }
      _currentPage = 1;
    });
    _fetchFeed();
  }

  Future<void> _fetchFeedAndToday() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final todayFuture = _repository.getTodayStandup();
      final feedFuture = _repository.getStandupFeed(
        page: _currentPage,
        pageSize: 12,
        search: _searchQuery,
        mood: _selectedMood,
      );

      final results = await Future.wait([todayFuture, feedFuture]);
      final todayRes = results[0] as StandupLog?;
      final feedRes = results[1] as StandupListResponse;

      if (mounted) {
        setState(() {
          _todayLog = todayRes;
          _logs = feedRes.logs;
          _totalPages = feedRes.totalPages;
          _totalCount = feedRes.total;
          _isLoading = false;

          if (todayRes != null) {
            _didController.text = todayRes.did;
            _planController.text = todayRes.plan;
            _blockersController.text = todayRes.blockers ?? '';
            _formMood = todayRes.mood.toLowerCase();
          }
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

  Future<void> _submitInlineStandup() async {
    final did = _didController.text.trim();
    if (did.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please tell us what you worked on'), backgroundColor: AppColors.danger),
      );
      return;
    }
    final plan = _planController.text.trim();
    if (plan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please tell us what you will work on'), backgroundColor: AppColors.danger),
      );
      return;
    }
    final blockers = _blockersController.text.trim();

    setState(() => _isSubmittingInline = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      if (_todayLog != null) {
        await _repository.updateStandup(
          _todayLog!.id,
          did: did,
          plan: plan,
          blockers: blockers.isNotEmpty ? blockers : 'No blockers.',
          mood: _formMood,
        );
      } else {
        await _repository.createStandup(
          date: dateStr,
          did: did,
          plan: plan,
          blockers: blockers.isNotEmpty ? blockers : 'No blockers.',
          mood: _formMood,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_todayLog != null ? 'Standup updated successfully' : 'Daily standup submitted!'),
            backgroundColor: AppColors.success,
          ),
        );
        _fetchFeedAndToday();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit standup: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmittingInline = false);
    }
  }

  Future<void> _fetchFeed() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final feedRes = await _repository.getStandupFeed(
        page: _currentPage,
        pageSize: 12,
        search: _searchQuery,
        mood: _selectedMood,
      );

      if (mounted) {
        setState(() {
          _logs = feedRes.logs;
          _totalPages = feedRes.totalPages;
          _totalCount = feedRes.total;
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

  // Search and mood filters are applied by the API (GET /api/standup?search&mood).
  List<StandupLog> get _filteredLogs => _logs;

  void _openCreateOrTodayDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StandupCreateOrTodayDialog(
        todayLog: _todayLog,
        onSuccess: _fetchFeedAndToday,
      ),
    );
  }

  void _openEditCardDialog(StandupLog log) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StandupCardEditDialog(
        log: log,
        onSuccess: _fetchFeedAndToday,
      ),
    );
  }

  Future<void> _confirmDelete(StandupLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Standup Entry?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: Text(
            'Are you sure you want to delete this standup entry by ${log.userName ?? "team member"} for ${formatDisplayDate(log.date)}? This action cannot be undone.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _repository.deleteStandup(log.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Standup entry deleted'),
              backgroundColor: AppColors.success,
            ),
          );
          _fetchFeedAndToday();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: AppColors.danger),
          );
        }
      }
    }
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages || page == _currentPage) return;
    setState(() => _currentPage = page);
    _fetchFeed();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    final bgColor = AppColors.canvas;
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final filtered = _filteredLogs;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchFeedAndToday,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header & Segmented Pill Switcher
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageHeader(
                        title: 'Standup',
                        showBack: widget.showBackButton && Navigator.canPop(context),
                        padding: EdgeInsets.zero,
                        actions: [
                          HeaderAction(icon: Icons.refresh_rounded, onTap: _fetchFeedAndToday),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Segmented Pills [My Standup] [Team Feed]
                      Row(
                        children: [
                          _buildSegmentedTab('My Standup', 'my_standup'),
                          const SizedBox(width: 10),
                          _buildSegmentedTab('Team Feed', 'team_feed'),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // In Team Feed: show search + filters
                      if (_activeTab == 'team_feed') ...[
                        if (_todayLog != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.successSoft,
                              borderRadius: BorderRadius.circular(AppSpacing.r20),
                              border: Border.all(color: AppColors.successSoft),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.successSoft,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "You've logged today's standup (${formatDisplayDate(_todayLog!.date)})",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.successInk,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'Need to make adjustments? Switch to My Standup anytime.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.successInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Filters Bar: Search + Mood Chips
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 700;

                            final searchInput = Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Row(
                                children: [
                                  Icon(Icons.search, size: 18, color: secondaryTextColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      onChanged: _onSearchChanged,
                                      style: TextStyle(fontSize: 13, color: primaryTextColor),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                        border: InputBorder.none,
                                        filled: false,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        hintText: 'Search by team member, accomplishments, plans…',
                                        hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                                      ),
                                    ),
                                  ),
                                  if (_searchController.text.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        _searchController.clear();
                                        _onSearchChanged('');
                                      },
                                      child: Icon(Icons.close, size: 16, color: secondaryTextColor),
                                    ),
                                ],
                              ),
                            );

                            final moodChips = Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _buildMoodChip(
                                  label: 'All Standups ($_totalCount)',
                                  isSelected: _selectedMood == 'all',
                                  onTap: () => _onMoodFilterTap('all'),
                                  cardBg: cardBg,
                                  borderColor: borderColor,
                                  primaryTextColor: primaryTextColor,
                                  secondaryTextColor: secondaryTextColor,
                                ),
                                ...standupMoodOptions.map((opt) {
                                  return _buildMoodChip(
                                    label: opt.label,
                                    isSelected: _selectedMood == opt.value,
                                    onTap: () => _onMoodFilterTap(opt.value),
                                    cardBg: cardBg,
                                    borderColor: borderColor,
                                    primaryTextColor: primaryTextColor,
                                    secondaryTextColor: secondaryTextColor,
                                  );
                                }),
                              ],
                            );

                            if (isWide) {
                              return Row(
                                children: [
                                  Expanded(child: searchInput),
                                  const SizedBox(width: 14),
                                  moodChips,
                                ],
                              );
                            } else {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  searchInput,
                                  const SizedBox(height: 12),
                                  moodChips,
                                ],
                              );
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // If My Standup tab active: show Screen 5 form
              if (_activeTab == 'my_standup')
                _buildMyStandupForm(cardBg, borderColor, primaryTextColor, secondaryTextColor),

              // If Team Feed tab active: show feed slivers
              if (_activeTab == 'team_feed') ...[

              // Content / Feed / States
              if (_isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_errorMessage != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: AppSpacing.p20),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.error_outline, size: 36, color: AppColors.danger),
                          const SizedBox(height: 8),
                          Text(_errorMessage!, style: const TextStyle(color: AppColors.danger)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _fetchFeedAndToday,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                // Dashed Card Empty State matching web screenshot
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 12),
                    child: _buildDashedEmptyCard(
                      borderColor: borderColor,
                      primaryTextColor: primaryTextColor,
                      secondaryTextColor: secondaryTextColor,
                      hasFilters: _searchQuery.isNotEmpty || _selectedMood != 'all',
                      onLogFirst: _openCreateOrTodayDialog,
                    ),
                  ),
                )
              else
                // Feed Grid / List
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.crossAxisExtent > 900
                          ? 2
                          : 1;

                      if (crossAxisCount == 1) {
                        return SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final log = filtered[index];
                              return _buildStandupCard(
                                log: log,
                                user: user,
                                cardBg: cardBg,
                                borderColor: borderColor,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                              );
                            },
                            childCount: filtered.length,
                          ),
                        );
                      } else {
                        return SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 14,
                            crossAxisSpacing: 14,
                            mainAxisExtent: 280,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final log = filtered[index];
                              return _buildStandupCard(
                                log: log,
                                user: user,
                                cardBg: cardBg,
                                borderColor: borderColor,
                                primaryTextColor: primaryTextColor,
                                secondaryTextColor: secondaryTextColor,
                              );
                            },
                            childCount: filtered.length,
                          ),
                        );
                      }
                    },
                  ),
                ),

              // Pagination Footer
              if (_totalPages > 1 && !_isLoading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 20, AppSpacing.p20, 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
                          icon: const Icon(Icons.chevron_left_rounded, size: 18),
                          label: const Text('Previous'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Showing page $_currentPage of $_totalPages ($_totalCount total standups)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _currentPage < _totalPages ? () => _goToPage(_currentPage + 1) : null,
                          icon: const Icon(Icons.chevron_right_rounded, size: 18),
                          label: const Text('Next'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ],
        ),
      ),
    ),
  );
}

  Widget _buildSegmentedTab(String label, String key) {
    final isSelected = _activeTab == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = key;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildMyStandupForm(
    Color cardBg,
    Color borderColor,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    final moods = [
      {'key': 'great', 'label': 'Great', 'emoji': '🔥', 'color': AppColors.success},
      {'key': 'good', 'label': 'Good', 'emoji': '😊', 'color': AppColors.info},
      {'key': 'okay', 'label': 'Okay', 'emoji': '😐', 'color': AppColors.primary},
      {'key': 'tired', 'label': 'Tired', 'emoji': '😴', 'color': AppColors.warning},
      {'key': 'stressed', 'label': 'Stressed', 'emoji': '😫', 'color': AppColors.danger},
    ];

    final dateFormatted = DateFormat('MMM dd, yyyy').format(_selectedDate);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Date Navigator Pill: < Oct 16, 2024 >
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  boxShadow: AppShadows.soft,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                        });
                      },
                      child: Icon(Icons.chevron_left_rounded, size: 20, color: secondaryTextColor),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateFormatted,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: primaryTextColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDate = _selectedDate.add(const Duration(days: 1));
                        });
                      },
                      child: Icon(Icons.chevron_right_rounded, size: 20, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. "How was your day?" title & Emoji row
            Text(
              'How was your day?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: moods.map((m) {
                final isSelected = _formMood == m['key'];
                final color = m['color'] as Color;
                return GestureDetector(
                  onTap: () => setState(() => _formMood = m['key'] as String),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? color.withValues(alpha: 0.15) : Colors.white,
                          border: Border.all(
                            color: isSelected ? color : borderColor,
                            width: isSelected ? 2.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            m['emoji'] as String,
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m['label'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? color : secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // 3. "Today's Updates" Section
            Text(
              "Today's Updates",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: 12),

            // Card 1: What did you work on?
            _buildQuestionInputCard(
              label: 'What did you work on?',
              hint: 'Completed the dashboard UI and fixed some bugs.',
              controller: _didController,
              cardBg: cardBg,
              borderColor: borderColor,
              primaryTextColor: primaryTextColor,
              secondaryTextColor: secondaryTextColor,
            ),
            const SizedBox(height: 14),

            // Card 2: What will you work on?
            _buildQuestionInputCard(
              label: 'What will you work on?',
              hint: 'Work on project documentation.',
              controller: _planController,
              cardBg: cardBg,
              borderColor: borderColor,
              primaryTextColor: primaryTextColor,
              secondaryTextColor: secondaryTextColor,
            ),
            const SizedBox(height: 14),

            // Card 3: Blockers (if any)
            _buildQuestionInputCard(
              label: 'Blockers (if any)',
              hint: 'No blockers.',
              controller: _blockersController,
              cardBg: cardBg,
              borderColor: borderColor,
              primaryTextColor: primaryTextColor,
              secondaryTextColor: secondaryTextColor,
            ),
            const SizedBox(height: 24),

            // Full-width Purple Pill Submit Button (Screen 5 in Reference UI)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSubmittingInline ? null : _submitInlineStandup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  ),
                ),
                child: _isSubmittingInline
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
                      )
                    : Text(
                        _todayLog != null ? "Update Standup" : "Submit",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onPrimary,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionInputCard({
    required String label,
    required String hint,
    required TextEditingController controller,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.p16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppSpacing.r24),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 3,
            minLines: 2,
            style: TextStyle(fontSize: 13, color: primaryTextColor),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor.withValues(alpha: 0.6)),
              filled: true,
              fillColor: AppColors.surfaceMuted,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.r16),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.r16),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.r16),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? AppColors.onPrimary
                : secondaryTextColor,
          ),
        ),
      ),
    );
  }

  Widget _buildDashedEmptyCard({
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required bool hasFilters,
    required VoidCallback onLogFirst,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined, size: 48, color: secondaryTextColor.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(
              'No standup logs found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Try resetting your search query or mood filter.'
                  : 'No team members have posted standups yet.',
              style: TextStyle(
                fontSize: 13,
                color: secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (!hasFilters) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onLogFirst,
                icon: const Icon(Icons.add, size: 16, color: AppColors.ink),
                label: const Text(
                  'Log First Standup',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.ink),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.ink,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: AppColors.warning, width: 1),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStandupCard({
    required StandupLog log,
    required UserModel user,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    final canManage = canManageLog(log.userId, user);
    final initial = (log.userName ?? 'T').isNotEmpty ? log.userName![0].toUpperCase() : 'T';

    // Mood pill colors
    Color moodBg;
    Color moodFg;
    switch (log.mood.toLowerCase()) {
      case 'great':
        moodBg = AppColors.successSoft;
        moodFg = AppColors.successInk;
        break;
      case 'good':
        moodBg = AppColors.infoSoft;
        moodFg = AppColors.info;
        break;
      case 'okay':
        moodBg = AppColors.warningSoft;
        moodFg = AppColors.warningInk;
        break;
      case 'tired':
        moodBg = AppColors.warningSoft;
        moodFg = AppColors.warningInk;
        break;
      case 'stressed':
        moodBg = AppColors.dangerSoft;
        moodFg = AppColors.danger;
        break;
      default:
        moodBg = AppColors.surfaceMuted;
        moodFg = AppColors.textSecondary;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: User + Mood + Actions
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.info.withValues(alpha: 0.25), width: 1),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.info,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  log.userName ?? 'Team Member',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Mood pill (only when a mood was recorded)
              if (getMoodLabel(log.mood).isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: moodBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(getMoodEmoji(log.mood), style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 4),
                    Text(
                      getMoodLabel(log.mood),
                      style: TextStyle(
                        color: moodFg,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: secondaryTextColor,
                  tooltip: 'Edit Standup',
                  onPressed: () => _openEditCardDialog(log),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  color: AppColors.danger,
                  tooltip: 'Delete Standup',
                  onPressed: () => _confirmDelete(log),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Accomplished Block
          Text(
            'Accomplished',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: secondaryTextColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            log.did,
            style: TextStyle(fontSize: 13, color: primaryTextColor),
          ),
          const SizedBox(height: 10),

          // Plan for Next Block
          Text(
            'Plan for Next',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: secondaryTextColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            log.plan,
            style: TextStyle(fontSize: 13, color: primaryTextColor),
          ),

          // Blockers Block (only if present and not "None")
          if (log.hasBlockers) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warningSoft.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primarySoft),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warningInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Blockers',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warningInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          log.blockers!,
                          style: const TextStyle(fontSize: 12, color: AppColors.warningInk),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // Footer: Date and Time
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 12, color: secondaryTextColor),
              const SizedBox(width: 5),
              Text(
                formatDisplayDate(log.date),
                style: TextStyle(fontSize: 11, color: secondaryTextColor),
              ),
              if (log.createdAt.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.access_time_rounded, size: 12, color: secondaryTextColor),
                const SizedBox(width: 5),
                Text(
                  formatDisplayTime(log.createdAt),
                  style: TextStyle(fontSize: 11, color: secondaryTextColor),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CREATE OR TODAY STANDUP DIALOG
// ============================================================================
class _StandupCreateOrTodayDialog extends StatefulWidget {
  final StandupLog? todayLog;
  final VoidCallback onSuccess;

  const _StandupCreateOrTodayDialog({
    this.todayLog,
    required this.onSuccess,
  });

  @override
  State<_StandupCreateOrTodayDialog> createState() => _StandupCreateOrTodayDialogState();
}

class _StandupCreateOrTodayDialogState extends State<_StandupCreateOrTodayDialog> {
  final StandupRepository _repository = StandupRepository();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _dateController;
  late TextEditingController _didController;
  late TextEditingController _planController;
  late TextEditingController _blockersController;
  String _selectedMood = 'good';

  bool _isSubmitting = false;

  bool get isUpdate => widget.todayLog != null;

  @override
  void initState() {
    super.initState();
    final log = widget.todayLog;
    if (log != null) {
      _dateController = TextEditingController(text: log.date);
      _didController = TextEditingController(text: log.did);
      _planController = TextEditingController(text: log.plan);
      _blockersController = TextEditingController(text: log.blockers ?? '');
      _selectedMood = log.mood.toLowerCase();
    } else {
      final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      _dateController = TextEditingController(text: nowStr);
      _didController = TextEditingController();
      _planController = TextEditingController();
      _blockersController = TextEditingController();
      _selectedMood = 'good';
    }

    _didController.addListener(() => setState(() {}));
    _planController.addListener(() => setState(() {}));
    _blockersController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _dateController.dispose();
    _didController.dispose();
    _planController.dispose();
    _blockersController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final did = _didController.text.trim();
    if (did.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('What did you accomplish is required'), backgroundColor: AppColors.danger),
      );
      return;
    }
    if (did.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('What did you accomplish cannot exceed 1000 characters'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final plan = _planController.text.trim();
    if (plan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('What will you work on is required'), backgroundColor: AppColors.danger),
      );
      return;
    }
    if (plan.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('What will you work on cannot exceed 1000 characters'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final blockers = _blockersController.text.trim();
    if (blockers.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Blockers cannot exceed 1000 characters'), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (isUpdate) {
        await _repository.updateStandup(
          widget.todayLog!.id,
          did: did,
          plan: plan,
          blockers: blockers.isNotEmpty ? blockers : 'None',
          mood: _selectedMood,
        );
      } else {
        await _repository.createStandup(
          date: _dateController.text.trim(),
          did: did,
          plan: plan,
          blockers: blockers.isNotEmpty ? blockers : 'None',
          mood: _selectedMood,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isUpdate ? 'Standup entry updated' : 'Daily standup logged successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 540,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isUpdate ? "Update Today's Standup" : "Log Daily Standup",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 16),
                      color: secondaryTextColor,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Standup Date * (disabled if todayLog exists)
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          children: const [
                            TextSpan(text: 'STANDUP DATE '),
                            TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _dateController,
                        enabled: !isUpdate,
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 16, color: secondaryTextColor),
                          filled: isUpdate,
                          fillColor: AppColors.surfaceMuted,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Accomplished *
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                              children: const [
                                TextSpan(text: 'WHAT DID YOU ACCOMPLISH TODAY? '),
                                TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                              ],
                            ),
                          ),
                          Text('${_didController.text.length}/1000', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _didController,
                        maxLines: 3,
                        maxLength: 1000,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'Implemented backend API authentication, finished unit tests...',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Plan *
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                              children: const [
                                TextSpan(text: 'WHAT WILL YOU WORK ON NEXT? '),
                                TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                              ],
                            ),
                          ),
                          Text('${_planController.text.length}/1000', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _planController,
                        maxLines: 3,
                        maxLength: 1000,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'Integrate Scalar interactive documentation and verify schemas...',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Blockers
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ANY BLOCKERS OR IMPEDIMENTS? (OPTIONAL)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                          Text('${_blockersController.text.length}/1000', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _blockersController,
                        maxLines: 2,
                        maxLength: 1000,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          hintText: 'None, or waiting on API schema confirmation...',
                          hintStyle: TextStyle(fontSize: 13, color: secondaryTextColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Mood emoji buttons (Screen 5)
                      Text(
                        'HOW WAS YOUR DAY?',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: standupMoodOptions.map((opt) {
                            final isSelected = _selectedMood == opt.value;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => setState(() => _selectedMood = opt.value),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(AppSpacing.rPill),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.border,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(opt.emoji, style: const TextStyle(fontSize: 15)),
                                      const SizedBox(width: 6),
                                      Text(
                                        opt.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? AppColors.onPrimary
                                              : AppColors.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),
            // Footer Actions
            Padding(
              padding: const EdgeInsets.all(18),
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.rPill)),
                      side: BorderSide(color: AppColors.border),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                        : const Icon(Icons.near_me_rounded, size: 16, color: AppColors.onPrimary),
                    label: Text(
                      _isSubmitting
                          ? 'Saving…'
                          : (isUpdate ? 'Update Standup' : 'Submit Standup'),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.onPrimary),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.rPill),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// EDIT STANDUP DIALOG (FROM CARD)
// ============================================================================
class _StandupCardEditDialog extends StatefulWidget {
  final StandupLog log;
  final VoidCallback onSuccess;

  const _StandupCardEditDialog({
    required this.log,
    required this.onSuccess,
  });

  @override
  State<_StandupCardEditDialog> createState() => _StandupCardEditDialogState();
}

class _StandupCardEditDialogState extends State<_StandupCardEditDialog> {
  final StandupRepository _repository = StandupRepository();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _didController;
  late TextEditingController _planController;
  late TextEditingController _blockersController;
  late String _selectedMood;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _didController = TextEditingController(text: widget.log.did);
    _planController = TextEditingController(text: widget.log.plan);
    _blockersController = TextEditingController(text: widget.log.blockers ?? '');
    _selectedMood = widget.log.mood.toLowerCase();

    _didController.addListener(() => setState(() {}));
    _planController.addListener(() => setState(() {}));
    _blockersController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _didController.dispose();
    _planController.dispose();
    _blockersController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final did = _didController.text.trim();
    if (did.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('What did you accomplish is required'), backgroundColor: AppColors.danger),
      );
      return;
    }
    if (did.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('What did you accomplish cannot exceed 1000 characters'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final plan = _planController.text.trim();
    if (plan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('What will you work on is required'), backgroundColor: AppColors.danger),
      );
      return;
    }
    if (plan.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('What will you work on cannot exceed 1000 characters'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final blockers = _blockersController.text.trim();
    if (blockers.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Blockers cannot exceed 1000 characters'), backgroundColor: AppColors.danger),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _repository.updateStandup(
        widget.log.id,
        did: did,
        plan: plan,
        blockers: blockers.isNotEmpty ? blockers : 'None',
        mood: _selectedMood,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Standup entry updated'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = Colors.white;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 540,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Standup Entry',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryTextColor),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.log.userName ?? "Team Member"} • ${formatDisplayDate(widget.log.date)}',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 16),
                      color: secondaryTextColor,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Form Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Accomplished *
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                              children: const [
                                TextSpan(text: 'WHAT DID YOU ACCOMPLISH TODAY? '),
                                TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                              ],
                            ),
                          ),
                          Text('${_didController.text.length}/1000', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _didController,
                        maxLines: 3,
                        maxLength: 1000,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Plan *
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                              children: const [
                                TextSpan(text: 'WHAT WILL YOU WORK ON NEXT? '),
                                TextSpan(text: '*', style: TextStyle(color: AppColors.danger)),
                              ],
                            ),
                          ),
                          Text('${_planController.text.length}/1000', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _planController,
                        maxLines: 3,
                        maxLength: 1000,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Blockers
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'ANY BLOCKERS OR IMPEDIMENTS? (OPTIONAL)',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                          ),
                          Text('${_blockersController.text.length}/1000', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _blockersController,
                        maxLines: 2,
                        maxLength: 1000,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => const SizedBox.shrink(),
                        style: TextStyle(fontSize: 13, color: primaryTextColor),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Mood dropdown
                      Text(
                        'CURRENT MOOD / ENERGY',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: secondaryTextColor),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedMood,
                            isExpanded: true,
                            dropdownColor: cardBg,
                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: secondaryTextColor),
                            style: TextStyle(fontSize: 13, color: primaryTextColor),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedMood = val);
                            },
                            items: standupMoodOptions.map((opt) {
                              return DropdownMenuItem<String>(
                                value: opt.value,
                                child: Row(
                                  children: [
                                    Text(opt.emoji, style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 8),
                                    Text(opt.label, style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),
            // Footer Actions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.ink,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.warning, width: 1),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                        : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.ink)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
