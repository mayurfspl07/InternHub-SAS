import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state_provider.dart';
import '../../shared/models/project_model.dart';
import '../../shared/models/user_model.dart';
import '../../core/constants/app_colors.dart';

class ProjectFormDialog extends ConsumerStatefulWidget {
  final ProjectModel? projectToEdit;
  final VoidCallback onSuccess;

  const ProjectFormDialog({
    super.key,
    this.projectToEdit,
    required this.onSuccess,
  });

  @override
  ConsumerState<ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends ConsumerState<ProjectFormDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _mentorSearchController = TextEditingController();
  final TextEditingController _internSearchController = TextEditingController();

  String _selectedStatus = 'planning';
  List<String> _projectStatuses = ['planning', 'active', 'on_hold', 'completed'];

  DateTime? _startDate;
  DateTime? _endDate;

  final Set<String> _selectedMentorIds = {};
  final Set<String> _selectedInternIds = {};

  List<Map<String, dynamic>> _mentors = [];
  List<Map<String, dynamic>> _interns = [];

  bool _isLoading = true;
  bool _isSubmitting = false;

  String? _nameError;
  String? _descError;
  String? _dateError;
  String? _mentorsError;
  String? _internsError;

  bool get isEdit => widget.projectToEdit != null;

  @override
  void initState() {
    super.initState();

    if (isEdit) {
      final p = widget.projectToEdit!;
      _nameController.text = p.name;
      _descController.text = p.description;
      _selectedStatus = p.status.toLowerCase().replaceAll(' ', '_');
      _startDate = p.startDate;
      _endDate = p.endDate;

      // Mentors pre-fill
      for (final id in p.mentorIds) {
        if (id.isNotEmpty) _selectedMentorIds.add(id);
      }
      if (p.mentorId != null && p.mentorId!.isNotEmpty) {
        _selectedMentorIds.add(p.mentorId!);
      }
      for (final m in p.mentors) {
        final id = (m['id'] ?? m['user_id'])?.toString();
        if (id != null && id.isNotEmpty) _selectedMentorIds.add(id);
      }

      // Interns pre-fill
      for (final id in p.internIds) {
        if (id.isNotEmpty) _selectedInternIds.add(id);
      }
      for (final intern in p.interns) {
        final id = (intern['id'] ?? intern['user_id'])?.toString();
        if (id != null && id.isNotEmpty) _selectedInternIds.add(id);
      }
      for (final mem in p.members) {
        final id = (mem['id'] ?? mem['user_id'])?.toString();
        final role = mem['role']?.toString().toLowerCase();
        if (id != null && id.isNotEmpty) {
          if (role == 'mentor') {
            _selectedMentorIds.add(id);
          } else {
            _selectedInternIds.add(id);
          }
        }
      }
      if (_selectedInternIds.isEmpty && p.memberIds.isNotEmpty) {
        for (final id in p.memberIds) {
          if (id.isNotEmpty && !_selectedMentorIds.contains(id)) {
            _selectedInternIds.add(id);
          }
        }
      }
    }

    _loadFormData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _mentorSearchController.dispose();
    _internSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadFormData() async {
    try {
      final curUser = ref.read(appStateProvider).currentUser;

      // Parallel loads
      final results = await Future.wait([
        ApiClient()
            .get('/api/users/dropdown', queryParameters: {'role': 'mentor'})
            .catchError((_) => ApiClient().get('/api/projects/mentors', queryParameters: {'page': 1, 'page_size': 30}))
            .catchError((_) => []),
        ApiClient()
            .get('/api/users/dropdown', queryParameters: {'role': 'intern'})
            .catchError((_) => ApiClient().get('/api/projects/interns', queryParameters: {'page': 1, 'page_size': 30}))
            .catchError((_) => []),
        ApiClient().get('/api/projects/project-statuses').catchError((_) => []),
      ]);

      // Mentors
      List<Map<String, dynamic>> mentorList = [];
      final mRes = results[0];
      if (mRes is List) {
        mentorList = mRes.whereType<Map<String, dynamic>>().toList();
      } else if (mRes is Map<String, dynamic>) {
        final items = mRes['users'] ?? mRes['mentors'] ?? mRes['items'] ?? mRes['results'] ?? mRes['data'];
        if (items is List) mentorList = items.whereType<Map<String, dynamic>>().toList();
      }

      // Interns
      List<Map<String, dynamic>> internList = [];
      final iRes = results[1];
      if (iRes is List) {
        internList = iRes.whereType<Map<String, dynamic>>().toList();
      } else if (iRes is Map<String, dynamic>) {
        final items = iRes['users'] ?? iRes['interns'] ?? iRes['items'] ?? iRes['results'] ?? iRes['data'];
        if (items is List) internList = items.whereType<Map<String, dynamic>>().toList();
      }

      // Fallback to universal dropdown if either is empty
      if (mentorList.isEmpty || internList.isEmpty) {
        try {
          final uRes = await ApiClient().get('/api/users/dropdown');
          List<Map<String, dynamic>> uList = [];
          if (uRes is List) {
            uList = uRes.whereType<Map<String, dynamic>>().toList();
          } else if (uRes is Map<String, dynamic>) {
            final items = uRes['users'] ?? uRes['items'] ?? uRes['data'];
            if (items is List) uList = items.whereType<Map<String, dynamic>>().toList();
          }
          if (mentorList.isEmpty) {
            mentorList = uList.where((u) => u['role']?.toString().toLowerCase() == 'mentor').toList();
          }
          if (internList.isEmpty) {
            internList = uList.where((u) => u['role']?.toString().toLowerCase() == 'intern').toList();
          }
        } catch (_) {}
      }

      // Final fallback to cached users in state
      if (mentorList.isEmpty) {
        final all = ref.read(appStateProvider).allUsers;
        mentorList = all
            .where((u) => u.role == UserRole.mentor)
            .map((u) => {'id': u.id, 'name': u.name, 'email': u.email, 'role': 'mentor'})
            .toList();
      }

      if (internList.isEmpty) {
        final all = ref.read(appStateProvider).allUsers;
        internList = all
            .where((u) => u.role == UserRole.intern)
            .map((u) => {'id': u.id, 'name': u.name, 'email': u.email, 'role': 'intern'})
            .toList();
      }

      // Also ensure project's existing mentors and members are present in list if editing
      if (isEdit) {
        final p = widget.projectToEdit!;
        for (final m in p.mentors) {
          final mId = (m['id'] ?? m['user_id'])?.toString();
          if (mId != null && !mentorList.any((item) => (item['id'] ?? item['user_id'])?.toString() == mId)) {
            mentorList.add(m);
          }
        }
        for (final mem in p.members) {
          final memId = (mem['id'] ?? mem['user_id'])?.toString();
          final role = mem['role']?.toString().toLowerCase();
          if (role == 'mentor') {
            if (memId != null && !mentorList.any((item) => (item['id'] ?? item['user_id'])?.toString() == memId)) {
              mentorList.add(mem);
            }
          } else {
            if (memId != null && !internList.any((item) => (item['id'] ?? item['user_id'])?.toString() == memId)) {
              internList.add(mem);
            }
          }
        }
        for (final intern in p.interns) {
          final iId = (intern['id'] ?? intern['user_id'])?.toString();
          if (iId != null && !internList.any((item) => (item['id'] ?? item['user_id'])?.toString() == iId)) {
            internList.add(intern);
          }
        }
      }

      // Statuses
      List<String> statuses = [];
      final sRes = results[2];
      if (sRes is List) {
        for (final item in sRes) {
          if (item is Map) {
            final key = item['slug'] ?? item['key'] ?? item['name'];
            if (key != null) statuses.add(key.toString().toLowerCase());
          } else if (item is String) {
            statuses.add(item.toLowerCase());
          }
        }
      }

      if (statuses.isEmpty) {
        statuses = ['planning', 'active', 'in_progress', 'review', 'on_hold', 'completed', 'archived'];
      }

      // Ensure current status is included
      if (!statuses.contains(_selectedStatus)) {
        statuses.insert(0, _selectedStatus);
      }

      // If actor is mentor and creating, lock as mentor on project
      if (!isEdit) {
        if (curUser.role == UserRole.mentor) {
          _selectedMentorIds.add(curUser.id);
        } else if (mentorList.isNotEmpty) {
          final firstId = (mentorList.first['id'] ?? mentorList.first['user_id'])?.toString() ?? '';
          if (firstId.isNotEmpty) _selectedMentorIds.add(firstId);
        }
      }

      if (mounted) {
        setState(() {
          _mentors = mentorList;
          _interns = internList;
          _projectStatuses = statuses;
          if (!isEdit) {
            _selectedStatus = statuses.first;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _validate() {
    setState(() {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        _nameError = 'Project name is required';
      } else if (name.length > 100) {
        _nameError = 'Max 100 characters';
      } else {
        _nameError = null;
      }

      final desc = _descController.text.trim();
      if (desc.length > 300) {
        _descError = 'Max 300 characters';
      } else {
        _descError = null;
      }

      // Dates validation
      if (_startDate == null && _endDate == null) {
        _dateError = 'Both dates are required';
      } else if (_startDate == null) {
        _dateError = 'Start date is required';
      } else if (_endDate == null) {
        _dateError = 'End date is required';
      } else if (_endDate!.isBefore(_startDate!)) {
        _dateError = 'End date must be on or after start date';
      } else {
        _dateError = null;
      }

      // Mentors validation
      if (_selectedMentorIds.isEmpty) {
        _mentorsError = 'At least 1 mentor is required';
      } else {
        _mentorsError = null;
      }

      // Interns validation
      if (_selectedInternIds.isEmpty) {
        _internsError = 'At least 1 intern is required';
      } else {
        _internsError = null;
      }
    });
  }

  Future<void> _submit() async {
    _validate();
    if (_nameError != null || _descError != null || _dateError != null || _mentorsError != null || _internsError != null) {
      return;
    }

    final curUser = ref.read(appStateProvider).currentUser;
    // Mentor actor cannot remove self
    if (curUser.role == UserRole.mentor && !_selectedMentorIds.contains(curUser.id)) {
      _selectedMentorIds.add(curUser.id);
    }

    final mentorIds = _selectedMentorIds.map((id) => int.tryParse(id) ?? id).toList();
    final internIds = _selectedInternIds.map((id) => int.tryParse(id) ?? id).toList();
    final firstMentorId = mentorIds.isNotEmpty ? mentorIds.first : null;

    final payload = <String, dynamic>{
      'name': _nameController.text.trim(),
      'status': _selectedStatus,
      'mentor_id': firstMentorId,
      'mentor_ids': mentorIds,
      'intern_ids': internIds,
      'member_ids': internIds,
      'start_date': DateFormat('yyyy-MM-dd').format(_startDate!),
      'end_date': DateFormat('yyyy-MM-dd').format(_endDate!),
    };

    payload['description'] = _descController.text.trim();

    setState(() => _isSubmitting = true);

    try {
      if (isEdit) {
        await ApiClient().put('/api/projects/${widget.projectToEdit!.id}', body: payload);
      } else {
        await ApiClient().post('/api/projects', body: payload);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Project updated successfully!' : 'Project created successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is ApiException ? e.message : 'Failed to save project: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final curUser = ref.read(appStateProvider).currentUser;

    final mentorFilter = _mentorSearchController.text.trim().toLowerCase();
    final filteredMentors = _mentors.where((m) {
      final name = m['name']?.toString().toLowerCase() ?? '';
      final email = m['email']?.toString().toLowerCase() ?? '';
      return name.contains(mentorFilter) || email.contains(mentorFilter);
    }).toList();

    final internFilter = _internSearchController.text.trim().toLowerCase();
    final filteredInterns = _interns.where((i) {
      final name = i['name']?.toString().toLowerCase() ?? '';
      final email = i['email']?.toString().toLowerCase() ?? '';
      return name.contains(internFilter) || email.contains(internFilter);
    }).toList();

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(22),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEdit ? 'Edit Project' : 'Create New Project',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Configure project details, mentors, sprint timelines, and assigned interns.',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Scrollable Form Fields
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Project Name
                          _buildLabel('PROJECT NAME *'),
                          TextField(
                            controller: _nameController,
                            onChanged: (_) => _validate(),
                            style: TextStyle(fontSize: 13, color: AppColors.ink),
                            decoration: _inputDecoration(
                              hint: 'e.g. Intern Operations Portal',
                              errorText: _nameError,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Description
                          _buildLabel('DESCRIPTION'),
                          TextField(
                            controller: _descController,
                            maxLines: 2,
                            onChanged: (_) => _validate(),
                            style: TextStyle(fontSize: 13, color: AppColors.ink),
                            decoration: _inputDecoration(
                              hint: 'Brief summary of objectives and deliverables...',
                              errorText: _descError,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Status
                          _buildLabel('STATUS *'),
                          Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _projectStatuses.contains(_selectedStatus) ? _selectedStatus : _projectStatuses.first,
                                isExpanded: true,
                                dropdownColor: Colors.white,
                                items: _projectStatuses.map((s) {
                                  return DropdownMenuItem(
                                    value: s,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: AppColors.info,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          s[0].toUpperCase() + s.substring(1).replaceAll('_', ' '),
                                          style: TextStyle(fontSize: 13, color: AppColors.ink),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedStatus = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Mentors (Multi-select)
                          _buildLabel('MENTORS *'),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _mentorsError != null
                                    ? AppColors.danger
                                    : AppColors.border,
                              ),
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _mentorSearchController,
                                    onChanged: (_) => setState(() {}),
                                    style: TextStyle(fontSize: 12, color: AppColors.ink),
                                    decoration: InputDecoration(
                                      hintText: 'Search mentors by name or email...',
                                      hintStyle: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                      prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textTertiary),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.zero,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: AppColors.border),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 110,
                                  child: filteredMentors.isEmpty
                                      ? Center(
                                          child: Text(
                                            _mentors.isEmpty ? 'Loading mentors...' : 'No mentors match search',
                                            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: filteredMentors.length,
                                          itemBuilder: (ctx, i) {
                                            final m = filteredMentors[i];
                                            final id = (m['id'] ?? m['user_id'])?.toString() ?? '';
                                            final isSelected = _selectedMentorIds.contains(id);
                                            final isSelfMentor = curUser.role == UserRole.mentor && curUser.id == id;

                                            return CheckboxListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity: VisualDensity.compact,
                                              title: Text(
                                                m['name']?.toString() ?? 'Mentor',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
                                              ),
                                              subtitle: Text(
                                                m['email']?.toString() ?? '',
                                                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                              ),
                                              value: isSelected,
                                              onChanged: isSelfMentor
                                                  ? null // locked as mentor on the project (cannot remove self)
                                                  : (checked) {
                                                      setState(() {
                                                        if (checked == true) {
                                                          _selectedMentorIds.add(id);
                                                        } else {
                                                          _selectedMentorIds.remove(id);
                                                        }
                                                      });
                                                      _validate();
                                                    },
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                          if (_mentorsError != null)
                            Padding(
                               padding: const EdgeInsets.only(top: 4, left: 4),
                               child: Text(_mentorsError!, style: const TextStyle(fontSize: 11, color: AppColors.danger)),
                            ),
                          const SizedBox(height: 14),

                          // Start Date & End Date Row
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel('START DATE *'),
                                    InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _startDate ?? DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2035),
                                        );
                                        if (picked != null) {
                                          setState(() => _startDate = picked);
                                          _validate();
                                        }
                                      },
                                      child: Container(
                                        height: 42,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceMuted,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: _dateError != null ? AppColors.danger : AppColors.border,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _startDate != null ? DateFormat('dd/MM/yyyy').format(_startDate!) : 'dd/mm/yyyy',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: _startDate != null ? AppColors.ink : AppColors.textTertiary,
                                              ),
                                            ),
                                            const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildLabel('END DATE *'),
                                    InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: _endDate ?? (_startDate ?? DateTime.now()).add(const Duration(days: 30)),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2035),
                                        );
                                        if (picked != null) {
                                          setState(() => _endDate = picked);
                                          _validate();
                                        }
                                      },
                                      child: Container(
                                        height: 42,
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceMuted,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: _dateError != null ? AppColors.danger : AppColors.border,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _endDate != null ? DateFormat('dd/MM/yyyy').format(_endDate!) : 'dd/mm/yyyy',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: _endDate != null ? AppColors.ink : AppColors.textTertiary,
                                              ),
                                            ),
                                            const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.textSecondary),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_dateError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Text(_dateError!, style: const TextStyle(fontSize: 11, color: AppColors.danger)),
                            ),
                          const SizedBox(height: 14),

                          // Assign Interns (Multi-select)
                          _buildLabel('ASSIGN INTERNS *'),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _internsError != null
                                    ? AppColors.danger
                                    : AppColors.border,
                              ),
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 36,
                                  child: TextField(
                                    controller: _internSearchController,
                                    onChanged: (_) => setState(() {}),
                                    style: TextStyle(fontSize: 12, color: AppColors.ink),
                                    decoration: InputDecoration(
                                      hintText: 'Search interns by name or email...',
                                      hintStyle: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                      prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textTertiary),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: EdgeInsets.zero,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: BorderSide(color: AppColors.border),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 110,
                                  child: filteredInterns.isEmpty
                                      ? Center(
                                          child: Text(
                                            _interns.isEmpty ? 'Loading interns...' : 'No interns match search',
                                            style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: filteredInterns.length,
                                          itemBuilder: (ctx, i) {
                                            final intern = filteredInterns[i];
                                            final id = (intern['id'] ?? intern['user_id'])?.toString() ?? '';
                                            final isSelected = _selectedInternIds.contains(id);

                                            return CheckboxListTile(
                                              dense: true,
                                              contentPadding: EdgeInsets.zero,
                                              visualDensity: VisualDensity.compact,
                                              title: Text(
                                                intern['name']?.toString() ?? 'Intern',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink),
                                              ),
                                              subtitle: Text(
                                                intern['email']?.toString() ?? '',
                                                style: TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                              ),
                                              value: isSelected,
                                              onChanged: (checked) {
                                                setState(() {
                                                  if (checked == true) {
                                                    _selectedInternIds.add(id);
                                                  } else {
                                                    _selectedInternIds.remove(id);
                                                  }
                                                });
                                                _validate();
                                              },
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          ),
                          if (_internsError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, left: 4),
                              child: Text(_internsError!, style: const TextStyle(fontSize: 11, color: AppColors.danger)),
                            ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  const Divider(height: 20),

                  // Actions
                  Wrap(
                    alignment: WrapAlignment.end,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: AppColors.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                            : Text(isEdit ? 'Save Changes' : 'Create Project', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({required String hint, String? errorText}) {
    return InputDecoration(
      hintText: hint,
      errorText: errorText,
      hintStyle: TextStyle(fontSize: 12, color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.warning, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    );
  }
}
