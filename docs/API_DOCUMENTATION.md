# InternHub Backend API Documentation

> **Interactive API Docs:**
> - Swagger UI: `http://127.0.0.1:3001/api/docs`
> - ReDoc: `http://127.0.0.1:3001/api/redoc`

---

## 1. Task Status / Bucket Master APIs (`/api/admin/task-statuses`)

Manage custom workflow buckets per organization (e.g. *Started → In Progress → Review → Completed*).

### 1.1 List Status Buckets
- **Method & Route:** `GET /api/admin/task-statuses`
- **Auth:** Admin / Super Admin / Org Admin
- **Response (200 OK):**
```json
[
  {
    "id": 1,
    "organization_id": 1,
    "name": "To Do",
    "slug": "todo",
    "color": "#94A3B8",
    "order_index": 0,
    "status_category": "todo",
    "is_default": true,
    "is_system": true,
    "task_count": 5
  },
  {
    "id": 2,
    "organization_id": 1,
    "name": "In Progress",
    "slug": "in_progress",
    "color": "#3B82F6",
    "order_index": 1,
    "status_category": "in_progress",
    "is_default": false,
    "is_system": true,
    "task_count": 3
  },
  {
    "id": 3,
    "organization_id": 1,
    "name": "Review",
    "slug": "review",
    "color": "#F59E0B",
    "order_index": 2,
    "status_category": "in_progress",
    "is_default": false,
    "is_system": false,
    "task_count": 2
  },
  {
    "id": 4,
    "organization_id": 1,
    "name": "Completed",
    "slug": "done",
    "color": "#10B981",
    "order_index": 3,
    "status_category": "done",
    "is_default": false,
    "is_system": true,
    "task_count": 12
  }
]
```

### 1.2 Create Status Bucket
- **Method & Route:** `POST /api/admin/task-statuses`
- **Auth:** Admin
- **Request Body:**
```json
{
  "name": "QA & Testing",
  "slug": "testing",
  "color": "#8B5CF6",
  "status_category": "in_progress",
  "is_default": false
}
```

### 1.3 Update Status Bucket
- **Method & Route:** `PUT /api/admin/task-statuses/{id}`
- **Auth:** Admin
- **Request Body:**
```json
{
  "name": "Code Review",
  "color": "#F59E0B",
  "status_category": "in_progress",
  "is_default": false
}
```

### 1.4 Reorder Status Buckets
- **Method & Route:** `PUT /api/admin/task-statuses/reorder`
- **Auth:** Admin
- **Request Body:**
```json
{
  "status_ids": [1, 2, 3, 4]
}
```

### 1.5 Delete Status Bucket
- **Method & Route:** `DELETE /api/admin/task-statuses/{id}`
- **Auth:** Admin
- **Safety Guard:** Returns `422 Unprocessable Entity` if active tasks are currently assigned to this status.

---

## 2. Dynamic Task Statuses for Projects (`/api/projects/*`)

### 2.1 Get Dynamic Status List for Organization / Project
- **Method & Route:** `GET /api/projects/task-statuses` or `GET /api/projects/{project_id}/task-statuses`
- **Auth:** Authenticated User
- **Response:** List of status buckets with slugs, colors, order, and categories for Kanban board columns and task forms.

