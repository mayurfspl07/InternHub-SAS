import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/reference_components.dart';
import 'activity_repository.dart';
import 'models/activity_models.dart';

class ActivityTimelineScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  const ActivityTimelineScreen({super.key, this.showBackButton = true});

  @override
  ConsumerState<ActivityTimelineScreen> createState() => _ActivityTimelineScreenState();
}

class _ActivityTimelineScreenState extends ConsumerState<ActivityTimelineScreen> {
  final ActivityRepository _repository = ActivityRepository();

  final TextEditingController _actorSearchController = TextEditingController();
  Timer? _debounceTimer;

  String _debouncedActorFilter = '';
  String _selectedCategory = 'all'; // all, attendance, leave, project, task, user, standup, review, announcement
  String? _selectedDate; // YYYY-MM-DD
  int _currentPage = 1;

  bool _isLoading = true;
  String? _errorMessage;

  List<AuditLogEntry> _displayedLogs = [];
  int _totalPages = 1;
  int _auditPageSize = 30;

  Widget _buildSegmentedTab(String label, String value) {
    final isSelected = _selectedCategory == value;
    return GestureDetector(
      onTap: () {
        if (_selectedCategory != value) {
          _onCategoryChanged(value);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  @override
  void initState() {
    super.initState();
    _fetchTimelineData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _actorSearchController.dispose();
    super.dispose();
  }

  void _onActorSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _debouncedActorFilter = value.trim();
          _currentPage = 1;
        });
        _fetchTimelineData();
      }
    });
  }

  void _onCategoryChanged(String? newCategory) {
    if (newCategory == null || newCategory == _selectedCategory) return;
    setState(() {
      _selectedCategory = newCategory;
      _currentPage = 1;
    });
    _fetchTimelineData();
  }

  Future<void> _pickDate() async {
    final initialDate = _selectedDate != null ? (DateTime.tryParse(_selectedDate!) ?? DateTime.now()) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );

    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {
        _selectedDate = formatted;
        _currentPage = 1;
      });
      _fetchTimelineData();
    }
  }

  void _clearDate() {
    setState(() {
      _selectedDate = null;
      _currentPage = 1;
    });
    _fetchTimelineData();
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages || page == _currentPage) return;
    setState(() => _currentPage = page);
    _fetchTimelineData();
  }

  Future<void> _fetchTimelineData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_selectedCategory == 'announcement') {
        // Announcement-only mode
        final annResult = await _repository.fetchAnnouncementsPage(
          page: _currentPage,
          pageSize: 20,
        );

        final entries = mergeAuditLogsWithAnnouncements(
          auditLogs: [],
          announcements: annResult.items,
          category: 'announcement',
          dateFilter: _selectedDate,
        );

        // Client fallback actor filter
        final filtered = _debouncedActorFilter.isNotEmpty
            ? entries.where((e) => e.actorName.toLowerCase().contains(_debouncedActorFilter.toLowerCase())).toList()
            : entries;

        if (mounted) {
          setState(() {
            _displayedLogs = filtered;
            _totalPages = annResult.totalPages;
            _auditPageSize = 20;
            _isLoading = false;
          });
        }
      } else if (_selectedCategory == 'all') {
        // Dual query: audit logs for current page + announcements page 1
        final auditFuture = _repository.fetchAudit(
          page: _currentPage,
          action: null,
          date: _selectedDate,
          actor: _debouncedActorFilter,
        );
        final annFuture = _repository.fetchAnnouncementsPage(
          page: 1,
          pageSize: 20,
        );

        final results = await Future.wait([auditFuture, annFuture]);
        final auditResult = results[0] as AuditLogList;
        final annResult = results[1] as AnnouncementsPageResult;

        final merged = mergeAuditLogsWithAnnouncements(
          auditLogs: auditResult.logs,
          announcements: annResult.items,
          category: 'all',
          dateFilter: _selectedDate,
        );

        // Client fallback actor filter
        final filtered = _debouncedActorFilter.isNotEmpty
            ? merged.where((e) => e.actorName.toLowerCase().contains(_debouncedActorFilter.toLowerCase())).toList()
            : merged;

        if (mounted) {
          setState(() {
            _displayedLogs = filtered;
            _totalPages = auditResult.totalPages;
            _auditPageSize = auditResult.pageSize;
            _isLoading = false;
          });
        }
      } else {
        // Specific category (attendance, leave, project, task, user, standup, review)
        final auditResult = await _repository.fetchAudit(
          page: _currentPage,
          action: _selectedCategory,
          date: _selectedDate,
          actor: _debouncedActorFilter,
        );

        final entries = mergeAuditLogsWithAnnouncements(
          auditLogs: auditResult.logs,
          announcements: [],
          category: _selectedCategory,
          dateFilter: _selectedDate,
        );

        // Client fallback actor filter
        final filtered = _debouncedActorFilter.isNotEmpty
            ? entries.where((e) => e.actorName.toLowerCase().contains(_debouncedActorFilter.toLowerCase())).toList()
            : entries;

        if (mounted) {
          setState(() {
            _displayedLogs = filtered;
            _totalPages = auditResult.totalPages;
            _auditPageSize = auditResult.pageSize;
            _isLoading = false;
          });
        }
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;

    // Page access gate: interns redirect to dashboard
    if (user.role == UserRole.intern) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final bgColor = AppColors.canvas;
    final cardBg = AppColors.surface;
    final borderColor = AppColors.border;
    final primaryTextColor = AppColors.ink;
    final secondaryTextColor = AppColors.textSecondary;

    final serialOffset = _selectedCategory == 'announcement'
        ? (_currentPage - 1) * 20
        : (_currentPage - 1) * _auditPageSize;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchTimelineData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Back Button & Title & Share Action matching Screen 3 "Interaction History"
                      PageHeader(
                        title: 'Activity',
                        showBack: widget.showBackButton && Navigator.canPop(context),
                        padding: EdgeInsets.zero,
                        actions: [
                          HeaderAction(icon: Icons.open_in_new_rounded, onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Interaction history exported successfully'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Segmented Tab Row: [All] [Interns] [Projects] [Reviews]
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
                                _buildSegmentedTab('All', 'all'),
                                _buildSegmentedTab('Interns', 'user'),
                                _buildSegmentedTab('Projects', 'project'),
                                _buildSegmentedTab('Reviews', 'review'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Search bar with date filter action
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _actorSearchController,
                              onChanged: _onActorSearchChanged,
                              style: TextStyle(color: primaryTextColor, fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Search activity...',
                                hintStyle: TextStyle(color: secondaryTextColor, fontSize: 13),
                                prefixIcon: Icon(Icons.search_rounded, size: 20, color: secondaryTextColor),
                                suffixIcon: _actorSearchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear_rounded, size: 18, color: secondaryTextColor),
                                        onPressed: () {
                                          _actorSearchController.clear();
                                          _onActorSearchChanged('');
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
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: _pickDate,
                            borderRadius: BorderRadius.circular(AppSpacing.rPill),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cardBg,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _selectedDate != null ? AppColors.primary : borderColor,
                                ),
                              ),
                              child: Icon(
                                Icons.calendar_today_rounded,
                                size: 18,
                                color: _selectedDate != null ? AppColors.primaryInk : secondaryTextColor,
                              ),
                            ),
                          ),
                          if (_selectedDate != null) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: _clearDate,
                              borderRadius: BorderRadius.circular(AppSpacing.rPill),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  shape: BoxShape.circle,
        boxShadow: AppShadows.soft,
      ),
                                child: Icon(Icons.clear_rounded, size: 18, color: secondaryTextColor),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Timeline Content or States
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
                            onPressed: _fetchTimelineData,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (_displayedLogs.isEmpty)
                // Dashed Card Empty State matching web screenshot
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                    child: _buildDashedEmptyCard(
                      borderColor: borderColor,
                      secondaryTextColor: secondaryTextColor,
                    ),
                  ),
                )
              else
                // Timeline List
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final log = _displayedLogs[index];
                        final serialNumber = serialOffset + index + 1;
                        final isLast = index == _displayedLogs.length - 1;

                        return _buildTimelineItem(
                          log: log,
                          serialNumber: serialNumber,
                          isLast: isLast,
                          cardBg: cardBg,
                          borderColor: borderColor,
                          primaryTextColor: primaryTextColor,
                          secondaryTextColor: secondaryTextColor,
                        );
                      },
                      childCount: _displayedLogs.length,
                    ),
                  ),
                ),

              // Pagination Footer
              if (_totalPages > 1 && !_isLoading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 24, AppSpacing.p20, 40),
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
                            'Page $_currentPage of $_totalPages',
                            style: TextStyle(
                              fontSize: 13,
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
          ),
        ),
      ),
    );
  }

  Widget _buildDashedEmptyCard({
    required Color borderColor,
    required Color secondaryTextColor,
  }) {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignCenter,
        ),
      ),
      child: Center(
        child: Text(
          'No activity logs matching the selected filters.',
          style: TextStyle(
            fontSize: 14,
            color: secondaryTextColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineItem({
    required AuditLogEntry log,
    required int serialNumber,
    required bool isLast,
    required Color cardBg,
    required Color borderColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    final themeList = [
      HistoryCardTheme.amber,
      HistoryCardTheme.peach,
      HistoryCardTheme.lavender,
      HistoryCardTheme.sage,
    ];
    final selectedTheme = themeList[serialNumber % themeList.length];

    final dt = DateTime.tryParse(log.createdAt) ?? DateTime.now();
    final dateStr = DateFormat('MMM d').format(dt);

    // Format readable title
    String title = '${log.actorName} ${log.verb}';
    if (log.target.isNotEmpty) {
      title = '${log.actorName} ${log.verb} ${log.target}';
    }

    final timeStr = DateFormat('h:mm a').format(dt);

    return InteractionHistoryCard(
      dateText: dateStr,
      title: title,
      metricValue: timeStr,
      cardTheme: selectedTheme,
      onTap: () {
        // Show detail diff modal
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (ctx) => Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Event Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Logged at: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(dt)}',
                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
