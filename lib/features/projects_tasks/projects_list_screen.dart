import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
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
      backgroundColor: isDark ? const Color(0xFF101216) : const Color(0xFFF9FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Top App Bar / Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                            color: isDark ? Colors.white : const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'All projects across mentors and intern cohorts.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canCreateProject)
                    ElevatedButton.icon(
                      onPressed: _openCreateProjectModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFBBF24), // Amber color matching screenshot
                        foregroundColor: const Color(0xFF1F2937),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFD97706), width: 1.2),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18, color: Color(0xFF1F2937)),
                      label: const Text(
                        'New Project',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),

            // Filter Bar Card matching Screenshot 1
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1D24) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color(0xFF2C313E) : const Color(0xFFE5E7EB),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
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
                          hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : const Color(0xFF9CA3AF)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF9CA3AF)),
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
                          fillColor: isDark ? const Color(0xFF121418) : const Color(0xFFF9FAFB),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: isDark ? const Color(0xFF323846) : const Color(0xFFE5E7EB)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: isDark ? const Color(0xFF323846) : const Color(0xFFE5E7EB)),
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
                                color: isDark ? const Color(0xFF121418) : const Color(0xFFF9FAFB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isDark ? const Color(0xFF323846) : const Color(0xFFE5E7EB)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF6B7280)),
                                  const SizedBox(width: 6),
                                  DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedMentorId ?? 'all',
                                      isDense: true,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white70 : const Color(0xFF374151),
                                      ),
                                      dropdownColor: isDark ? const Color(0xFF1A1D24) : Colors.white,
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
                              foregroundColor: isDark ? Colors.white60 : const Color(0xFF4B5563),
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
                                          color: isDark ? const Color(0xFF1E232D) : const Color(0xFFFEF3C7),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.folder_open_rounded, size: 32, color: Color(0xFFD97706)),
                                      ),
                                      const SizedBox(height: 14),
                                      Text(
                                        'No projects found',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : const Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        isSearching ? 'Try changing your search keywords.' : 'Create a new project to get started.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? Colors.white60 : const Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF16181F) : Colors.white,
                  border: Border(
                    top: BorderSide(color: isDark ? const Color(0xFF242936) : const Color(0xFFE5E7EB)),
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
                        color: isDark ? Colors.white60 : const Color(0xFF4B5563),
                      ),
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: _currentPage > 1 ? () => _loadProjects(page: _currentPage - 1) : null,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('< Previous', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBBF24),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD97706)),
                          ),
                          child: Text(
                            '$_currentPage',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _currentPage < _totalPages ? () => _loadProjects(page: _currentPage + 1) : null,
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Next >', style: TextStyle(fontSize: 12)),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF121418) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF323846) : const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : const Color(0xFF374151),
              ),
            ),
            const SizedBox(width: 6),
            Icon(icon, size: 14, color: const Color(0xFF6B7280)),
          ],
        ),
      ),
    );
  }

  // Card matching screenshot 1 (Yellowish/Amber background card with dark rounded border)
  Widget _buildProjectCard(ProjectModel project, bool isDark) {
    final progressInt = (project.progress * 100).round().clamp(0, 100);

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)),
        ).then((_) => _loadProjects(page: _currentPage));
      },
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFCE38A), // Warm light yellow from screenshot
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF1F2937), width: 1.8), // Dark outline
          boxShadow: const [
            BoxShadow(
              color: Color(0x15000000),
              blurRadius: 8,
              offset: Offset(0, 4),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    project.status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.file_download_outlined, size: 20, color: Color(0xFF1F2937)),
                      tooltip: 'Export project',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _exportProject(project),
                    ),
                    const Icon(Icons.bookmark_rounded, size: 20, color: Color(0xFF1F2937)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(
              project.name.isNotEmpty ? project.name : project.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                fontFamily: 'Outfit',
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 4),

            // Description
            if (project.description.isNotEmpty)
              Text(
                project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF4B5563),
                  height: 1.3,
                ),
              ),
            const SizedBox(height: 16),

            // Progress Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Progress',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  '$progressInt%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: project.progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0x331F2937),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF97316)), // Orange accent
              ),
            ),
            const SizedBox(height: 18),

            // Bottom Row: Avatars, Due date, "Continue" Button
            Row(
              children: [
                // Member avatars
                _buildAvatarStack(project.memberNames, project.memberAvatars),
                const SizedBox(width: 10),

                // Calendar date
                const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF4B5563)),
                const SizedBox(width: 4),
                Text(
                  DateFormat('yyyy-MM-dd').format(project.endDate),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const Spacer(),

                // Continue Red/Orange Button matching Screenshot 1
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)),
                    ).then((_) => _loadProjects(page: _currentPage));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444), // Vibrant Red/Coral button
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
          color: Color(0xFF3B82F6),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('P', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      );
    }

    final colors = [const Color(0xFF3B82F6), const Color(0xFFF97316), const Color(0xFF10B981)];

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
