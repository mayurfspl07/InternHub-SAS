import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_colors.dart';

enum KanbanStatus {
  todo,
  inProgress,
  inReview,
  completed;

  static KanbanStatus fromString(String? val) {
    if (val == null) return KanbanStatus.todo;
    final lower = val.toLowerCase().trim().replaceAll(' ', '_').replaceAll('-', '_');
    switch (lower) {
      case 'in_progress':
      case 'inprogress':
        return KanbanStatus.inProgress;
      case 'in_review':
      case 'inreview':
      case 'review':
      case 'testing':
        return KanbanStatus.inReview;
      case 'completed':
      case 'done':
        return KanbanStatus.completed;
      case 'todo':
      default:
        return KanbanStatus.todo;
    }
  }

  String toApiValue() {
    switch (this) {
      case KanbanStatus.todo:
        return 'todo';
      case KanbanStatus.inProgress:
        return 'in_progress';
      case KanbanStatus.inReview:
        return 'review';
      case KanbanStatus.completed:
        return 'done';
    }
  }

  String get label {
    switch (this) {
      case KanbanStatus.todo:
        return 'To Do';
      case KanbanStatus.inProgress:
        return 'In Progress';
      case KanbanStatus.inReview:
        return 'Review';
      case KanbanStatus.completed:
        return 'Completed';
    }
  }
}

/// Task priorities accepted by the API.
enum TaskPriority {
  low,
  medium,
  high;

  static TaskPriority fromString(String? val) {
    if (val == null) return TaskPriority.medium;
    switch (val.toLowerCase().trim()) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      case 'medium':
      default:
        return TaskPriority.medium;
    }
  }

  String toApiValue() => name;
}

class TaskStatusColumn {
  final String key;
  final String title;
  final Color color;
  final String statusCategory; // todo | in_progress | done
  final bool isDefault;
  final int orderIndex;

  const TaskStatusColumn({
    required this.key,
    required this.title,
    required this.color,
    this.statusCategory = 'todo',
    this.isDefault = false,
    this.orderIndex = 0,
  });

  factory TaskStatusColumn.fromJson(Map<String, dynamic> json) {
    final rawName = json['name']?.toString() ?? json['title']?.toString() ?? 'To Do';
    final rawSlug = json['slug']?.toString() ?? json['key']?.toString();
    final colKey = (rawSlug ?? rawName.toLowerCase().replaceAll(' ', '_')).trim().toLowerCase();

    Color colColor = AppColors.textSecondary;
    final colorHex = json['color']?.toString() ?? json['color_hex']?.toString();
    if (colorHex != null && colorHex.isNotEmpty) {
      final parsed = int.tryParse('FF${colorHex.replaceAll('#', '')}', radix: 16);
      if (parsed != null) colColor = Color(parsed);
    } else {
      if (colKey.contains('todo') || colKey.contains('to_do')) {
        colColor = AppColors.textSecondary;
      } else if (colKey.contains('progress')) {
        colColor = AppColors.info;
      } else if (colKey.contains('review') || colKey.contains('test')) {
        colColor = AppColors.warning;
      } else if (colKey.contains('complete') || colKey.contains('done')) {
        colColor = AppColors.success;
      }
    }

    return TaskStatusColumn(
      key: colKey,
      title: rawName,
      color: colColor,
      statusCategory: json['status_category']?.toString() ?? (colKey.contains('done') || colKey.contains('complete') ? 'done' : (colKey.contains('progress') || colKey.contains('review') || colKey.contains('test') ? 'in_progress' : 'todo')),
      isDefault: json['is_default'] == true,
      orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
    );
  }

  static List<TaskStatusColumn> fallbackColumns() {
    return const [
      TaskStatusColumn(key: 'todo', title: 'To Do', color: AppColors.textSecondary, statusCategory: 'todo', isDefault: true, orderIndex: 0),
      TaskStatusColumn(key: 'in_progress', title: 'In Progress', color: AppColors.info, statusCategory: 'in_progress', orderIndex: 1),
      TaskStatusColumn(key: 'review', title: 'Review', color: AppColors.warning, statusCategory: 'in_progress', orderIndex: 2),
      TaskStatusColumn(key: 'done', title: 'Done', color: AppColors.success, statusCategory: 'done', orderIndex: 3),
    ];
  }
}

class TaskComment {
  final String id;
  final String taskId;
  final String userId;
  final String authorName;
  final String authorAvatar;
  final String message;
  final DateTime createdAt;

