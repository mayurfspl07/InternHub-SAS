import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/constants/app_colors.dart';
import '../../shared/models/user_model.dart';
import '../../shared/models/project_model.dart';
import 'user_360_profile_dialog.dart';
import 'app_avatar.dart';

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
  bool _isLoading = false;

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
      setState(() {
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
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient().get('/api/search', queryParameters: {'q': query});
      if (res is Map<String, dynamic> && mounted) {
        List<UserModel> users = [];
        if (res['users'] is List) {
          users = (res['users'] as List)
              .whereType<Map<String, dynamic>>()
              .map((u) => UserModel.fromJson(u))
              .toList();
        }

        List<ProjectModel> projs = [];
        if (res['projects'] is List) {
          projs = (res['projects'] as List)
              .whereType<Map<String, dynamic>>()
              .map((p) => ProjectModel.fromJson(p))
              .toList();
        }

        List<TaskModel> tasks = [];
        if (res['tasks'] is List) {
          tasks = (res['tasks'] as List)
              .whereType<Map<String, dynamic>>()
              .map((t) => TaskModel.fromJson(t))
              .toList();
        }

        setState(() {
          _users = users;
          _projects = projs;
          _tasks = tasks;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
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
              decoration: InputDecoration(
                hintText: 'Search users, projects, tasks...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                suffixIcon: _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : (_searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E143B) : const Color(0xFFF3F4F6),
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
            child: (_users.isEmpty && _projects.isEmpty && _tasks.isEmpty)
                ? Center(
                    child: Text(
                      _searchController.text.isEmpty
                          ? 'Type to search across InternHub'
                          : 'No results found',
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey.shade500,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    children: [
                      // Users
                      if (_users.isNotEmpty) ...[
                        Text(
                          'USERS (${_users.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._users.map((u) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: AppAvatar(url: u.avatarUrl, size: 40, fallbackText: u.name),
                              title: Text(u.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${u.roleTitle} • ${u.department ?? ''}'),
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
                        Text(
                          'PROJECTS (${_projects.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._projects.map((p) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.folder_outlined, color: AppColors.primary),
                              ),
                              title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${(p.progress * 100).toInt()}% progress • ${p.status}'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                Navigator.pop(context);
                              },
                            )),
                        const SizedBox(height: 16),
                      ],

                      // Tasks
                      if (_tasks.isNotEmpty) ...[
                        Text(
                          'TASKS (${_tasks.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._tasks.map((t) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.secondary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.assignment_outlined, color: AppColors.secondary),
                              ),
                              title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${t.projectName} • ${t.status.label}'),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                Navigator.pop(context);
                              },
                            )),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
