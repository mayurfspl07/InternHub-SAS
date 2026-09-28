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
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../shared/widgets/app_avatar.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../../shared/widgets/custom_text_field.dart';
import '../../core/utils/formatters.dart';

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
  String? _formMood; // great | good | okay | tired | stressed; null until picked

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
            final mood = todayRes.mood.toLowerCase();
            _formMood = const ['great', 'good', 'okay', 'tired', 'stressed'].contains(mood) ? mood : null;
          }
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
    if (_formMood == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick how your day went'), backgroundColor: AppColors.danger),
      );
      return;
    }
    final blockers = _blockersController.text.trim();

    setState(() => _isSubmittingInline = true);
    try {
      // Interns can only post today's standup.
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (_todayLog != null) {
        await _repository.updateStandup(
          _todayLog!.id,
          did: did,
          plan: plan,
          blockers: blockers,
          mood: _formMood!,
        );
      } else {
        await _repository.createStandup(
          date: dateStr,
          did: did,
          plan: plan,
          blockers: blockers,
          mood: _formMood!,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_todayLog != null ? 'Standup updated' : 'Standup posted'),
            backgroundColor: AppColors.success,
          ),
        );
        _fetchFeedAndToday();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit standup: ${apiErrorMessage(e)}'), backgroundColor: AppColors.danger),
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
          _errorMessage = apiErrorMessage(e);
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
      builder: (_) => _StandupFormDialog(
        log: _todayLog,
        onSuccess: _fetchFeedAndToday,
      ),
    );
  }

  void _openEditCardDialog(StandupLog log) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StandupFormDialog(
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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Delete Standup Entry?', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
          content: Text(
            'Are you sure you want to delete this standup entry by ${log.userName ?? "team member"} for ${formatDisplayDate(log.date)}? This action cannot be undone.',
            style: AppTypography.body.copyWith(color: AppColors.ink),
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
                foregroundColor: AppColors.surface,
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
            SnackBar(content: Text('Failed to delete: ${apiErrorMessage(e)}'), backgroundColor: AppColors.danger),
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
    final cardBg = AppColors.surface;
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
                          HeaderAction(icon: Icons.refresh_rounded, tooltip: 'Refresh', onTap: _fetchFeedAndToday),
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
                                        style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: AppColors.successInk),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Need to make adjustments? Switch to My Standup anytime.',
                                        style: AppTypography.caption.copyWith(color: AppColors.successInk),
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
                                      style: AppTypography.caption.copyWith(color: primaryTextColor),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                        border: InputBorder.none,
                                        filled: false,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        hintText: 'Search by team member, accomplishments, plans…',
                                        hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor),
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
                if (_isLoading && _todayLog == null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (_errorMessage != null && _todayLog == null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.p20),
                      child: LoadErrorView(
                        title: "Couldn't load your standup",
                        message: _errorMessage!,
                        onRetry: _fetchFeedAndToday,
                        compact: true,
                      ),
                    ),
                  )
                else
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
                    padding: const EdgeInsets.all(AppSpacing.p20),
                    child: LoadErrorView(
                      title: "Couldn't load standups",
                      message: _errorMessage!,
                      onRetry: _fetchFeedAndToday,
                      compact: true,
                    ),
                  ),
                )
              else if (filtered.isEmpty)
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
                    padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 12, AppSpacing.p20, 32),
                    child: PaginationBar(
                      page: _currentPage,
                      totalPages: _totalPages,
                      totalItems: _totalCount,
                      itemLabel: 'standups',
                      onPageChanged: _goToPage,
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
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.rPill),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: isSelected ? AppColors.onPrimary : AppColors.textSecondary),
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

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The form always edits today's standup (the API accepts today only for interns).
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  boxShadow: AppShadows.soft,
                ),
                child: Text(
                  'Today · ${DateFormat('EEE, d MMM').format(DateTime.now())}',
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. "How was your day?" title & Emoji row
            Text(
              'How was your day?',
              style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
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
                          color: isSelected ? color.withValues(alpha: 0.15) : AppColors.surface,
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
                            style: AppTypography.title,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m['label'] as String,
                        style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: isSelected ? color : secondaryTextColor),
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
              style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
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
                        style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700, color: AppColors.onPrimary),
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
            style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 3,
            minLines: 2,
            style: AppTypography.caption.copyWith(color: primaryTextColor),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTypography.caption.copyWith(color: secondaryTextColor.withValues(alpha: 0.6)),
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
          style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: isSelected
                ? AppColors.onPrimary
                : secondaryTextColor),
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
              style: AppTypography.section.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Try resetting your search query or mood filter.'
                  : 'No team members have posted standups yet.',
              style: AppTypography.caption.copyWith(color: secondaryTextColor),
              textAlign: TextAlign.center,
            ),
            if (!hasFilters) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onLogFirst,
                icon: const Icon(Icons.add, size: 16, color: AppColors.ink),
                label: Text(
                  'Log First Standup',
                  style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink),
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
        moodFg = AppColors.infoInk;
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
        moodFg = AppColors.dangerInk;
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
              AppAvatar(size: 34, fallbackText: log.userName ?? ''),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  log.userName ?? 'Team Member',
                  style: AppTypography.bodyStrong.copyWith(fontWeight: FontWeight.w700, color: primaryTextColor),
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
                    Text(getMoodEmoji(log.mood), style: AppTypography.label.copyWith(color: AppColors.ink)),
                    const SizedBox(width: 4),
                    Text(
                      getMoodLabel(log.mood),
                      style: AppTypography.label.copyWith(color: moodFg, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              if (canManage) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: secondaryTextColor,
                  tooltip: 'Edit standup',
                  onPressed: () => _openEditCardDialog(log),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: AppColors.dangerInk,
                  tooltip: 'Delete standup',
                  onPressed: () => _confirmDelete(log),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Accomplished Block
          Text(
            'Accomplished',
            style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: secondaryTextColor, letterSpacing: 0.5),
          ),
          const SizedBox(height: 3),
          Text(
            log.did,
            style: AppTypography.caption.copyWith(color: primaryTextColor),
          ),
          const SizedBox(height: 10),

          // Plan for Next Block
          Text(
            'Next',
            style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: secondaryTextColor, letterSpacing: 0.5),
          ),
          const SizedBox(height: 3),
          Text(
            log.plan,
            style: AppTypography.caption.copyWith(color: primaryTextColor),
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
                        Text(
                          'Blockers',
                          style: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.warningInk),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          log.blockers!,
                          style: AppTypography.caption.copyWith(color: AppColors.warningInk),
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
                style: AppTypography.label.copyWith(color: secondaryTextColor),
              ),
              if (log.createdAt.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.access_time_rounded, size: 12, color: secondaryTextColor),
                const SizedBox(width: 5),
                Text(
                  formatDisplayTime(log.createdAt),
                  style: AppTypography.label.copyWith(color: secondaryTextColor),
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
/// Post today's standup, or edit an existing one ([log]).
/// Validation shows under each field; the dialog is only as tall as its content.
class _StandupFormDialog extends StatefulWidget {
  final StandupLog? log;
  final VoidCallback onSuccess;

  const _StandupFormDialog({this.log, required this.onSuccess});

  @override
  State<_StandupFormDialog> createState() => _StandupFormDialogState();
}

class _StandupFormDialogState extends State<_StandupFormDialog> {
  final _repository = StandupRepository();
  late final TextEditingController _did;
  late final TextEditingController _plan;
  late final TextEditingController _blockers;
  String? _mood;
  String? _didError;
  String? _planError;
  String? _moodError;
  String? _serverError;
  bool _saving = false;

  bool get _isEdit => widget.log != null;

  @override
  void initState() {
    super.initState();
    final log = widget.log;
    _did = TextEditingController(text: log?.did ?? '');
    _plan = TextEditingController(text: log?.plan ?? '');
    final blockers = log?.hasBlockers == true ? log!.blockers! : '';
    _blockers = TextEditingController(text: blockers);
    final mood = log?.mood.toLowerCase() ?? '';
    // Older logs may have no mood (or one no longer offered): start unselected instead of crashing.
    _mood = standupMoodOptions.any((o) => o.value == mood) ? mood : null;
  }

  @override
  void dispose() {
    _did.dispose();
    _plan.dispose();
    _blockers.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _didError = _did.text.trim().isEmpty ? 'Tell your team what you worked on' : null;
      _planError = _plan.text.trim().isEmpty ? 'Tell your team what you will work on next' : null;
      _moodError = _mood == null ? 'Pick how your day went' : null;
      _serverError = null;
    });
    if (_didError != null || _planError != null || _moodError != null) return;

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await _repository.updateStandup(
          widget.log!.id,
          did: _did.text.trim(),
          plan: _plan.text.trim(),
          blockers: _blockers.text.trim(),
          mood: _mood!,
        );
      } else {
        await _repository.createStandup(
          date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          did: _did.text.trim(),
          plan: _plan.text.trim(),
          blockers: _blockers.text.trim(),
          mood: _mood!,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      widget.onSuccess();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Standup updated' : 'Standup posted'), backgroundColor: AppColors.success),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _serverError = apiErrorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _isEdit ? formatDate(widget.log!.date) : 'Today · ${formatDate(DateTime.now(), withYear: false)}';
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(_isEdit ? 'Edit standup' : 'Post standup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(dateLabel, style: AppTypography.caption),
            const SizedBox(height: 14),
            Text('How was your day?', style: AppTypography.bodyStrong),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in standupMoodOptions)
                  ChoiceChip(
                    label: Text('${m.emoji} ${m.label}'),
                    selected: _mood == m.value,
                    onSelected: _saving ? null : (_) => setState(() => _mood = m.value),
                  ),
              ],
            ),
            if (_moodError != null) ...[
              const SizedBox(height: 6),
              Text(_moodError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
            ],
            const SizedBox(height: 16),
            CustomTextField(
              label: 'What did you work on?',
              controller: _did,
              maxLines: 3,
              maxLength: 1000,
              errorText: _didError,
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              label: 'What will you work on next?',
              controller: _plan,
              maxLines: 3,
              maxLength: 1000,
              errorText: _planError,
              enabled: !_saving,
            ),
            const SizedBox(height: 12),
            CustomTextField(
              label: 'Anything blocking you? (optional)',
              controller: _blockers,
              maxLines: 2,
              maxLength: 1000,
              enabled: !_saving,
            ),
            if (_serverError != null) ...[
              const SizedBox(height: 8),
              Text(_serverError!, style: AppTypography.caption.copyWith(color: AppColors.dangerInk)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? 'Save' : 'Post'),
        ),
      ],
    );
  }
}
