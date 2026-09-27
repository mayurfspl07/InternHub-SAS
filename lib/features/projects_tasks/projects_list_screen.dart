import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/widgets/reference_components.dart';
import '../../shared/widgets/page_header.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/widgets/load_error_view.dart';
import 'project_form_dialog.dart';

class ProjectsListScreen extends ConsumerStatefulWidget {
  const ProjectsListScreen({super.key});

  @override
  ConsumerState<ProjectsListScreen> createState() => _ProjectsListScreenState();
}

class _ProjectsListScreenState extends ConsumerState<ProjectsListScreen> {
  // Search & Filter State
  final TextEditingController _searchController = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedMentorId; // null or 'all' means all mentors
  String _segmentedTab = 'ongoing'; // Screen 3: 'ongoing', 'completed', 'all'
  List<Map<String, dynamic>> _mentorOptions = [];

  // Pagination & Data State
  List<ProjectModel> _projects = [];
  bool _isLoading = true;
  String? _loadError;
  int _currentPage = 1;
  final int _pageSize = 12;
  int _totalProjects = 0;
  int _totalPages = 1;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchMentorsList();
    _loadProjects();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMentorsList() async {
    try {
      final res = await ApiClient().get('/api/users/mentors');
      final mentors = res is Map && res['mentors'] is List
          ? (res['mentors'] as List).whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      if (mounted) setState(() => _mentorOptions = mentors);
    } catch (_) {
      // The mentor filter is optional; the project list still loads without it.
      if (mounted) setState(() => _mentorOptions = []);
    }
  }

