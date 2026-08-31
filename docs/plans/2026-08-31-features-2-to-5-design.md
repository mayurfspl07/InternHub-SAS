# Design Document: Check-in Time (IST), Task Attachments, Internship Period Visibility & Leave Attachments

> **Document ID:** `2026-08-31-features-2-to-5-design.md`  
> **Date:** 2026-08-31  
> **Status:** Approved Design  

---

## 1. Feature Specifications

### 1.1 Check-in / Check-out Time in IST
- Convert check-in / check-out times into Indian Standard Time (IST, `Asia/Kolkata`, `UTC+05:30`) across all attendance, dashboard, student listing, and user endpoints.
- Return both readable time string (`10:30 AM` / `10:30`) and ISO 8601 with `+05:30` offset.

### 1.2 Task Attachments
- Enable interns and mentors to attach documents, screenshots, and reports against tasks.
- Support uploading attachments directly, during task commenting, or when updating status.
- Link attachments to the specific task with metadata (uploader, filename, size, type, timestamp) and provide secure download endpoints for mentor review.

### 1.3 Internship Period & Leave Visibility
- Provide interns with complete visibility of their internship details:
  - Start Date (`joining_date`)
  - End Date (`internship_end_date`)
  - Duration (e.g. `3 Months`)
  - Approved Leaves / Leaves Used
  - Pending Leaves
  - Remaining Leave Balance
  - Total Leave Quota
- Expose `internship_summary` in `/api/profile`, `/api/leave/mine`, and dashboard responses.

### 1.4 Optional Leave Application Attachments
- Allow interns to optionally attach medical certificates or supporting documents when submitting a leave request (`POST /api/leave`).
- Provide secure download endpoint `/api/leave/{id}/attachment` for interns, mentors, and admins.

---

## 2. Data Models & Database Changes

### `TaskAttachment` Table
- `id`: Integer primary key
- `task_id`: Integer, ForeignKey(`tasks.id`, ondelete="CASCADE"), indexed
- `user_id`: Integer, ForeignKey(`users.id`, ondelete="SET NULL"), nullable
- `comment_id`: Integer, ForeignKey(`task_comments.id`, ondelete="SET NULL"), nullable
- `file_name`: String(255)
- `file_path`: String(500)
- `file_size`: Integer
- `file_type`: String(100)
- `description`: Text, nullable
- `created_at`: DateTime, UTC

### `LeaveRequest` Additions
- `attachment_path`: String(500), nullable
- `attachment_name`: String(255), nullable

### `User` & `OrganizationMembership` Additions
- `internship_end_date`: Date, nullable
- `internship_duration_months`: Integer, nullable, default 3