  /// Files posted with the comment: task attachments whose `comment_id` is this comment.
  final List<TaskAttachment> attachments;

  const TaskComment({
    required this.id,
    this.taskId = '',
    this.userId = '',
    required this.authorName,
    required this.authorAvatar,
    required this.message,
    required this.createdAt,
    this.attachments = const [],
  });

  TaskComment withAttachments(List<TaskAttachment> files) => TaskComment(
        id: id,
        taskId: taskId,
        userId: userId,
        authorName: authorName,
        authorAvatar: authorAvatar,
        message: message,
        createdAt: createdAt,
        attachments: files,
      );

  factory TaskComment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    final userObj = json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : null;

    return TaskComment(
      id: json['id']?.toString() ?? '',
      taskId: json['task_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? userObj?['id']?.toString() ?? '',
      authorName: json['user_name']?.toString() ?? json['author_name']?.toString() ?? userObj?['name']?.toString() ?? 'Member',
      authorAvatar: json['user_avatar']?.toString() ?? json['author_avatar']?.toString() ?? userObj?['avatar_url']?.toString() ?? '',
      message: json['body']?.toString() ?? json['message']?.toString() ?? json['comment']?.toString() ?? '',
      createdAt: parseDate(json['created_at']),
    );
  }
}

class TaskAttachment {
  final String id;
  final String taskId;
  final String fileName;
  final int fileSize;
  final String? contentType;
  final String? url;
  final String? description;
  final String? uploadedByName;
  final String? commentId;
  final DateTime createdAt;

  const TaskAttachment({
    required this.id,
    required this.taskId,
    required this.fileName,
    this.fileSize = 0,
    this.contentType,
    this.url,
    this.description,
    this.uploadedByName,
    this.commentId,
    required this.createdAt,
  });

  factory TaskAttachment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    return TaskAttachment(
      id: json['id']?.toString() ?? '',
      taskId: json['task_id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? 'attachment',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      contentType: json['file_type']?.toString(),
      url: json['download_url']?.toString(),
      description: json['description']?.toString(),
      uploadedByName: json['user_name']?.toString(),
      commentId: json['comment_id']?.toString(),
      createdAt: parseDate(json['created_at']),
    );
  }
}

class TaskChecklistItem {
  final String id;
  final String title;
  final bool isCompleted;

  const TaskChecklistItem({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  factory TaskChecklistItem.fromJson(Map<String, dynamic> json) {
    return TaskChecklistItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      isCompleted: json['is_completed'] is bool ? json['is_completed'] as bool : false,
    );
  }
}

class TaskModel {
  final String id;
  final String projectId;
  final String projectName;
  final String title;
  final String description;
  final String rawStatus;
  final KanbanStatus status;
  final TaskPriority priority;
  final DateTime? dueDate;
  final String? assignedTo;
  final String? assigneeName;
  final String? createdById;
  final String? createdByName;
  final bool isOverdue;
  final bool canEdit;
  final bool canMove;
  final bool canDelete;
  final int commentCount;
  final int attachmentCount;
  final List<String> assigneeNames;
  final List<String> assigneeAvatars;
  final List<TaskChecklistItem> checklist;
  final List<TaskComment> comments;
  final List<TaskAttachment> attachments;
  final DateTime createdAt;

