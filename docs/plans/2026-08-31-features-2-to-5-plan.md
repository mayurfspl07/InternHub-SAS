# Features 2–5 Implementation Plan

> **For Cursor / Antigravity:** Use `executing-plans` or `subagent-driven-development` to implement this plan task-by-task.

**Goal:** Implement:
1. Check-in/check-out time display in **IST** (`Asia/Kolkata`, `UTC+05:30`).
2. **Task Attachments** allowing interns/mentors to attach documents, reports, and screenshots to tasks and comments.
3. **Internship Period & Leave Visibility** displaying start/end date, duration (e.g. *3 Months*), approved leaves, leaves used, and remaining balance.
4. **Leave Application Attachment** allowing optional medical certificates / document uploads when applying for leave.

**Architecture:** Extended SQLAlchemy models (`TaskAttachment`, `LeaveRequest` attachment fields, `User` internship period fields), secure disk storage with directory containment checks, IST localization utilities, and FastAPI multipart file upload endpoints.

**Tech Stack:** FastAPI, SQLAlchemy 2.0, Pydantic, Python `zoneinfo`, Pytest.

---

## User Review Required

> [!IMPORTANT]
> Leave application attachments are optional: interns can submit leave with or without an attachment.

> [!NOTE]
> All attendance check-in/out timestamps will now be localized to IST (`Asia/Kolkata`) across all API responses.

---

## Proposed Changes

### 1. Database Models & Migrations

#### [MODIFY] [models.py](file:///d:/download/internhub%20backend/internhub%20backend/models.py)
- Add `TaskAttachment` model (`id`, `task_id`, `user_id`, `comment_id`, `file_name`, `file_path`, `file_size`, `file_type`, `description`, `created_at`).
- Add `attachments` relationship on `Task`.
- Add `attachment_path` and `attachment_name` columns on `LeaveRequest`.
- Add `internship_end_date` and `internship_duration_months` on `User` and `OrganizationMembership`.

#### [NEW] [migrations/20260831_features_2_to_5.py](file:///d:/download/internhub%20backend/internhub%20backend/migrations/20260831_features_2_to_5.py)
- Idempotent migration creating `task_attachments` table and adding columns to `leave_requests`, `users`, and `organization_memberships`.

#### [MODIFY] [migrate_db.py](file:///d:/download/internhub%20backend/internhub%20backend/migrate_db.py)
- Register `migrations.20260831_features_2_to_5`.

---

### 2. Timezone & Helper Utilities

#### [MODIFY] [utils.py](file:///d:/download/internhub%20backend/internhub%20backend/utils.py)
- Add `to_ist(dt: datetime | None) -> datetime | None`.
- Add `isoformat_ist(dt: datetime | None) -> str | None`.
- Add `fmt_time_ist(dt: datetime | None) -> str`.
- Add `get_internship_summary(db: Session, user: User, org_id: int | None = None) -> dict`.
- Add `save_task_attachment(task_id: int, user_id: int, file_name: str, content: bytes, mime_type: str, description: str | None) -> str`.
- Add `save_leave_attachment(leave_id: int, user_id: int, file_name: str, content: bytes) -> str`.

---

### 3. Check-in Time in IST

#### [MODIFY] [routes/api/attendance.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/attendance.py)
- Localize `check_in` and `check_out` representations to IST.

#### [MODIFY] [routes/api/student_attendance.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/student_attendance.py) & [routes/api/dashboard.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/dashboard.py)
- Localize student check-in/out timestamps to IST.

---

### 4. Task Attachments

#### [MODIFY] [routes/api/projects.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/projects.py)
- `POST /api/projects/tasks/{task_id}/attachments`: Upload file against task.
- `GET /api/projects/tasks/{task_id}/attachments`: List attachments.
- `GET /api/projects/tasks/attachments/{attachment_id}/download`: Download/view attachment.
- `DELETE /api/projects/tasks/attachments/{attachment_id}`: Remove attachment.
- `POST /api/projects/tasks/{task_id}/comments`: Support optional attachment with comment.
- `_task_dict`: Include `attachments` list in task response.

---

### 5. Internship Period Visibility

#### [MODIFY] [routes/api/profile.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/profile.py)
- Include `internship_summary` in `GET /api/profile` for interns.

#### [MODIFY] [routes/api/leave.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/leave.py)
- Include `internship_summary` in `GET /api/leave/mine`.

---

### 6. Optional Leave Application Attachment

#### [MODIFY] [routes/api/leave.py](file:///d:/download/internhub%20backend/internhub%20backend/routes/api/leave.py)
- Update `POST /api/leave` to accept optional `attachment: UploadFile = File(None)`.
- Add `GET /api/leave/{leave_id}/attachment` for downloading medical certificate / attachment.
- Update `_leave_dict` to include `attachment_name` and `has_attachment`.

---

## Verification Plan

### Automated Tests
- Create `tests/test_features_2_to_5.py` testing:
  1. `test_checkin_checkout_time_in_ist`: Verify attendance responses format check-in/out in IST.
  2. `test_task_attachment_upload_and_download`: Upload PDF/image attachment to task and verify download.
  3. `test_task_comment_with_attachment`: Add task comment with file attached and verify linkage.
  4. `test_internship_period_visibility`: Verify profile and leave responses return complete internship period summary (start, end, duration, approved leaves, remaining balance).
  5. `test_leave_application_with_optional_attachment`: Apply for leave with attachment and verify download.
  6. `test_leave_application_without_attachment`: Apply for leave without attachment (optional) and verify success.

Run test command:
```bash
pytest tests/test_features_2_to_5.py -v
pytest tests/ -v
```