### 2.2 Create Task (Dynamic Default Status)
- **Method & Route:** `POST /api/projects/{project_id}/tasks`
- **Request Body:**
```json
{
  "title": "Build Auth API",
  "description": "Implement JWT endpoints",
  "assigned_to": 3,
  "due_date": "2026-09-15",
  "priority": "high",
  "status": "todo"
}
```
*(If `status` is omitted, automatically assigns the organization's default status bucket).*

---

## 3. Task Attachments APIs (`/api/projects/*`)

### 3.1 Upload Attachment Against Task
- **Method & Route:** `POST /api/projects/tasks/{task_id}/attachments`
- **Content-Type:** `multipart/form-data`
- **Form Fields:**
  - `files`: Single or multiple files (UploadFile)
  - `description`: Optional text description
- **Response (200 OK):**
```json
{
  "ok": true,
  "attachments": [
    {
      "id": 10,
      "task_id": 42,
      "user_id": 3,
      "user_name": "Intern Name",
      "file_name": "qa_report.pdf",
      "file_path": "tasks/42/20260831_180000_qa_report.pdf",
      "file_size": 245120,
      "file_type": "application/pdf",
      "description": "Final QA Test Report",
      "download_url": "/api/projects/tasks/attachments/10/download",
      "created_at": "2026-08-31T18:00:00Z"
    }
  ]
}
```

### 3.2 List Task Attachments
- **Method & Route:** `GET /api/projects/tasks/{task_id}/attachments`
- **Response:** List of all files attached to the task with download URLs.

### 3.3 Download Task Attachment
- **Method & Route:** `GET /api/projects/tasks/attachments/{attachment_id}/download`
- **Response:** Binary file stream (`FileResponse`) with Content-Disposition headers.

### 3.4 Delete Task Attachment
- **Method & Route:** `DELETE /api/projects/tasks/attachments/{attachment_id}`
- **Auth:** Uploader, Assigned Mentor, or Admin.

### 3.5 Post Task Comment with Attachment
- **Method & Route:** `POST /api/projects/tasks/{task_id}/comments`
- **Content-Type:** `multipart/form-data` or `application/json`
- **Form Fields:**
  - `body`: Text comment (optional if file is present)
  - `file`: Supporting document/screenshot (optional)
- **Response:** Comment object with linked attachment metadata.

---

## 4. Attendance APIs (IST / Asia/Kolkata Formatting)

- **Endpoints:**
  - `GET /api/attendance/history`
  - `GET /api/attendance/today`
  - `GET /api/attendance/report`
  - `GET /api/attendance/export.csv`
  - `POST /api/attendance/checkin`
  - `POST /api/attendance/checkout`
- **Timestamps Serialized:**
  - `check_in`: Time string formatted in IST (e.g. `"10:00"`)
  - `check_in_time`: 12-hour formatted time in IST (e.g. `"10:00 AM"`)
  - `check_in_dt`: Full ISO 8601 string with IST offset (e.g. `"2026-08-31T10:00:00+05:30"`)
  - `check_out`: Time string formatted in IST (e.g. `"19:00"`)
  - `check_out_time`: 12-hour formatted time in IST (e.g. `"07:00 PM"`)
  - `check_out_dt`: Full ISO 8601 string with IST offset (e.g. `"2026-08-31T19:00:00+05:30"`)

---

## 5. Internship Period Visibility

Included in:
- `GET /api/profile`
- `GET /api/leave/mine`
- `GET /api/dashboard/intern`

### Response Payload Structure (`internship_summary`):
```json
{
  "start_date": "2026-06-01",
  "end_date": "2026-08-31",
  "duration_months": 3,
  "duration_label": "3 Months",
  "approved_leaves": 6,
  "leaves_used": 6,
  "pending_leaves": 0,
  "remaining_leave_balance": 9,
  "total_leave_quota": 15,
  "days_remaining": 0,
  "summary_text": "Internship Period – 3 Months | Approved Leaves – 6 Days",
  "leave_balance": {
    "quota": 15,
    "used": 6,
    "pending": 0,
    "remaining": 9,
    "remaining_days": 9
  }
}
```

---

## 6. Leave Application Attachment APIs (`/api/leave/*`)

### 6.1 Apply for Leave with Optional Attachment
- **Method & Route:** `POST /api/leave`
- **Content-Type:** `multipart/form-data` or `application/json`
- **Form Fields:**
  - `start_date`: Start date (`YYYY-MM-DD`, required)
  - `end_date`: End date (`YYYY-MM-DD`, required)
  - `reason`: Reason text (min 3 chars, required)
  - `leave_type`: `casual` or `sick` (defaults to `casual`)
  - `attachment`: Supporting document / medical certificate (UploadFile, **optional**)
- **Response (200 OK):**
```json
{
  "id": 14,
  "user_id": 5,
  "user_name": "Intern Name",
  "start_date": "2026-09-10",
  "end_date": "2026-09-11",
  "days": 2,
  "reason": "Doctor advised rest",
  "leave_type": "sick",
  "status": "pending",
  "reviewed_by": null,
  "reviewer_name": null,
  "reviewed_at": null,
  "has_attachment": true,
  "attachment_name": "medical_cert.pdf",
  "attachment_url": "/api/leave/14/attachment",
  "created_at": "2026-08-31T18:00:00Z"
}
```

### 6.2 Download Leave Supporting Document
- **Method & Route:** `GET /api/leave/{leave_id}/attachment`
- **Auth:** Applicant intern, assigned mentor, or admin.
- **Response:** Binary file stream (`FileResponse`).