  const TaskModel({
    required this.id,
    required this.projectId,
    this.projectName = '',
    required this.title,
    this.description = '',
    this.rawStatus = 'todo',
    required this.status,
    required this.priority,
    this.dueDate,
    this.assignedTo,
    this.assigneeName,
    this.createdById,
    this.createdByName,
    this.isOverdue = false,
    this.canEdit = true,
    this.canMove = true,
    this.canDelete = true,
    this.commentCount = 0,
    this.attachmentCount = 0,
    this.assigneeNames = const [],
    this.assigneeAvatars = const [],
    this.checklist = const [],
    this.comments = const [],
    this.attachments = const [],
    required this.createdAt,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    final rawStatusStr = (json['status']?.toString() ?? 'todo').trim();
    final kanbanStatus = KanbanStatus.fromString(rawStatusStr);

    String? assignedToId;
    String? assignedName;
    List<String> names = [];
    List<String> avatars = [];

    if (json['assignee'] != null) {
      if (json['assignee'] is Map) {
        assignedToId = json['assignee']['id']?.toString();
        assignedName = json['assignee']['name']?.toString();
        final av = json['assignee']['avatar_url']?.toString();
        if (assignedName != null) names.add(assignedName);
        if (av != null && av.isNotEmpty) avatars.add(av);
      } else {
        assignedName = json['assignee'].toString();
        names.add(assignedName);
      }
    } else if (json['assigned_to'] != null) {
      assignedToId = json['assigned_to'].toString();
      if (json['assignee_name'] != null) {
        assignedName = json['assignee_name'].toString();
        names.add(assignedName);
      }
    }

    if (json['assignee_names'] is List) {
      names = (json['assignee_names'] as List).map((e) => e.toString()).toList();
    }
    if (json['assignee_avatars'] is List) {
      avatars = (json['assignee_avatars'] as List).map((e) => e.toString()).toList();
    }

    List<TaskComment> parsedComments = [];
    if (json['comments'] is List) {
      parsedComments = (json['comments'] as List)
          .whereType<Map<String, dynamic>>()
          .map((c) => TaskComment.fromJson(c))
          .toList();
    }

    List<TaskAttachment> parsedAttachments = [];
    if (json['attachments'] is List) {
      parsedAttachments = (json['attachments'] as List)
          .whereType<Map<String, dynamic>>()
          .map((a) => TaskAttachment.fromJson(a))
          .toList();
    }

    final due = parseDate(json['deadline'] ?? json['due_date']);
    final created = parseDate(json['created_at']) ?? DateTime.now();

    return TaskModel(
      id: json['id']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      projectName: json['project_name']?.toString() ?? json['project']?['name']?.toString() ?? json['project']?['title']?.toString() ?? '',
      title: json['title']?.toString() ?? json['name']?.toString() ?? 'Task',
      description: json['description']?.toString() ?? '',
      rawStatus: rawStatusStr,
      status: kanbanStatus,
      priority: TaskPriority.fromString(json['priority']?.toString()),
      dueDate: due,
      assignedTo: assignedToId ?? json['assigned_to']?.toString() ?? json['assignee_id']?.toString(),
      assigneeName: assignedName ?? json['assignee_name']?.toString() ?? (names.isNotEmpty ? names.first : null),
      createdById: json['created_by_id']?.toString() ?? json['creator_id']?.toString(),
      createdByName: json['created_by_name']?.toString() ?? json['creator_name']?.toString(),
      isOverdue: json['is_overdue'] == true ||
          (due != null && due.isBefore(DateTime.now()) && kanbanStatus != KanbanStatus.completed),
      canEdit: json['can_edit'] is bool ? json['can_edit'] as bool : true,
      canMove: json['can_move'] is bool ? json['can_move'] as bool : true,
      canDelete: json['can_delete'] is bool ? json['can_delete'] as bool : true,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? parsedComments.length,
      attachmentCount: (json['attachment_count'] as num?)?.toInt() ?? parsedAttachments.length,
      assigneeNames: names,
      assigneeAvatars: avatars,
      comments: parsedComments,
      attachments: parsedAttachments,
      createdAt: created,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'project_id': projectId,
      'title': title,
      'description': description,
      'status': rawStatus.isNotEmpty ? rawStatus : status.toApiValue(),
      'priority': priority.toApiValue(),
      'assigned_to': assignedTo,
      if (dueDate != null) 'due_date': DateFormat('yyyy-MM-dd').format(dueDate!),
    };
  }

  TaskModel copyWith({
    String? id,
    String? projectId,
    String? projectName,
    String? title,
    String? description,
    String? rawStatus,
    KanbanStatus? status,
    TaskPriority? priority,
    DateTime? dueDate,
    String? assignedTo,
    String? assigneeName,
    String? createdById,
    String? createdByName,
    bool? isOverdue,
    bool? canEdit,
    bool? canMove,
    bool? canDelete,
    int? commentCount,
    int? attachmentCount,
    List<String>? assigneeNames,
    List<String>? assigneeAvatars,
    List<TaskChecklistItem>? checklist,
    List<TaskComment>? comments,
    List<TaskAttachment>? attachments,
    DateTime? createdAt,
  }) {
    return TaskModel(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      title: title ?? this.title,
      description: description ?? this.description,
      rawStatus: rawStatus ?? this.rawStatus,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: dueDate ?? this.dueDate,
      assignedTo: assignedTo ?? this.assignedTo,
      assigneeName: assigneeName ?? this.assigneeName,
      createdById: createdById ?? this.createdById,
      createdByName: createdByName ?? this.createdByName,
      isOverdue: isOverdue ?? this.isOverdue,
      canEdit: canEdit ?? this.canEdit,
      canMove: canMove ?? this.canMove,
      canDelete: canDelete ?? this.canDelete,
      commentCount: commentCount ?? this.commentCount,
      attachmentCount: attachmentCount ?? this.attachmentCount,
      assigneeNames: assigneeNames ?? this.assigneeNames,
      assigneeAvatars: assigneeAvatars ?? this.assigneeAvatars,
      checklist: checklist ?? this.checklist,
      comments: comments ?? this.comments,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get timeSlot => dueDate == null ? 'No due date' : DateFormat('MMM dd, yyyy').format(dueDate!);
}

class ProjectComment {
  final String id;
  final String projectId;
  final String userId;
  final String userName;
  final String userRole;
  final String userAvatar;
  final String body;
  final DateTime createdAt;
  final bool isDeleted;

  const ProjectComment({
    required this.id,
    required this.projectId,
    required this.userId,
    required this.userName,
    this.userRole = '',
    this.userAvatar = '',
    required this.body,
    required this.createdAt,
    this.isDeleted = false,
  });

  factory ProjectComment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    final userObj = json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : null;

    return ProjectComment(
      id: json['id']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? userObj?['id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? json['author_name']?.toString() ?? userObj?['name']?.toString() ?? 'Member',
      userRole: json['user_role']?.toString() ?? userObj?['role']?.toString() ?? '',
      userAvatar: json['user_avatar']?.toString() ?? userObj?['avatar_url']?.toString() ?? '',
      body: json['body']?.toString() ?? json['message']?.toString() ?? '',
      createdAt: parseDate(json['created_at']),
      isDeleted: json['is_deleted'] == true,
    );
  }
}

class ProjectLink {
  final String id;
  final String projectId;
  final String? userId;
  final String? userName;
  final String link;
  final String remark;
  final DateTime createdAt;
  final bool isDeleted;

  const ProjectLink({
    required this.id,
    required this.projectId,
    this.userId,
    this.userName,
    required this.link,
    required this.remark,
    required this.createdAt,
    this.isDeleted = false,
  });

  factory ProjectLink.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? DateTime.now();
    }

    final userObj = json['user'] is Map<String, dynamic> ? json['user'] as Map<String, dynamic> : null;

    return ProjectLink(
      id: json['id']?.toString() ?? '',
      projectId: json['project_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? userObj?['id']?.toString(),
      userName: json['user_name']?.toString() ?? json['added_by_name']?.toString() ?? userObj?['name']?.toString(),
      link: json['link']?.toString() ?? json['url']?.toString() ?? '',
      remark: json['remark']?.toString() ?? json['title']?.toString() ?? 'Project Resource',
      createdAt: parseDate(json['created_at']),
      isDeleted: json['is_deleted'] == true,
    );
  }
}

class ProjectModel {
  final String id;
  final String name;
  final String title;
  final String description;
  final String status;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime deadline;
  final String department;
  final String? mentorId;
  final String mentorName;
  final List<String> mentorIds;
  final List<Map<String, dynamic>> mentors;
  final List<String> internIds;
  final List<String> memberIds;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> interns;
  final List<TaskModel> tasks;
  final double progress;
  final int taskCount;
  final int taskDone;
  final int taskTotal;
  final int totalTasks;
  final int completedTasks;
  final bool canEdit;
  final DateTime createdAt;

  const ProjectModel({
    required this.id,
    required this.name,
    required this.title,
    this.description = '',
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.deadline,
    this.department = '',
    this.mentorId,
    required this.mentorName,
    this.mentorIds = const [],
    this.mentors = const [],
    this.internIds = const [],
    this.memberIds = const [],
    this.members = const [],
    this.interns = const [],
    this.tasks = const [],
    this.progress = 0.0,
    this.taskCount = 0,
    this.taskDone = 0,
    this.taskTotal = 0,
    this.totalTasks = 0,
    this.completedTasks = 0,
    this.canEdit = true,
    required this.createdAt,
  });

  String get leadMentorName => mentorName;

  List<String> get memberNames {
    final names = <String>[];
    for (final m in members) {
      final n = m['name']?.toString();
      if (n != null && n.isNotEmpty && !names.contains(n)) names.add(n);
    }
    for (final m in mentors) {
      final n = m['name']?.toString();
      if (n != null && n.isNotEmpty && !names.contains(n)) names.add(n);
    }
    return names;
  }

  List<String> get memberAvatars {
    final avatars = <String>[];
    for (final m in members) {
      final av = m['avatar_url']?.toString();
      if (av != null && av.isNotEmpty && !avatars.contains(av)) avatars.add(av);
    }
    for (final m in mentors) {
      final av = m['avatar_url']?.toString();
      if (av != null && av.isNotEmpty && !avatars.contains(av)) avatars.add(av);
    }
    return avatars;
  }

  factory ProjectModel.fromJson(Map<String, dynamic> raw) {
    final json = (raw['data'] is Map<String, dynamic>) ? raw['data'] as Map<String, dynamic> : raw;

    DateTime parseDate(dynamic v, [DateTime? fallback]) {
      if (v == null) return fallback ?? DateTime.now();
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString()) ?? (fallback ?? DateTime.now());
    }

    final pName = json['name']?.toString() ?? json['title']?.toString() ?? 'Untitled Project';

    // 1. Members normalization
    final rawMembersList = json['members'] ??
        json['interns'] ??
        json['intern_members'] ??
        json['team_members'] ??
        json['assigned_interns'];
    List<Map<String, dynamic>> membersList = [];
    if (rawMembersList is List) {
      for (final m in rawMembersList) {
        if (m is Map<String, dynamic>) {
          membersList.add(m);
        } else if (m is Map) {
          membersList.add(Map<String, dynamic>.from(m));
        }
      }
    }

    // 2. Mentors normalization
    final rawMentorsList = json['mentors'] ?? json['project_mentors'] ?? json['assigned_mentors'];
    List<Map<String, dynamic>> mentorsList = [];
    if (rawMentorsList is List) {
      for (final m in rawMentorsList) {
        if (m is Map<String, dynamic>) {
          mentorsList.add(m);
        } else if (m is Map) {
          mentorsList.add(Map<String, dynamic>.from(m));
        }
      }
    } else if (json['mentor'] is Map) {
      mentorsList.add(Map<String, dynamic>.from(json['mentor'] as Map));
    }

    // Also include any members whose role is mentor
    for (final mem in membersList) {
      if (mem['role']?.toString().toLowerCase() == 'mentor') {
        if (!mentorsList.any((m) => m['id']?.toString() == mem['id']?.toString())) {
          mentorsList.add(mem);
        }
      }
    }

    // 3. Mentor IDs and Names
    String? mId = json['mentor_id']?.toString() ?? (json['mentor'] is Map ? json['mentor']['id']?.toString() : null);
    String mName = json['mentor_name']?.toString() ?? (json['mentor'] is Map ? json['mentor']['name']?.toString() : null) ?? '';

    List<String> mentorIds = [];
    if (json['mentor_ids'] is List) {
      mentorIds = (json['mentor_ids'] as List).map((e) => e.toString()).toList();
    } else if (mId != null) {
      mentorIds = [mId];
    }
    for (final m in mentorsList) {
      final idStr = m['id']?.toString();
      if (idStr != null && !mentorIds.contains(idStr)) {
        mentorIds.add(idStr);
      }
    }
    if (mId == null && mentorIds.isNotEmpty) {
      mId = mentorIds.first;
    }
    if (mName.isEmpty && mentorsList.isNotEmpty) {
      mName = mentorsList.first['name']?.toString() ?? 'Mentor';
    }
    if (mName.isEmpty) {
      mName = 'Unassigned';
    }

    // 4. Intern IDs and Member IDs
    List<String> internIds = [];
    if (json['intern_ids'] is List) {
      internIds = (json['intern_ids'] as List).map((e) => e.toString()).toList();
    } else {
      internIds = membersList
          .where((m) => m['role'] == null || m['role'].toString().toLowerCase() == 'intern')
          .map((m) => m['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    }

    List<String> memberIds = [];
    if (json['member_ids'] is List) {
      memberIds = (json['member_ids'] as List).map((e) => e.toString()).toList();
    } else {
      memberIds = membersList.map((m) => m['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
    }

    // 5. Tasks normalization
    final rawTaskList = json['tasks'] ?? json['task_list'] ?? json['project_tasks'];
    List<TaskModel> taskList = [];
    if (rawTaskList is List) {
      for (final t in rawTaskList) {
        if (t is Map) taskList.add(TaskModel.fromJson(Map<String, dynamic>.from(t)));
      }
    }

    // 6. Task counts & progress formula
    int calcTaskDone = 0;
    if (json['task_done'] != null) {
      calcTaskDone = (json['task_done'] as num).toInt();
    } else if (json['completed_tasks'] != null) {
      calcTaskDone = (json['completed_tasks'] as num).toInt();
    } else if (json['completed_tasks_count'] != null) {
      calcTaskDone = (json['completed_tasks_count'] as num).toInt();
    } else {
      calcTaskDone = taskList.where((t) => t.status == KanbanStatus.completed || t.rawStatus.toLowerCase() == 'completed' || t.rawStatus.toLowerCase() == 'done').length;
    }

    int calcTaskTotal = 0;
    if (json['task_total'] != null) {
      calcTaskTotal = (json['task_total'] as num).toInt();
    } else if (json['total_tasks'] != null) {
      calcTaskTotal = (json['total_tasks'] as num).toInt();
    } else if (json['task_count'] != null) {
      calcTaskTotal = (json['task_count'] as num).toInt();
    } else if (json['tasks_count'] != null) {
      calcTaskTotal = (json['tasks_count'] as num).toInt();
    } else {
      calcTaskTotal = taskList.length;
    }

    // The API reports progress as a whole percentage (0-100).
    double calcProgress = 0.0;
    final rawProg = json['progress'];
    if (rawProg is num) {
      calcProgress = rawProg.toDouble() / 100.0;
    } else if (calcTaskTotal > 0) {
      calcProgress = (calcTaskDone / calcTaskTotal);
    }
    calcProgress = calcProgress.clamp(0.0, 1.0);

    final start = parseDate(json['start_date'], DateTime.now());
    final end = parseDate(json['end_date'] ?? json['deadline'], DateTime.now().add(const Duration(days: 30)));
    final created = parseDate(json['created_at'], DateTime.now());

    final canEditVal = json['can_edit'] is bool ? json['can_edit'] as bool : true;

    return ProjectModel(
      id: json['id']?.toString() ?? '',
      name: pName,
      title: pName,
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'planning',
      startDate: start,
      endDate: end,
      deadline: end,
      department: json['department']?.toString() ?? '',
      mentorId: mId,
      mentorName: mName,
      mentorIds: mentorIds,
      mentors: mentorsList,
      internIds: internIds,
      memberIds: memberIds,
      members: membersList,
      interns: membersList.where((m) => m['role'] == null || m['role'].toString().toLowerCase() == 'intern').toList(),
      tasks: taskList,
      progress: calcProgress,
      taskCount: calcTaskTotal,
      taskDone: calcTaskDone,
      taskTotal: calcTaskTotal,
      totalTasks: calcTaskTotal,
      completedTasks: calcTaskDone,
      canEdit: canEditVal,
      createdAt: created,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'title': name,
      'description': description,
      'status': status,
      'mentor_id': mentorId != null ? int.tryParse(mentorId!) ?? mentorId : null,
      'mentor_ids': mentorIds.map((id) => int.tryParse(id) ?? id).toList(),
      'intern_ids': internIds.map((id) => int.tryParse(id) ?? id).toList(),
      'member_ids': memberIds.map((id) => int.tryParse(id) ?? id).toList(),
      'start_date': DateFormat('yyyy-MM-dd').format(startDate),
      'end_date': DateFormat('yyyy-MM-dd').format(endDate),
    };
  }

  ProjectModel copyWith({
    String? id,
    String? name,
    String? title,
    String? description,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? deadline,
    String? department,
    String? mentorId,
    String? mentorName,
    List<String>? mentorIds,
    List<Map<String, dynamic>>? mentors,
    List<String>? internIds,
    List<String>? memberIds,
    List<Map<String, dynamic>>? members,
    List<Map<String, dynamic>>? interns,
    List<TaskModel>? tasks,
    double? progress,
    int? taskCount,
    int? taskDone,
    int? taskTotal,
    int? totalTasks,
    int? completedTasks,
    bool? canEdit,
    DateTime? createdAt,
  }) {
    return ProjectModel(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      deadline: deadline ?? this.deadline,
      department: department ?? this.department,
      mentorId: mentorId ?? this.mentorId,
      mentorName: mentorName ?? this.mentorName,
      mentorIds: mentorIds ?? this.mentorIds,
      mentors: mentors ?? this.mentors,
      internIds: internIds ?? this.internIds,
      memberIds: memberIds ?? this.memberIds,
      members: members ?? this.members,
      interns: interns ?? this.interns,
      tasks: tasks ?? this.tasks,
      progress: progress ?? this.progress,
      taskCount: taskCount ?? this.taskCount,
      taskDone: taskDone ?? this.taskDone,
      taskTotal: taskTotal ?? this.taskTotal,
      totalTasks: totalTasks ?? this.totalTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      canEdit: canEdit ?? this.canEdit,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
