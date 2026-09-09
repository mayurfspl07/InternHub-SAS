import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/services/file_export_service.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/models/user_model.dart';
import 'project_detail_screen.dart';
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
  List<Map<String, dynamic>> _mentorOptions = [];

  // Pagination & Data State
  List<ProjectModel> _projects = [];
  bool _isLoading = true;
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
      dynamic res;
      try {
        res = await ApiClient().get('/api/users/dropdown', queryParameters: {'role': 'mentor'});
      } catch (_) {
        res = await ApiClient().get('/api/projects/mentors', queryParameters: {'page': 1, 'page_size': 30}).catchError((_) => []);
      }
      List<Map<String, dynamic>> mentors = [];
      if (res is List) {
        mentors = res.whereType<Map<String, dynamic>>().where((m) => m['is_active'] != false).toList();
      } else if (res is Map<String, dynamic>) {
        final items = res['users'] ?? res['mentors'] ?? res['items'] ?? res['results'] ?? res['data'];
        if (items is List) {
          mentors = items.whereType<Map<String, dynamic>>().where((m) => m['is_active'] != false).toList();
        }
      }
      if (mentors.isEmpty) {
        final all = ref.read(appStateProvider).allUsers;
        mentors = all
            .where((u) => u.role == UserRole.mentor)
            .map((u) => {'id': u.id, 'name': u.name, 'email': u.email, 'role': 'mentor'})
            .toList();
      }
      if (mounted) {
        setState(() {
          _mentorOptions = mentors;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProjects({int page = 1}) async {
    setState(() => _isLoading = true);
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

        try {
          res = await ApiClient().get('/api/projects', queryParameters: params);
        } catch (e) {
          if (query.isNotEmpty || _fromDate != null || _toDate != null || (_selectedMentorId != null && _selectedMentorId != 'all')) {
            rethrow;
          }
          res = await ApiClient().get('/api/projects');
        }
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

      if (list.isEmpty && query.isEmpty && _fromDate == null && _toDate == null && (_selectedMentorId == null || _selectedMentorId == 'all')) {
        final cached = ref.read(appStateProvider).projects;
        if (cached.isNotEmpty) {
          list = cached;
          total = cached.length;
          pages = 1;
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
      final cached = ref.read(appStateProvider).projects;
      if (mounted) {
        setState(() {
          if (cached.isNotEmpty && _projects.isEmpty) {
            _projects = cached;
            _totalProjects = cached.length;
            _totalPages = 1;
          }
          _isLoading = false;
        });
        if (cached.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load projects: ${e is ApiException ? e.message : e}')),
          );
        }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdmin = user.role == UserRole.admin || user.role == UserRole.superadmin;
    final canCreateProject = user.role == UserRole.admin || user.role == UserRole.mentor || user.role == UserRole.superadmin;

    final isSearching = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar / Title
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.p20, 16, AppSpacing.p20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Projects',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Outfit',
                            letterSpacing: -0.5,
                            color: isDark ? Colors.white : AppColors.textPrimaryLight,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'All projects across mentors and intern cohorts.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canCreateProject)
                    ElevatedButton.icon(
                      onPressed: _openCreateProjectModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppSpacing.r16),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text(
                        'New Project',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),

            // Filter Bar Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.p16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.r24),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Search text field
                    SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: 'Search projects by name or description...',
                          hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : AppColors.textTertiaryLight),
                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: isDark ? Colors.white38 : AppColors.textTertiaryLight),
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
                          fillColor: isDark ? AppColors.surfaceDark : const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.r16),
                            borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppSpacing.r16),
                            borderSide: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
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
                            label: _fromDate != null ? DateFormat('dd/MM/yyyy').format(_fromDate!) : 'From: dd/mm/yyyy',
                            icon: Icons.calendar_today_outlined,
                            isDark: isDark,
                            onTap: () => _selectDate(context, true),
                          ),
                          const SizedBox(width: 8),

                          // To Date
                          _buildFilterButton(
                            label: _toDate != null ? DateFormat('dd/MM/yyyy').format(_toDate!) : 'To: dd/mm/yyyy',
                            icon: Icons.calendar_today_outlined,
                            isDark: isDark,
                            onTap: () => _selectDate(context, false),
                          ),
                          const SizedBox(width: 8),

                          // Admin Mentor Filter
                          if (isAdmin) ...[
                            Container(
                              height: 36,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(AppSpacing.r12),
                                border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_outline_rounded, size: 16, color: isDark ? Colors.white60 : AppColors.textSecondaryLight),
                                  const SizedBox(width: 6),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedMentorId ?? 'all',
                                      isDense: true,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
                                      ),
                                      dropdownColor: isDark ? AppColors.cardDark : Colors.white,
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
                              foregroundColor: isDark ? Colors.white60 : AppColors.textSecondaryLight,
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

            // Projects List or Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _loadProjects(page: _currentPage),
                      child: _projects.isEmpty
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
                                          color: isDark ? AppColors.surfaceDark : AppColors.primaryLight,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.folder_open_rounded, size: 32, color: AppColors.primary),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'No projects found',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        isSearching ? 'Try changing your search keywords.' : 'Create a new project to get started.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
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
                              itemCount: _projects.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final project = _projects[index];
                                return _buildProjectCard(project, isDark);
                              },
                            ),
                    ),
            ),

            // Bottom Pagination Bar (when NOT searching)
            if (!isSearching && _totalProjects > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.p20, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.cardDark : Colors.white,
                  border: Border(
                    top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
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
                        color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
                      ),
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _currentPage > 1 ? () => _loadProjects(page: _currentPage - 1) : null,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: isDark ? Colors.white : AppColors.textPrimaryLight,
                            side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
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
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _currentPage < _totalPages ? () => _loadProjects(page: _currentPage + 1) : null,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: isDark ? Colors.white : AppColors.textPrimaryLight,
                            side: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight),
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

  Widget _buildFilterButton({
    required String label,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.r12),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(AppSpacing.r12),
          border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : AppColors.textPrimaryLight,
              ),
            ),
            const SizedBox(width: 6),
            Icon(icon, size: 14, color: isDark ? Colors.white60 : AppColors.textSecondaryLight),
          ],
        ),
      ),
    );
  }

  // Modern Clean Project Card matching application theme
  Widget _buildProjectCard(ProjectModel project, bool isDark) {
    final progressInt = (project.progress * 100).round().clamp(0, 100);

    // Status pill coloring:
    Color statusBg;
    Color statusTextColor;
    final statusLower = project.status.toLowerCase();
    if (statusLower == 'completed' || statusLower == 'done') {
      statusBg = isDark ? AppColors.success.withValues(alpha: 0.2) : const Color(0xFFECFDF5);
      statusTextColor = isDark ? AppColors.success : const Color(0xFF047857);
    } else if (statusLower == 'in_progress' || statusLower == 'active') {
      statusBg = isDark ? AppColors.accent.withValues(alpha: 0.2) : const Color(0xFFE0F2FE);
      statusTextColor = isDark ? AppColors.accent : const Color(0xFF0284C7);
    } else if (statusLower == 'planning') {
      statusBg = isDark ? AppColors.primaryDark.withValues(alpha: 0.3) : AppColors.primaryLight;
      statusTextColor = isDark ? AppColors.primaryLight : AppColors.primaryDark;
    } else {
      statusBg = isDark ? AppColors.warning.withValues(alpha: 0.2) : const Color(0xFFFEF3C7);
      statusTextColor = isDark ? AppColors.warning : const Color(0xFFD97706);
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)),
        ).then((_) => _loadProjects(page: _currentPage));
      },
      borderRadius: BorderRadius.circular(AppSpacing.r24),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.p20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.r24),
          border: Border.all(color: isDark ? AppColors.borderDark : AppColors.borderLight, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
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
                      fontWeight: FontWeight.w800,
                      color: statusTextColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.file_download_outlined, size: 20, color: isDark ? Colors.white70 : AppColors.textSecondaryLight),
                      tooltip: 'Export project',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _exportProject(project),
                    ),
                    Icon(Icons.bookmark_outline_rounded, size: 20, color: isDark ? Colors.white60 : AppColors.textTertiaryLight),
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
                fontWeight: FontWeight.w800,
                fontFamily: 'Outfit',
                letterSpacing: -0.3,
                color: isDark ? Colors.white : AppColors.textPrimaryLight,
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
                  color: isDark ? Colors.white60 : AppColors.textSecondaryLight,
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
                    color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                  ),
                ),
                Text(
                  '$progressInt%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
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
                backgroundColor: isDark ? const Color(0xFF2A2E3B) : const Color(0xFFF1F4F9),
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
                Icon(Icons.calendar_today_rounded, size: 14, color: isDark ? Colors.white60 : AppColors.textTertiaryLight),
                const SizedBox(width: 5),
                Text(
                  DateFormat('yyyy-MM-dd').format(project.endDate),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppColors.textSecondaryLight,
                  ),
                ),
                const Spacer(),

                // View CTA Button
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)),
                    ).then((_) => _loadProjects(page: _currentPage));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
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
          color: AppColors.primaryLight,
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('P', style: TextStyle(color: AppColors.primaryDark, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      );
    }

    final colors = [
      AppColors.primary,
      AppColors.cardPurple,
      AppColors.accent,
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
