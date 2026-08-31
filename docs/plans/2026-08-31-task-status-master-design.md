# Task Status Master Design Document

> **Document ID:** `2026-08-31-task-status-master-design.md`  
> **Status:** Approved Design  
> **Date:** 2026-08-31  

---

## 1. Executive Summary & Problem Statement

Currently, task statuses across InternHub (e.g. `todo`, `in_progress`, `testing`, `done`) are hardcoded in the codebase (`TaskStatus` enum). Different teams and organizations require customized workflows (for example: *Started → In Progress → Review → Completed*, where "Testing" may not be necessary).

This feature introduces the **Task Status / Bucket Master** in the Admin Panel. Admins can define, reorder, color-code, and customize task status buckets scoped to their organization, while preserving data integrity, metrics, and overdue tracking.

---

## 2. Architecture & Data Model

### 2.1 Entity: `TaskStatusBucket`
- **Table:** `task_status_buckets`
- **Columns:**
  - `id`: `Integer`, Primary Key, Autoincrement
  - `organization_id`: `Integer`, ForeignKey(`organizations.id`, ondelete="CASCADE"), Indexed, Not Null
  - `name`: `String(60)`, Not Null (e.g. `"Started"`, `"In Progress"`, `"Review"`, `"Completed"`)
  - `slug`: `String(60)`, Not Null (URL-safe string, e.g. `"started"`, `"in_progress"`, `"review"`, `"done"`)
  - `color`: `String(20)`, Not Null, Default `"#6366F1"` (hex color code for Kanban column & badge)
  - `order_index`: `Integer`, Not Null, Default `0` (sequence ordering)
  - `status_category`: `String(20)`, Not Null, Default `"in_progress"` (`'todo'`, `'in_progress'`, or `'done'`)
  - `is_default`: `Boolean`, Not Null, Default `False` (new tasks default to this bucket if not specified)
  - `created_at`: `DateTime`, Not Null, UTC
  - `updated_at`: `DateTime`, Not Null, UTC
- **Constraints:**
  - `UniqueConstraint("organization_id", "slug", name="uq_org_status_slug")`
  - `UniqueConstraint("organization_id", "name", name="uq_org_status_name")`

### 2.2 Default Seeding for Organizations
When an organization is initialized or first queries task statuses without existing custom configuration, seed:
1. **To Do** (`slug: "todo"`, `status_category: "todo"`, `is_default: True`, `color: "#94A3B8"`, `order_index: 0`)
2. **In Progress** (`slug: "in_progress"`, `status_category: "in_progress"`, `is_default: False`, `color: "#3B82F6"`, `order_index: 1`)
3. **Review** (`slug: "review"`, `status_category: "in_progress"`, `is_default: False`, `color: "#F59E0B"`, `order_index: 2`)
4. **Completed** (`slug: "done"`, `status_category: "done"`, `is_default: False`, `color: "#10B981"`, `order_index: 3`)

---

## 3. Admin & Project API Endpoints

### 3.1 Admin Endpoints (`/api/admin/task-statuses`)
- `GET /api/admin/task-statuses`: List all status buckets for current organization ordered by `order_index`, with `task_count` per bucket.
- `POST /api/admin/task-statuses`: Create a new status bucket.
- `PUT /api/admin/task-statuses/{id}`: Update bucket name, color, category, is_default, order_index.
- `DELETE /api/admin/task-statuses/{id}`: Delete bucket. Blocked if any active tasks are assigned to this status (returns 422 with count of active tasks).
- `PUT /api/admin/task-statuses/reorder`: Bulk update display ordering via list of status IDs.

### 3.2 Scoped Project / Board Endpoints
- `GET /api/projects/task-statuses` (and `GET /api/projects/{id}/task-statuses`): List active buckets for Kanban columns and task forms.

---

## 4. Integration with Task Lifecycle, Metrics & Backward Compatibility

- **Task Creation (`POST /api/projects/{id}/tasks`):**
  - If `status` is omitted, defaults to the organization's `is_default=True` bucket.
  - If provided, validates against the organization's active buckets.
- **Task Status Updates (`PUT /api/projects/tasks/{id}`, `PATCH /api/projects/tasks/{id}/status`):**
  - Validates `new_status` against the project's organization buckets.
  - Audits status transitions (`Started → Review`).
- **Completion & Progress Tracking:**
  - Dynamically calculates `done_count` and completion percentages based on any status marked `status_category == "done"`.
  - Overdue calculations (`is_overdue`) ignore all tasks in `"done"` category buckets.
- **Dashboard Analytics:**
  - Groups tasks dynamically by the organization's configured buckets.
