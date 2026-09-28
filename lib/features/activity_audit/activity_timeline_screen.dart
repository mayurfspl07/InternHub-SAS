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
import '../../core/constants/app_typography.dart';
import '../../shared/widgets/load_error_view.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/pagination_bar.dart';
import '../dashboard/widgets/dashboard_shared.dart';

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

  /// Filter label and the audit `action` category (null = everything).
  static const _categories = <(String, String)>[
    ('All', 'all'),
    ('Attendance', 'attendance'),
    ('Leave', 'leave'),
    ('Projects', 'project'),
    ('Tasks', 'task'),
    ('Users', 'user'),
    ('Standups', 'standup'),
    ('Reviews', 'review'),
    ('Announcements', 'announcement'),
  ];

  void _selectCategory(String value) {
    if (value == _selectedCategory) return;
    setState(() {
      _selectedCategory = value;
      _currentPage = 1;
    });
    _fetchTimelineData();
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

  Future<void> _pickDate() async {
    final initialDate = _selectedDate != null ? (DateTime.tryParse(_selectedDate!) ?? DateTime.now()) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
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
            _isLoading = false;
          });
        }
      } else if (_selectedCategory == 'all') {
        // Audit logs for this page; recent announcements are mixed in on page 1 only,
        // so later pages don't repeat them.
        final auditResult = await _repository.fetchAudit(
          page: _currentPage,
          action: null,
          date: _selectedDate,
          actor: _debouncedActorFilter,
        );
        final announcements = _currentPage == 1
            ? (await _repository.fetchAnnouncementsPage(page: 1, pageSize: 20)).items
            : const <Never>[];

        final merged = mergeAuditLogsWithAnnouncements(
          auditLogs: auditResult.logs,
          announcements: announcements,
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
            _isLoading = false;
          });
        }
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
    final secondaryTextColor = AppColors.textSecondary;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchTimelineData,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PageHeader(
                              title: 'Activity',
                              subtitle: 'What changed, who did it and when',
                              showBack: widget.showBackButton && Navigator.canPop(context),
                              padding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _actorSearchController,
                                    onChanged: _onActorSearchChanged,
                                    textInputAction: TextInputAction.search,
                                    decoration: InputDecoration(
                                      hintText: 'Search by person',
                                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                                      suffixIcon: _actorSearchController.text.isNotEmpty
                                          ? IconButton(
                                              tooltip: 'Clear search',
                                              icon: const Icon(Icons.clear_rounded, size: 18),
                                              onPressed: () {
                                                _actorSearchController.clear();
                                                _onActorSearchChanged('');
                                              },
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.outlined(
                                  tooltip: _selectedDate == null ? 'Pick a date' : 'Change date',
                                  onPressed: _pickDate,
                                  icon: Icon(
                                    Icons.calendar_today_rounded,
                                    size: 18,
                                    color: _selectedDate != null ? AppColors.primaryInk : secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                            if (_selectedDate != null) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: InputChip(
                                  label: Text(formatDate(_selectedDate)),
                                  deleteButtonTooltipMessage: 'Show all dates',
                                  onDeleted: _clearDate,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            PillFilter(
                              options: [for (final c in _categories) c.$1],
                              selectedIndex: _categories.indexWhere((c) => c.$2 == _selectedCategory),
                              onSelected: (i) => _selectCategory(_categories[i].$2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isLoading && _displayedLogs.isEmpty)
                      const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                    else if (_errorMessage != null && _displayedLogs.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: LoadErrorView(title: "Couldn't load activity", message: _errorMessage!, onRetry: _fetchTimelineData),
                      )
                    else if (_displayedLogs.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 40),
                          child: Column(
                            children: [
                              const Icon(Icons.history_rounded, size: 48, color: AppColors.textTertiary),
                              const SizedBox(height: 12),
                              Text('Nothing here', style: AppTypography.section.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('No activity matches these filters.', style: AppTypography.caption, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      if (_isLoading) const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 4, AppSpacing.p20, 24),
                        sliver: SliverList.separated(
                          itemCount: _displayedLogs.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) => _buildTimelineItem(_displayedLogs[index]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            PaginationBar(
              page: _currentPage,
              totalPages: _totalPages,
              itemLabel: 'events',
              isLoading: _isLoading,
              onPageChanged: _goToPage,
            ),
          ],
        ),
      ),
    );
  }

  String _sentence(AuditLogEntry log) =>
      log.target.isNotEmpty ? '${log.actorName} ${log.verb} ${log.target}' : '${log.actorName} ${log.verb}';

  Widget _buildTimelineItem(AuditLogEntry log) {
    final dt = DateTime.tryParse(log.createdAt);
    final when = dt == null ? 'Unknown time' : formatRelative(dt);
    final text = _sentence(log);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: AppTypography.cardTitle.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(dt == null ? 'Unknown time' : formatDateTime(dt), style: AppTypography.caption),
                  const SizedBox(height: 4),
                  Text('Type: ${humanize(log.action.split('.').first)}', style: AppTypography.caption),
                ],
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
                child: Icon(getActivityIcon(log.action), size: 18, color: AppColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.body.copyWith(color: AppColors.ink)),
                    const SizedBox(height: 2),
                    Text(when, style: AppTypography.label),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
