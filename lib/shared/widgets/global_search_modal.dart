import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/models/user_model.dart';
import '../../shared/models/project_model.dart';
import 'user_360_profile_dialog.dart';
import 'app_avatar.dart';
import 'load_error_view.dart';
import '../../core/constants/app_typography.dart';
import '../../core/utils/formatters.dart';

class GlobalSearchModal extends StatefulWidget {
  const GlobalSearchModal({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GlobalSearchModal(),
    );
  }

  @override
  State<GlobalSearchModal> createState() => _GlobalSearchModalState();
}

class _GlobalSearchModalState extends State<GlobalSearchModal> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  // The latest query sent; older responses that arrive late are ignored.
  String _activeQuery = '';
  bool _isLoading = false;
  String? _error;

  List<UserModel> _users = [];
  List<ProjectModel> _projects = [];
  List<TaskModel> _tasks = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      _activeQuery = '';
      setState(() {
        _error = null;
        _users = [];
        _projects = [];
        _tasks = [];
        _isLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _executeSearch(query.trim());
    });
  }

  Future<void> _executeSearch(String query) async {
    _activeQuery = query;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // GET /api/search -> {q, results: {users, projects, tasks}, total}
      final res = await ApiClient().get('/api/search', queryParameters: {'q': query});
      final results = res is Map && res['results'] is Map ? res['results'] as Map : const {};
      List<Map<String, dynamic>> listOf(String key) =>
          results[key] is List ? (results[key] as List).whereType<Map<String, dynamic>>().toList() : const [];

      if (mounted && query == _activeQuery) {
        setState(() {
          _users = listOf('users').map(UserModel.fromJson).toList();
          _projects = listOf('projects').map(ProjectModel.fromJson).toList();
          _tasks = listOf('tasks').map(TaskModel.fromJson).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && query == _activeQuery) {
        setState(() {
          _isLoading = false;
          _error = apiErrorMessage(e);
        });
      }
    }
  }

  void _openProject(String id) {
    final projectId = int.tryParse(id);
    if (projectId == null) return;
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pushNamed('/projects/$projectId');
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );

  Widget _emptyState() {
    if (_error != null) {
      return LoadErrorView(
        title: "Search didn't work",
        message: _error!,
        compact: true,
        onRetry: () => _executeSearch(_searchController.text.trim()),
      );
    }
    final text = _searchController.text.isEmpty
        ? 'Search people, projects and tasks'
        : (_isLoading ? 'Searching…' : 'No matches for "${_searchController.text.trim()}"');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, textAlign: TextAlign.center, style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    final media = MediaQuery.of(context);
    // Stay clear of the keyboard: shrink the sheet by the keyboard height.
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
      height: (media.size.height * 0.80 - media.viewInsets.bottom).clamp(240.0, media.size.height),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (q) {
                _debounce?.cancel();
                if (q.trim().isNotEmpty) _executeSearch(q.trim());
              },
              decoration: InputDecoration(
                hintText: 'Search people, projects, tasks',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryInk),
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : (_searchController.text.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null),
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),

          // Search results
          Expanded(
            child: (_users.isEmpty && _projects.isEmpty && _tasks.isEmpty) || _error != null
                ? _emptyState()
                : ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    children: [
                      // Users
                      if (_users.isNotEmpty) ...[
                        _sectionLabel('People (${_users.length})'),
                        ..._users.map((u) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: AppAvatar(url: u.avatarUrl, size: 40, fallbackText: u.name),
                              title: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                              subtitle: Text(
                                [u.roleTitle, if ((u.department ?? '').isNotEmpty) u.department!].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                Navigator.pop(context);
                                User360ProfileDialog.show(context, userId: u.id, fallbackUser: u);
                              },
                            )),
                        const SizedBox(height: 16),
                      ],

                      // Projects
                      if (_projects.isNotEmpty) ...[
                        _sectionLabel('Projects (${_projects.length})'),
                        ..._projects.map((p) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.folder_outlined, color: AppColors.primaryInk),
                              ),
                              title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                              subtitle: Text(humanize(p.status), maxLines: 1),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _openProject(p.id),
                            )),
                        const SizedBox(height: 16),
                      ],

                      // Tasks
                      if (_tasks.isNotEmpty) ...[
                        _sectionLabel('Tasks (${_tasks.length})'),
                        ..._tasks.map((t) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.assignment_outlined, color: AppColors.ink),
                              ),
                              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyStrong),
                              subtitle: Text(
                                [if (t.projectName.isNotEmpty) t.projectName, humanize(t.rawStatus)].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () => _openProject(t.projectId),
                            )),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      ),
    );
  }
}
