# Task Status / Bucket Master Implementation Plan

> **For Cursor / Antigravity:** Use `executing-plans` or `subagent-driven-development` to implement this plan task-by-task.

**Goal:** Create a customizable Task Status / Bucket Master in the Admin Panel so admins can create, customize, and reorder workflow buckets (e.g., *Started → In Progress → Review → Completed* without mandatory "Testing") with tenant isolation, safety guards, and dynamic project metrics.

**Architecture:** A dedicated `task_status_buckets` table keyed by `organization_id` with metadata for name, slug, color, sequence order, and logical category (`todo`, `in_progress`, `done`). Task APIs and metrics dynamically validate against and query the tenant's configured status buckets.

**Tech Stack:** FastAPI, SQLAlchemy 2.0, Pydantic, SQLite / MySQL, Pytest.

---

## User Review Required

> [!IMPORTANT]
> Existing organizations will automatically receive default workflow buckets (`To Do`, `In Progress`, `Review`, `Completed`) during database initialization/migration, ensuring full backward compatibility with existing task data.

> [!NOTE]
> Deletion of a status bucket is guarded: admins cannot delete a bucket if active tasks are currently assigned to it. Tasks must be moved or reassigned first.

---

## Proposed Changes

Grouped by layer and component:

### 1. Database Model & Migrations

#### [MODIFY] [models.py](file:///d:/download/internhub%20backend/internhub%20backend/models.py)
- Define `TaskStatusBucket` SQLAlchemy model with `id`, `organization_id`, `name`, `slug`, `color`, `order_index`, `status_category`, `is_default`, `created_at`, `updated_at`.
- Add unique constraints `uq_org_status_slug` and `uq_org_status_name`.
- Add relationship on `Organization` to `task_statuses`.
- Update `Task.is_overdue` to support dynamic status categories.

#### [NEW] [migrations/add_task_status_buckets.py](file:///d:/download/internhub%20backend/internhub%20backend/migrations/add_task_status_buckets.py)
- Standalone migration to create `task_status_buckets` table and seed default buckets for all existing organizations.

#### [MODIFY] [init_db.py](file:///d:/download/internhub%20backend/internhub%20backend/init_db.py)
- Include `TaskStatusBucket` in table initialization and auto-seeding.

---

### 2. Schemas & Data Transfer Objects

#### [MODIFY] [routes/api/schemas.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/schemas.py)
- Add `TaskStatusBucketCreatePayload`, `TaskStatusBucketUpdatePayload`, `TaskStatusBucketReorderPayload`, and `TaskStatusBucketResponse`.

#### [MODIFY] [app/modules/tasks/schemas.py](file:///d:/download/internhub%20backend/internhub%20backend/app/modules/tasks/schemas.py)
- Add Pydantic validation models for task status buckets.

---

### 3. Utility Helpers & Tenant Workflow Services

#### [MODIFY] [utils.py](file:///d:/download/internhub%20backend/internhub%20backend/utils.py)
- Add `get_or_seed_org_task_statuses(db: Session, org_id: int) -> list[TaskStatusBucket]`.
- Add `get_org_done_statuses(db: Session, org_id: int) -> set[str]`.
- Add `slugify_status_name(name: str) -> str`.

---

### 4. Admin API Endpoints

#### [MODIFY] [routes/api/admin.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/admin.py)
- `GET /api/admin/task-statuses`: Return configured buckets with `task_count` per bucket.
- `POST /api/admin/task-statuses`: Create custom bucket, validate name/slug uniqueness within org, handle `is_default` flag.
- `PUT /api/admin/task-statuses/{id}`: Update bucket properties.
- `DELETE /api/admin/task-statuses/{id}`: Safeguard deletion (reject if active tasks exist or if last default/done bucket).
- `PUT /api/admin/task-statuses/reorder`: Batch reorder status sequence.

---

### 5. Project & Task Route Integration

#### [MODIFY] [routes/api/projects.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/projects.py)
- `GET /api/projects/task-statuses`: Return active buckets for current tenant.
- `POST /api/projects/{project_id}/tasks`: Validate status against org buckets; fallback to `is_default` bucket.
- `PUT /api/projects/tasks/{task_id}` & `PATCH /api/projects/tasks/{task_id}/status`: Dynamic status validation and human-readable audit logging.
- `_task_stats_for_projects` & `get_project`: Dynamically count completed tasks using org's `status_category == 'done'`.

---

### 6. Dashboard & Analytics Integration

#### [MODIFY] [routes/api/dashboard.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/dashboard.py)
- Update task metric summaries to dynamically group by active task status buckets and properly aggregate completed tasks.

---

## Verification Plan

### Automated Tests
- Create `tests/test_task_status_master.py` testing:
  1. `test_default_status_seeding`: Verify initial default buckets are created for an organization.
  2. `test_admin_create_custom_status`: Create a custom bucket (e.g. `Review` or `QA`) with custom color and category.
  3. `test_admin_reorder_statuses`: Reorder buckets and verify display sequence.
  4. `test_admin_delete_status_safety`: Attempt to delete a bucket with assigned tasks and verify `422` refusal.
  5. `test_admin_delete_unused_status`: Delete an unused bucket successfully.
  6. `test_task_workflow_dynamic_validation`: Create and transition tasks across custom statuses (*Started → In Progress → Review → Completed*).
  7. `test_project_completion_metric`: Verify project completion percentage updates based on custom `done` category buckets.
  8. `test_tenant_isolation`: Verify Organization A cannot see or modify Organization B's status buckets.

Run test command:
```bash
pytest tests/test_task_status_master.py -v
pytest tests/ -v
```

### Manual Verification
- Test creating tasks without status and verify default bucket assignment.
- Test moving tasks across custom bucket stages.
- Test admin configuration page endpoint payloads.