  Future<void> _loadProjects({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    final query = _searchController.text.trim();

    try {
      dynamic res;
      if (query.isNotEmpty) {
        // Search mode: GET /api/projects/search?q={q}&limit=50
        res = await ApiClient().get('/api/projects/search', queryParameters: {
          'q': query,
          'limit': 50,
        });
      } else {
        // List mode: GET /api/projects?page={page}&page_size=12&from_date=...&to_date=...&mentor_id=...
        final params = <String, dynamic>{
          'page': page,
          'page_size': _pageSize,
        };
        if (_fromDate != null) {
          params['from_date'] = DateFormat('yyyy-MM-dd').format(_fromDate!);
        }
        if (_toDate != null) {
          params['to_date'] = DateFormat('yyyy-MM-dd').format(_toDate!);
        }
        if (_selectedMentorId != null && _selectedMentorId != 'all') {
          params['mentor_id'] = _selectedMentorId;
        }

        res = await ApiClient().get('/api/projects', queryParameters: params);
      }

      List<ProjectModel> list = [];
      int total = 0;
      int pages = 1;

      List rawList = [];
      if (res is List) {
        rawList = res;
        total = res.length;
        pages = 1;
      } else if (res is Map<String, dynamic>) {
        final rawItems = res['projects'] ?? res['items'] ?? res['results'] ?? res['data'];
        if (rawItems is List) {
          rawList = rawItems;
        }
        total = (res['total'] as num?)?.toInt() ?? rawList.length;
        pages = (res['total_pages'] as num?)?.toInt() ?? (total > 0 ? (total / _pageSize).ceil() : 1);
      }

      for (final item in rawList) {
        try {
          if (item is Map<String, dynamic>) {
            list.add(ProjectModel.fromJson(item));
          } else if (item is Map) {
            list.add(ProjectModel.fromJson(Map<String, dynamic>.from(item)));
          }
        } catch (e) {
          debugPrint('Error parsing project: $e');
        }
      }

      if (mounted) {
        setState(() {
          _projects = list;
          _totalProjects = total;
          _totalPages = pages > 0 ? pages : 1;
          _currentPage = page;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = apiErrorMessage(e);
        });
      }
    }
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _loadProjects(page: 1);
    });
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _fromDate = null;
      _toDate = null;
      _selectedMentorId = null;
    });
    _loadProjects(page: 1);
  }

  Future<void> _selectDate(BuildContext context, bool isFrom) async {
    final initial = isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? _fromDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_toDate != null && _toDate!.isBefore(picked)) {
            _toDate = picked;
          }
        } else {
          _toDate = picked;
        }
      });
      _loadProjects(page: 1);
    }
  }

  void _openCreateProjectModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProjectFormDialog(
        onSuccess: () {
          _loadProjects(page: 1);
        },
      ),
    );
  }

  Future<void> _exportProject(ProjectModel project) async {
    try {
      await FileExportService.downloadAndShare(
        endpoint: '/api/projects/${project.id}/export',
        defaultFileName: '${project.title.replaceAll(' ', '_')}_export.xlsx',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to export project. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    final user = state.currentUser;
    final isAdmin = user.role == UserRole.admin || user.role == UserRole.superadmin;
    final canCreateProject = user.role == UserRole.admin || user.role == UserRole.mentor || user.role == UserRole.superadmin;

    final isSearching = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            PageHeader(
              title: 'Projects',
              subtitle: 'Across mentors and intern cohorts',
              padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 12, AppSpacing.p20, 8),
              actions: [
                if (canCreateProject)
                  CircularIconButton(
                    icon: Icons.add_rounded,
                    backgroundColor: AppColors.primary,
                    iconColor: AppColors.onPrimary,
                    onTap: _openCreateProjectModal,
                  ),
              ],
            ),

            // Filter Bar Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.p16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.r24),
                  boxShadow: AppShadows.soft,
                ),
                child: Column(
                  children: [
                    // Search text field
                    SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: TextStyle(fontSize: 13, color: AppColors.ink),
                        decoration: InputDecoration(
                          hintText: 'Search projects by name or description...',
                          hintStyle: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: AppColors.textTertiary),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    _loadProjects(page: 1);
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppColors.surfaceMuted,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.r16),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.r16),
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.r16),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Filter row: From, To, Mentor, Reset
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // From Date
                          _buildFilterButton(
                            label: _fromDate != null ? DateFormat('dd/MM/yyyy').format(_fromDate!) : 'From',
                            icon: Icons.calendar_today_outlined,
                            onTap: () => _selectDate(context, true),
                          ),
                          const SizedBox(width: 8),

                          // To Date
                          _buildFilterButton(
                            label: _toDate != null ? DateFormat('dd/MM/yyyy').format(_toDate!) : 'To',
                            icon: Icons.calendar_today_outlined,
                            onTap: () => _selectDate(context, false),
                          ),
                          const SizedBox(width: 8),

                          // Admin Mentor Filter
                          if (isAdmin) ...[
                            Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(AppSpacing.r12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textSecondary),
                                  const SizedBox(width: 6),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedMentorId ?? 'all',
                                      isDense: true,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink,
                                      ),
                                      dropdownColor: Colors.white,
                                      items: [
                                        const DropdownMenuItem(value: 'all', child: Text('All mentors')),
                                        ..._mentorOptions.map((m) {
                                          return DropdownMenuItem(
                                            value: m['id']?.toString() ?? '',
                                            child: Text(m['name']?.toString() ?? 'Mentor'),
                                          );
                                        }),
                                      ],
                                      onChanged: (val) {
                                        setState(() => _selectedMentorId = val);
                                        _loadProjects(page: 1);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],

                          // Reset button
                          TextButton(
                            onPressed: _resetFilters,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: AppColors.textSecondary,
                            ),
                            child: const Text('Reset', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Segmented Pill Filter (Screen 3: Ongoing / Completed)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 8),
              child: Row(
                children: [
                  _buildSegmentedTab('Ongoing', 'ongoing'),
                  const SizedBox(width: 10),
                  _buildSegmentedTab('Completed', 'completed'),
                  const SizedBox(width: 10),
                  _buildSegmentedTab('All', 'all'),
                ],
              ),
            ),


            // Projects List or Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                  ? LoadErrorView(
                      title: 'Couldn\'t load projects',
                      message: _loadError!,
                      onRetry: () => _loadProjects(page: _currentPage),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _loadProjects(page: _currentPage),
                      child: _displayedProjects.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 64,
                                        height: 64,
                                        decoration: BoxDecoration(
                                          color: AppColors.primarySoft,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.folder_open_rounded, size: 32, color: AppColors.primaryInk),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'No projects found',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        isSearching ? 'Try changing your search keywords.' : 'Create a new project to get started.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 12),
                              itemCount: _displayedProjects.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final project = _displayedProjects[index];
                                return _buildProjectCard(project);
                              },
                            ),
                    ),
            ),

            // Bottom Pagination Bar (when NOT searching)
            if (!isSearching && _totalProjects > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: AppColors.border),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Page $_currentPage of $_totalPages ($_totalProjects ${_totalProjects == 1 ? 'project' : 'projects'})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _currentPage > 1 ? () => _loadProjects(page: _currentPage - 1) : null,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: AppColors.ink,
                            side: BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r12)),
                          ),
                          child: const Text('‹ Prev', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppSpacing.r8),
                          ),
                          child: Text(
                            '$_currentPage',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _currentPage < _totalPages ? () => _loadProjects(page: _currentPage + 1) : null,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: AppColors.ink,
                            side: BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r12)),
                          ),
                          child: const Text('Next ›', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<ProjectModel> get _displayedProjects {
    if (_segmentedTab == 'ongoing') {
      return _projects.where((p) => p.status.toLowerCase() != 'completed' && p.status.toLowerCase() != 'done').toList();
    } else if (_segmentedTab == 'completed') {
      return _projects.where((p) => p.status.toLowerCase() == 'completed' || p.status.toLowerCase() == 'done').toList();
    }
    return _projects;
  }

  Widget _buildSegmentedTab(String label, String key) {
    final isSelected = _segmentedTab == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          _segmentedTab = key;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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

  Widget _buildFilterButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.r12),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(width: 6),
            Icon(icon, size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  // Modern Clean Project Card matching application theme
  Widget _buildProjectCard(ProjectModel project) {
    final progressInt = (project.progress * 100).round().clamp(0, 100);

    // Status pill coloring:
    Color statusBg;
    Color statusTextColor;
    final statusLower = project.status.toLowerCase();
    if (statusLower == 'completed' || statusLower == 'done') {
      statusBg = AppColors.successSoft;
      statusTextColor = AppColors.successInk;
    } else if (statusLower == 'in_progress' || statusLower == 'active') {
      statusBg = AppColors.infoSoft;
      statusTextColor = AppColors.info;
    } else if (statusLower == 'planning') {
      statusBg = AppColors.primarySoft;
      statusTextColor = AppColors.primaryInk;
    } else {
      statusBg = AppColors.warningSoft;
      statusTextColor = AppColors.warning;
    }

    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/projects/${project.id}',
          arguments: project,
        ).then((_) => _loadProjects(page: _currentPage));
      },
      borderRadius: BorderRadius.circular(AppSpacing.r24),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.p20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.r24),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Status pill & Export / Bookmark icons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(AppSpacing.rPill),
                  ),
                  child: Text(
                    project.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusTextColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.file_download_outlined, size: 20, color: AppColors.textSecondary),
                      tooltip: 'Export project',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _exportProject(project),
                    ),
                    Icon(Icons.bookmark_outline_rounded, size: 20, color: AppColors.textTertiary),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              project.name.isNotEmpty ? project.name : project.title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),

            // Description
            if (project.description.isNotEmpty)
              Text(
                project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 16),

            // Progress Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '$progressInt%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.r8),
              child: LinearProgressIndicator(
                value: project.progress.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: AppColors.surfaceMuted,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 18),

            // Bottom Row: Avatars, Due date, "View" CTA Button
            Row(
              children: [
                // Member avatars
                _buildAvatarStack(project.memberNames, project.memberAvatars),
                const SizedBox(width: 12),

                // Calendar date
                Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textTertiary),
                const SizedBox(width: 5),
                Text(
                  DateFormat('yyyy-MM-dd').format(project.endDate),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),

                // View CTA Button
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      '/projects/${project.id}',
                      arguments: project,
                    ).then((_) => _loadProjects(page: _currentPage));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                    shadowColor: AppColors.primary.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.r16)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarStack(List<String> names, List<String> avatars) {
    final count = names.length > 3 ? 3 : names.length;
    if (count == 0) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: AppColors.primarySoft,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('P', style: TextStyle(color: AppColors.primaryInk, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      );
    }

    final colors = [
      AppColors.primary,
      AppColors.info,
      AppColors.info,
    ];

    return SizedBox(
      height: 28,
      width: (count * 18.0) + 12,
      child: Stack(
        children: List.generate(count, (i) {
          final name = names[i];
          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
          return Positioned(
            left: i * 18.0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors[i % colors.length],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
