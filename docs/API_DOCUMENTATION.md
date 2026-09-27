# InternHub Backend API Documentation

This document describes every HTTP route the backend serves. It was checked against the code and against live
responses from production on 2026-09-27. The interactive reference is generated from the code and is always the
authoritative source for request and response schemas:

| | URL |
|---|---|
| Interactive reference (Scalar) | `/docs` or `/api/docs` |
| OpenAPI schema | `/openapi.json` |
| Local development | `http://127.0.0.1:3001` (`python main.py`) |
| Production | `https://internhub-sas-production-b44c.up.railway.app` |

Swagger UI and ReDoc are not served.

---

## 1. Authentication

**Sign in:** `POST /api/auth/login` with `{"email", "password", "remember"}`.

- The response sets an HttpOnly session cookie `ih_session` and a readable CSRF cookie `ih_csrf`, and returns
  `{"user": {...}, "ok": true}`.
- When the server runs with `AUTH_RETURN_BEARER_TOKEN=true` (production does), the body also contains `"token"` for
  mobile and CLI clients. Send it as `Authorization: Bearer <token>`. Tokens last 8 hours; `remember` only extends
  the cookie (30 days).
- Cookie-authenticated `POST`/`PUT`/`PATCH`/`DELETE` requests must send the `ih_csrf` cookie value in an
  `X-CSRF-Token` header. Bearer-token requests are exempt.
- Sign-in (and public registration) is limited to **10 attempts per 5 minutes per IP**; a successful sign-in resets
  the count. Beyond the limit the API returns `429` with `Retry-After`.
- `POST /api/auth/logout` clears the session. `POST /api/profile/change-password` signs out every other session and
  returns a fresh token for the current one.
- **Forgotten password:** `POST /api/auth/password/forgot {"email"}` always answers `200` with the same message, so it
  cannot reveal which accounts exist. For an active account it e-mails a 6-digit code (through the organization's
  SMTP settings) that is valid for 15 minutes. `POST /api/auth/password/reset {"email", "code", "new_password",
  "confirm_password"}` sets the new password (same rules as change-password), signs out every session and uses up the
  code. A code allows 5 wrong tries; requests share the sign-in rate limit.

**Sign-up paths:**

| Route | Result |
|---|---|
| `POST /api/admin/users`, `POST /api/org/members` | An admin (or a mentor, for interns) creates the account inside their organization. |
| `POST /api/auth/invite/{token}/register` | Intern signs up through an invite link; the account is inactive until an admin or the link's mentor approves it at `POST /api/admin/intern-signup-requests/{user_id}/review` with `{"decision": "approved"}` or `{"decision": "rejected"}`. Approval adds the intern to the link's organization. |
| `POST /api/auth/register` | Public self-registration (`role`: `intern` or `mentor`; mentor accounts wait for approval). The account belongs to **no organization**: it can use only `/api/auth/*`, `/api/profile` and `/api/notifications` until an org admin adds it by e-mail (`POST /api/org/members`) or it joins with an invite link. `organization_name` and `organization_slug` are accepted but ignored. |

**Errors** are JSON `{"detail": "..."}` (validation errors: `{"detail": [{"loc", "msg", "type"}, ...]}`).

| Status | Meaning |
|---|---|
| 401 | Not signed in, or the session/token expired. |
| 403 | Signed in but not allowed (role, CSRF, suspended organization, or no organization yet). |
| 404 | Not found, **including records that belong to another organization**. |
| 409 | Conflict, e.g. already checked in today, duplicate record, overlapping leave. |
| 422 | Invalid input. |

---

## 2. Organizations (multi-tenancy)

- Every signed-in request runs in one organization: the `X-Organization-Id` header if the user is an active member
  of it, otherwise the user's first active membership. A header naming an organization the user doesn't belong to
  is ignored, not honoured.
- Any id that belongs to another organization (in the path or in the body, e.g. `mentor_id`, `project_id`,
  `assigned_to`) is answered with `404` or `422`, exactly as if it did not exist.
- Members of a **suspended or cancelled** organization, and users whose memberships are all inactive, get `403` on
  every authenticated route except logout.
- Organization-wide admin actions (invite regenerate/deactivate, recycle bin, auto-checkout) affect only the
  caller's organization. Audit-log entries and attendance rows are filed under the organization they happen in.
- **Platform admins** (`is_platform_admin`) are not restricted to one organization and are the only users who can
  call `/api/platform/*`, the superadmin dashboards and `POST /api/admin/clear-database`.

---

## 3. Conventions

- **Roles:** `admin`, `mentor`, `intern` (plus platform admins). "Mentor (own interns)" means the mentor may act only
  on interns whose `mentor_id` is them.
- **Dates** are `YYYY-MM-DD`; **timestamps** are ISO 8601 UTC with `Z` unless noted. Attendance times are in IST
  (`Asia/Kolkata`), see section 6.
- **Pagination:** list endpoints take `page` (from 1) and `page_size` (or `per_page` for blogs) and return
  `page`, `page_size`, `total`, `total_pages` next to the list. Most lists are returned under both a named key
  (`statuses`, `requests`, `members`, ...) and `items`.
- **Aliases:** several routes exist under more than one path for older clients; they are marked in the tables.
- **Deletes** of projects, tasks, task comments, users, announcements, blog posts, cohorts, performance reviews and
  standups move the record to the organization's recycle bin (`/api/admin/bin`), where an admin can restore or
  purge it. Project board comments and links are soft-deleted without a bin entry.
- **Uploaded files** (attachments, submissions, leave documents, attendance selfies) are stored on the server's
  persistent volume (`UPLOADS_DIR`, `ATTENDANCE_PHOTOS_DIR`) or Cloudinary for images, and downloaded through the
  API routes below, which apply the same permission checks as the parent record.

---

## 4. Endpoint reference

`Request` lists query parameters, JSON body fields, or multipart `form` fields; `(file)` marks an upload field.
All routes are under the organization rules in section 2.

### Auth & profile

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/auth/invite/{token}` | Public | — |
| POST | `/api/auth/invite/{token}/register` | Public | body: `name`, `email`, `password`, `confirm_password`, `phone`, `department`, `job_title`, `joining_date` |
| POST | `/api/auth/login` | Public | body: `email`, `password`, `remember` |
| POST | `/api/auth/logout` | Any (clears the session) | — |
| GET | `/api/auth/me` | Any signed-in user | — |
| POST | `/api/auth/password/forgot` | Public | body: `email` |
| POST | `/api/auth/password/reset` | Public | body: `email`, `code`, `new_password`, `confirm_password` |
| POST | `/api/auth/register` | Public | body: `name`, `email`, `password`, `confirm_password`, `role`, `phone`, `department`, `job_title`, `joining_date`, `organization_name`, `organization_slug` |
| GET | `/api/profile` | Any signed-in user | — |
| PUT | `/api/profile` | Any signed-in user | body: `bio`, `phone`, `skills` |
| POST | `/api/profile/change-password` | Any signed-in user | body: `current_password`, `new_password`, `confirm_password` |

### Organization

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/org/current` | Any signed-in user | — |
| GET | `/api/org/members` | Admin, Mentor | query: `role`, `search`, `page`, `page_size` |
| POST | `/api/org/members` | Admin; Mentor (interns only) | body: `name`, `email`, `password`, `role`, `department`, `job_title`, `joining_date`, `mentor_id`, `is_paid`, `stipend_amount` |
| PUT | `/api/org/profile` | Admin | body: `name`, `timezone`, `logo_url` |
| PUT | `/api/org/settings` | Admin | body: `shift_start`, `shift_end`, `late_cutoff`, `noon_cutoff`, `checkin_block`, `full_day_hours`, `half_day_hours`, `leave_quota_days`, `advance_leave_days`, `require_attendance_selfie`, `require_attendance_gps`, `auto_checkout_enabled` |
| GET | `/api/org/smtp` | Admin | — |
| PUT | `/api/org/smtp` | Admin | body: `is_enabled`, `host`, `port`, `username`, `password`, `sender_email`, `sender_name`, `encryption`, `notify_welcome`, `notify_leave_request`, `notify_leave_decision`, `notify_assignment_new`, `notify_assignment_submit`, `notify_assignment_grade`, `notify_task_assigned`, `notify_attendance_alert` |
| GET | `/api/org/smtp/logs` | Admin | query: `page`, `page_size`, `email_type`, `status` |
| POST | `/api/org/smtp/test` | Admin | body: `target_email`, `host`, `port`, `username`, `password`, `sender_email`, `sender_name`, `encryption` |

### Users & admin

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/admin/intern-assignments` | Admin, Mentor | — |
| GET | `/api/admin/mentors` | Admin, Mentor | — |
| GET | `/api/admin/users` | Admin; Mentor (own interns) | — |
| POST | `/api/admin/users` | Admin; Mentor (interns only) | body: `name`, `email`, `password`, `role`, `phone`, `department`, `job_title`, `joining_date`, `internship_duration_months`, `mentor_id`, `is_paid`, `stipend_amount` |
| PUT | `/api/admin/users/{user_id}` | Admin; Mentor (own interns) | body: `name`, `email`, `phone`, `department`, `job_title`, `joining_date`, `internship_duration_months`, `mentor_id`, `is_paid`, `stipend_amount` |
| DELETE | `/api/admin/users/{user_id}` | Admin | — |
| POST | `/api/admin/users/{user_id}/role` | Admin | body: `role` |
| POST | `/api/admin/users/{user_id}/toggle` | Admin; Mentor (own interns) | — |
| GET | `/api/users/dropdown` | Any signed-in user | — |
| GET | `/api/users/interns` | Any signed-in user | alias of `/api/users/dropdown` |
| GET | `/api/users/mentors` | Any signed-in user | — |
| GET | `/api/users/{user_id}/leave` | Self, or same-organization Admin/Mentor | — |
| GET | `/api/users/{user_id}/overview` | Self, or same-organization staff | — |

### Invites & sign-up requests

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/admin/intern-signup-requests` | Admin; Mentor (own links) | query: `page`, `page_size`, `search` |
| POST | `/api/admin/intern-signup-requests/{user_id}/review` | Admin; Mentor (own links) | — |
| GET | `/api/admin/invite-link` | Admin; Mentor (own links) | — |
| POST | `/api/admin/invite-link` | Admin; Mentor (own links) | body: `label`, `mentor_id` |
| POST | `/api/admin/invite-link/deactivate` | Admin | — |
| POST | `/api/admin/invite-link/regenerate` | Admin | — |
| DELETE | `/api/admin/invite-link/{link_id}` | Admin; Mentor (own links) | — |

### Masters

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/admin/internship-durations` | Any signed-in user (inactive tiers: Admin only) | query: `page`, `page_size`, `search`, `is_active` |
| POST | `/api/admin/internship-durations` | Admin | body: `title`, `internship_duration`, `duration_months`, `duration_days`, `leaves`, `is_default`, `order_index` |
| GET | `/api/admin/internship-durations/dropdown` | Any signed-in user (inactive tiers: Admin only) | query: `page`, `page_size`, `search`, `is_active`; alias of `/api/admin/internship-durations` |
| PUT | `/api/admin/internship-durations/{duration_id}` | Admin | body: `title`, `internship_duration`, `duration_months`, `duration_days`, `leaves`, `is_default`, `is_active`, `order_index` |
| DELETE | `/api/admin/internship-durations/{duration_id}` | Admin | — |
| GET | `/api/admin/project-statuses` | Admin | query: `page`, `page_size`, `search` |
| POST | `/api/admin/project-statuses` | Admin | body: `name`, `slug`, `color`, `is_default`, `order_index` |
| PUT | `/api/admin/project-statuses/reorder` | Admin | body: `status_ids` |
| PUT | `/api/admin/project-statuses/{status_id}` | Admin | body: `name`, `color`, `is_default`, `order_index` |
| DELETE | `/api/admin/project-statuses/{status_id}` | Admin | — |
| GET | `/api/admin/task-statuses` | Admin | query: `page`, `page_size`, `search`, `category` |
| POST | `/api/admin/task-statuses` | Admin | body: `name`, `slug`, `color`, `status_category`, `is_default`, `order_index` |
| PUT | `/api/admin/task-statuses/reorder` | Admin | body: `status_ids` |
| PUT | `/api/admin/task-statuses/{status_id}` | Admin | body: `name`, `color`, `status_category`, `is_default`, `order_index` |
| DELETE | `/api/admin/task-statuses/{status_id}` | Admin | — |

### Projects & tasks

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/projects` | Any signed-in user (interns: their projects) | — |
| POST | `/api/projects` | Admin, Mentor | body: `name`, `description`, `mentor_id`, `mentor_ids`, `intern_ids`, `start_date`, `end_date`, `status` |
| DELETE | `/api/projects/comments-board/{comment_id}` | Author, project Mentor, Admin | — |
| GET | `/api/projects/interns` | Any signed-in user | — |
| GET | `/api/projects/interns/dropdown` | Any signed-in user | alias of `/api/projects/interns` |
| DELETE | `/api/projects/links/{link_id}` | Submitter, Mentor, Admin | — |
| GET | `/api/projects/mentors` | Any signed-in user | — |
| GET | `/api/projects/mentors/dropdown` | Any signed-in user | alias of `/api/projects/mentors` |
| GET | `/api/projects/project-statuses` | Any signed-in user | — |
| GET | `/api/projects/search` | Any signed-in user | — |
| GET | `/api/projects/statuses` | Any signed-in user | alias of `/api/projects/project-statuses` |
| GET | `/api/projects/task-statuses` | Any signed-in user | query: `project_id` |
| DELETE | `/api/projects/tasks/attachments/{attachment_id}` | Uploader, project Mentor, Admin | — |
| GET | `/api/projects/tasks/attachments/{attachment_id}/download` | Project members | — |
| DELETE | `/api/projects/tasks/comments/{comment_id}` | Comment author, Admin | — |
| PUT | `/api/projects/tasks/{task_id}` | Project staff; Intern (own task) | body: `title`, `description`, `assigned_to`, `due_date`, `priority`, `status` |
| GET | `/api/projects/tasks/{task_id}/attachments` | Project members | — |
| POST | `/api/projects/tasks/{task_id}/attachments` | Project members | form: `file (file)`, `description` |
| GET | `/api/projects/tasks/{task_id}/comments` | Project members | — |
| POST | `/api/projects/tasks/{task_id}/comments` | Project members | form: `body`, `file (file)` |
| PATCH | `/api/projects/tasks/{task_id}/status` | Project members | body: `status` |
| GET | `/api/projects/{project_id}` | Project members, Admin | — |
| PUT | `/api/projects/{project_id}` | Admin, Mentor | body: `name`, `description`, `mentor_id`, `mentor_ids`, `intern_ids`, `start_date`, `end_date`, `status` |
| DELETE | `/api/projects/{project_id}` | Admin, Mentor | — |
| POST | `/api/projects/{project_id}/assign` | Admin, Mentor | body: `user_id` |
| DELETE | `/api/projects/{project_id}/assign/{user_id}` | Admin, Mentor | — |
| GET | `/api/projects/{project_id}/comments-board` | Admin, Mentor, project members | — |
| POST | `/api/projects/{project_id}/comments-board` | Admin, Mentor, project members | body: `body` |
| GET | `/api/projects/{project_id}/export` | Project members, Admin | — |
| GET | `/api/projects/{project_id}/links` | Admin, Mentor, project members | — |
| POST | `/api/projects/{project_id}/links` | Project members | body: `link`, `remark` |
| GET | `/api/projects/{project_id}/task-statuses` | Any signed-in user | — |
| POST | `/api/projects/{project_id}/tasks` | Admin, Mentor; Intern (assigned project, task for self) | body: `title`, `description`, `assigned_to`, `due_date`, `priority`, `status` |
| DELETE | `/api/tasks/{task_id}` | Project staff | alias of `DELETE /api/projects/tasks/{task_id}` |

### Attendance

| Method | Path | Who can call it | Request |
|---|---|---|---|
| POST | `/api/attendance/auto-checkout` | Admin, Mentor | — |
| POST | `/api/attendance/check-in` | Intern | form: `photo (file)`, `lat`, `lng` |
| POST | `/api/attendance/check-out` | Intern | form: `photo (file)`, `lat`, `lng` |
| GET | `/api/attendance/export` | Admin, Mentor | — |
| GET | `/api/attendance/export.csv` | Admin, Mentor | — |
| GET | `/api/attendance/my/export.csv` (+8 aliases) | Any signed-in user | Own attendance as CSV. Aliases: `/api/attendance/export/me`, `/api/attendance/export/my`, `/api/attendance/export/my.csv`, `/api/attendance/me/export`, `/api/attendance/me/export.csv`, `/api/attendance/my-attendance/export`, `/api/attendance/my-attendance/export.csv`, `/api/attendance/my/export` |
| GET | `/api/attendance/history` | Any signed-in user (interns: own) | — |
| POST | `/api/attendance/manual` | Admin; Mentor (own interns) | body: `user_id`, `date`, `check_in`, `check_out`, `status_override`, `reason` |
| GET | `/api/attendance/report` | Admin, Mentor | — |
| GET | `/api/attendance/today` | Any signed-in user | — |
| GET | `/api/attendance/{attendance_id}/photo/{kind}` | Owner, Admin, or the intern's Mentor | — |
| PUT | `/api/attendance/{record_id}` | Admin; Mentor (own interns, no status override) | body: `check_in`, `check_out`, `status_override`, `reason` |
| DELETE | `/api/attendance/{record_id}` | Admin; Mentor (own interns) | — |
| GET | `/api/attendance/{record_id}/audit` | Admin, Mentor | — |

### Student attendance (admin / mentor)

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/admin/attendance/export` | Admin, Mentor | — |
| GET | `/api/admin/attendance/export.csv` | Admin, Mentor | — |
| GET | `/api/admin/attendance/search` | Admin, Mentor | — |
| GET | `/api/admin/attendance/today` | Admin, Mentor | — |
| GET | `/api/admin/students` | Admin, Mentor | — |
| GET | `/api/admin/students/export` | Admin, Mentor | — |
| GET | `/api/admin/students/export.csv` | Admin, Mentor | — |
| GET | `/api/admin/students/overview/search` | Admin, Mentor | — |
| GET | `/api/admin/students/search` | Admin, Mentor | — |
| GET | `/api/admin/students/today` | Admin, Mentor | — |
| GET | `/api/admin/students/{user_id}/attendance` | Admin, Mentor | — |
| GET | `/api/mentor/attendance/export` | Admin, Mentor | — |
| GET | `/api/mentor/attendance/export.csv` | Admin, Mentor | — |
| GET | `/api/mentor/attendance/search` | Admin, Mentor | — |
| GET | `/api/mentor/attendance/today` | Admin, Mentor | — |
| GET | `/api/mentor/students` | Admin, Mentor | — |
| GET | `/api/mentor/students/export` | Admin, Mentor | — |
| GET | `/api/mentor/students/export.csv` | Admin, Mentor | — |
| GET | `/api/mentor/students/overview/search` | Admin, Mentor | — |
| GET | `/api/mentor/students/search` | Admin, Mentor | — |
| GET | `/api/mentor/students/today` | Admin, Mentor | — |
| GET | `/api/mentor/students/{user_id}/attendance` | Admin, Mentor | — |

### Leave

| Method | Path | Who can call it | Request |
|---|---|---|---|
| POST | `/api/leave` | Intern | form: `start_date`, `end_date`, `reason`, `leave_type`, `attachment (file)` |
| GET | `/api/leave/balance` | Intern | — |
| GET | `/api/leave/manage` | Admin, Mentor | — |
| GET | `/api/leave/mine` | Intern | — |
| POST | `/api/leave/review/{leave_id}` | Admin; Mentor (own interns) | body: `decision`, `comment` |
| PUT | `/api/leave/review/{leave_id}` | Admin; Mentor (own interns) | body: `decision`, `comment` |
| GET | `/api/leave/{leave_id}/attachment` | Applicant, Admin, or any Mentor in the organization | — |
| POST | `/api/leave/{leave_id}/review` | Admin; Mentor (own interns) | body: `decision`, `comment` |
| PUT | `/api/leave/{leave_id}/review` | Admin; Mentor (own interns) | body: `decision`, `comment` |

### Assignments

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/assignments` | Any signed-in user (interns: assigned to them) | query: `status`, `project_id`, `cohort_id`, `assigned_to_user_id`, `search`, `page`, `page_size` |
| POST | `/api/assignments` | Admin, Mentor | body: `title`, `description`, `project_id`, `cohort_id`, `assigned_to_user_id`, `due_date`, `max_score`, `status` |
| GET | `/api/assignments/` | Any signed-in user (interns: assigned to them) | query: `status`, `project_id`, `cohort_id`, `assigned_to_user_id`, `search`, `page`, `page_size`; alias of `/api/assignments` |
| POST | `/api/assignments/` | Admin, Mentor | body: `title`, `description`, `project_id`, `cohort_id`, `assigned_to_user_id`, `due_date`, `max_score`, `status`; alias of `/api/assignments` |
| GET | `/api/assignments/submissions/{submission_id}/file` | Admin, Mentor, or the submitting intern | — |
| POST | `/api/assignments/submissions/{submission_id}/review` | Admin, Mentor | body: `score`, `feedback`, `status` |
| PUT | `/api/assignments/submissions/{submission_id}/review` | Admin, Mentor | body: `score`, `feedback`, `status` |
| GET | `/api/assignments/{assignment_id}` | Any signed-in user | — |
| PUT | `/api/assignments/{assignment_id}` | Admin, Mentor | body: `title`, `description`, `project_id`, `cohort_id`, `assigned_to_user_id`, `due_date`, `max_score`, `status` |
| DELETE | `/api/assignments/{assignment_id}` | Admin, Mentor | — |
| GET | `/api/assignments/{assignment_id}/attachment` | Any signed-in user | — |
| POST | `/api/assignments/{assignment_id}/attachment` | Admin, Mentor | form: `file (file)` |
| GET | `/api/assignments/{assignment_id}/submissions` | Admin, Mentor | query: `status`, `page`, `page_size` |
| POST | `/api/assignments/{assignment_id}/submit` | Intern | form: `submission_text`, `github_url`, `file (file)` |

### Cohorts

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/cohorts` | Any signed-in user (interns: their cohorts) | — |
| POST | `/api/cohorts` | Admin, Mentor | body: `name`, `description`, `start_date`, `end_date` |
| GET | `/api/cohorts/{cohort_id}` | Any signed-in user (interns: their cohorts) | — |
| PUT | `/api/cohorts/{cohort_id}` | Admin; Mentor (cohorts they created) | body: `name`, `description`, `start_date`, `end_date` |
| DELETE | `/api/cohorts/{cohort_id}` | Admin; Mentor (cohorts they created) | — |
| POST | `/api/cohorts/{cohort_id}/members` | Admin; Mentor (cohorts they created) | body: `user_id` |
| DELETE | `/api/cohorts/{cohort_id}/members/{user_id}` | Admin, Mentor | — |

### Announcements

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/announcements` | Any signed-in user (interns: org-wide + their projects) | — |
| POST | `/api/announcements` | Admin, Mentor | body: `title`, `body`, `is_pinned`, `project_id` |
| PUT | `/api/announcements/{ann_id}` | Admin; Mentor (own posts) | body: `title`, `body`, `is_pinned` |
| DELETE | `/api/announcements/{ann_id}` | Admin; Mentor (own posts) | — |

### Standups

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/standup` | Any signed-in user (interns: own; mentors: their interns) | query: `from`, `to`, `user_id`, `mood`, `search`, `page`, `page_size` |
| POST | `/api/standup` | Any signed-in user (interns: today only) | body: `date`, `did`, `plan`, `blockers`, `mood` |
| GET | `/api/standup/today` | Any signed-in user | — |
| PUT | `/api/standup/{log_id}` | Author, Admin | body: `did`, `plan`, `blockers`, `mood` |
| DELETE | `/api/standup/{log_id}` | Author, Admin | — |

### Performance reviews

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/reviews` | Any signed-in user (interns: their own) | — |
| POST | `/api/reviews` | Admin, Mentor | body: `intern_id`, `project_id`, `period`, `rating`, `technical_rating`, `communication_rating`, `initiative_rating`, `feedback`, `strengths`, `improvements` |
| GET | `/api/reviews/{review_id}` | Admin, Mentor; Intern (own review) | — |
| PUT | `/api/reviews/{review_id}` | Admin; reviewing Mentor | body: `rating`, `technical_rating`, `communication_rating`, `initiative_rating`, `feedback`, `strengths`, `improvements` |
| DELETE | `/api/reviews/{review_id}` | Admin; reviewing Mentor | — |

### Dashboards

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/admin/dashboard` | Admin | — |
| GET | `/api/admin/dashboard` | Admin | — |
| GET | `/api/dashboard` | Any signed-in user (response depends on role) | — |
| GET | `/api/dashboard/admin` | Admin | — |
| GET | `/api/dashboard/attendance-chart` | Any signed-in user (scoped by role) | — |
| GET | `/api/dashboard/intern` | Intern | — |
| GET | `/api/dashboard/mentor` | Mentor | — |
| GET | `/api/dashboard/open-tasks` | Any signed-in user (scoped by role) | — |
| GET | `/api/dashboard/present-today` | Any signed-in user (scoped by role) | — |
| GET | `/api/intern/dashboard` | Intern | — |
| GET | `/api/mentor/dashboard` | Mentor | — |
| GET | `/intern/dashboard` | Intern | — |
| GET | `/mentor/dashboard` | Mentor | — |

### Notifications

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/notifications` | Any signed-in user | — |
| POST | `/api/notifications/mark-read` | Any signed-in user | — |
| GET | `/api/notifications/stream` | Any signed-in user | — |
| GET | `/api/notifications/unread-count` | Any signed-in user | — |
| DELETE | `/api/notifications/{notif_id}` | Any signed-in user | — |

### Search & audit

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/audit` | Admin; Mentor/Intern (activity they can see) | query: `action`, `actor_id`, `project_id`, `date`, `search`, `page`, `page_size` |
| GET | `/api/search` | Any signed-in user (scoped by role) | — |

### Recycle bin & maintenance

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/admin/bin` | Admin | — |
| DELETE | `/api/admin/bin` | Admin | — |
| DELETE | `/api/admin/bin/{bin_id}` | Admin | — |
| POST | `/api/admin/bin/{bin_id}/restore` | Admin | — |
| POST | `/api/admin/clear-database` | Platform admin | body: `password` |

### Uploads

| Method | Path | Who can call it | Request |
|---|---|---|---|
| POST | `/api/upload/avatar` | Any signed-in user | form: `file (file)` |
| POST | `/api/upload/image` | Any signed-in user | form: `file (file)`, `folder` |
| POST | `/api/upload/org-logo` | Admin | form: `file (file)` |
| GET | `/api/upload/status` | Any signed-in user | — |

### Blogs

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/blogs` | Public | query: `page`, `per_page`, `tag`, `search` |
| POST | `/api/blogs` | Admin | body: `title`, `content`, `excerpt`, `cover_image_url`, `tags`, `status`, `slug` |
| GET | `/api/blogs/admin/all` | Admin | query: `status`, `search`, `page`, `per_page` |
| PUT | `/api/blogs/{post_id}` | Admin | body: `title`, `content`, `excerpt`, `cover_image_url`, `tags`, `status`, `slug` |
| DELETE | `/api/blogs/{post_id}` | Admin | — |
| GET | `/api/blogs/{slug}` | Public (drafts: Admin) | — |

### Public

| Method | Path | Who can call it | Request |
|---|---|---|---|
| POST | `/api/leads` | Public | body: `name`, `email`, `phone`, `company`, `role`, `cohort_size`, `message`, `source`, `website` |

### Platform (super admin)

| Method | Path | Who can call it | Request |
|---|---|---|---|
| GET | `/api/dashboard/superadmin` | Platform admin | — |
| GET | `/api/platform/leads` | Platform admin | query: `page`, `page_size`, `search`, `status` |
| GET | `/api/platform/metrics` | Platform admin | — |
| GET | `/api/platform/organizations` | Platform admin | query: `page`, `page_size`, `search` |
| POST | `/api/platform/organizations` | Platform admin | body: `name`, `slug`, `type`, `timezone`, `admin_name`, `admin_email`, `admin_password` |
| GET | `/api/platform/organizations/{org_id}` | Platform admin | — |
| PUT | `/api/platform/organizations/{org_id}/status` | Platform admin | body: `status` |
| GET | `/api/superadmin/dashboard` | Platform admin | — |
| GET | `/superadmin/dashboard` | Platform admin | — |

---

## 5. Task statuses (workflow buckets)

Each organization has its own ordered set of task statuses. `slug` is the value stored in a task's `status`.

### 5.1 List (admin master)
`GET /api/admin/task-statuses?page=1&page_size=20&search=&category=` (Admin)

```json
{
  "statuses": [
    {
      "id": 17, "organization_id": 5, "name": "To Do", "slug": "todo", "color": "#94A3B8",
      "order_index": 0, "status_category": "todo", "is_default": true, "is_system": true,
      "created_at": "2026-09-26T22:08:02", "updated_at": "2026-09-26T23:32:41", "task_count": 3
    }
  ],
  "items": ["... same list ..."],
  "total": 4, "page": 1, "page_size": 20, "total_pages": 1
}
```

New organizations start with `todo`, `in_progress`, `review` and `done`. `status_category` is one of `todo`,
`in_progress`, `done`.

### 5.2 Create / update / reorder / delete (Admin)

| Route | Body |
|---|---|
| `POST /api/admin/task-statuses` | `{"name": "QA & Testing", "slug": "testing", "color": "#8C9A33", "status_category": "in_progress", "is_default": false, "order_index": 4}`. `slug` is optional (derived from `name`); a duplicate slug returns `422`. |
| `PUT /api/admin/task-statuses/{status_id}` | Any of `name`, `color`, `status_category`, `is_default`, `order_index`. |
| `PUT /api/admin/task-statuses/reorder` | `{"status_ids": [17, 18, 19, 20]}` |
| `DELETE /api/admin/task-statuses/{status_id}` | Returns `422` while tasks still use the status. Deleting the default moves the default to another status. |

Project statuses (`/api/admin/project-statuses`) work the same way without `status_category`.

### 5.3 Statuses for boards and forms (any signed-in user)
`GET /api/projects/task-statuses?project_id=` or `GET /api/projects/{project_id}/task-statuses` returns
`{"statuses": [...]}` with the same fields as above minus `task_count`, for the project's organization.

---

## 6. Tasks, comments and attachments

### 6.1 Create a task
`POST /api/projects/{project_id}/tasks`

```json
{"title": "Build Auth API", "description": "Implement JWT endpoints", "assigned_to": 17,
 "due_date": "2026-10-15", "priority": "high", "status": "todo"}
```

- `priority`: `low`, `medium`, `high`. `status`: any slug from section 5; omitted means the organization's
  default status. `due_date` is also accepted as `deadline`.
- Interns can create tasks only in projects they are assigned to, and the task is assigned to themselves.
- `assigned_to` must be a member of the project's organization (`422 Assignee not found.` otherwise).

`PATCH /api/projects/tasks/{task_id}/status` with `{"status": "in_progress"}` moves a task; interns may move tasks
of projects they belong to.

### 6.2 Upload an attachment
`POST /api/projects/tasks/{task_id}/attachments` — `multipart/form-data` with `file` (one file, required) and
`description` (optional). Project members only. Returns the attachment object:

```json
{
  "id": 3, "task_id": 3, "user_id": 13, "user_name": "Anand Apte", "comment_id": null,
  "file_name": "gtfs-import-checklist.pdf", "file_size": 310, "file_type": "application/pdf",
  "description": "GTFS import checklist",
  "download_url": "/api/projects/tasks/attachments/3/download", "created_at": "2026-09-26T23:27:46"
}
```

- `GET /api/projects/tasks/{task_id}/attachments` returns `{"task_id": 3, "attachments": [...], "total": 1}`.
- `GET /api/projects/tasks/attachments/{attachment_id}/download` streams the file
  (`application/octet-stream`, `Content-Disposition: attachment; filename="..."`).
- `DELETE /api/projects/tasks/attachments/{attachment_id}`: the uploader, a mentor of the project, or an admin.

### 6.3 Comment on a task
`POST /api/projects/tasks/{task_id}/comments` accepts JSON `{"body": "..."}` or `multipart/form-data` with `body`
and/or `file` (at least one is required). A file becomes an attachment linked to the comment (`comment_id`).
`GET /api/projects/tasks/{task_id}/comments` returns the comment list (oldest first, `?limit=` up to 500).

---

## 7. Attendance

### 7.1 Check in / check out (interns)
`POST /api/attendance/check-in` and `POST /api/attendance/check-out` — `multipart/form-data`:

| Field | Required | Notes |
|---|---|---|
| `photo` | yes | Selfie image. |
| `lat`, `lng` | yes | Location; reverse-geocoded to an address. |

- `photo`, `lat` and `lng` are required on every call, even when the organization's
  `require_attendance_selfie` / `require_attendance_gps` settings are off.
- Check-in returns `409` when already checked in today and `422` after the check-in cut-off (8 PM).

### 7.2 Record format
`GET /api/attendance/history`, `/today` and `/report` return records with times in IST:

```json
{
  "id": 6, "user_id": 17, "user_name": "Aarav Deshmukh", "date": "2026-09-25",
  "check_in": "10:05", "check_in_time": "10:05 AM", "check_in_dt": "2026-09-25T10:05:00+05:30",
  "check_out": "18:40", "check_out_time": "6:40 PM", "check_out_dt": "2026-09-25T18:40:00+05:30",
  "hours_worked": 8.58, "status": "present", "notes": null, "checkout_source": "manual",
  "checkout_missed": false, "check_in_location": null, "check_out_location": null,
  "check_in_photo_url": null, "check_out_photo_url": null
}
```

- `status`: `present`, `late`, `half_day`, `absent`, `on_leave`, `excused`.
- `GET /api/attendance/today` returns `{"record": <record or null>, "today": "2026-09-27"}`.
- `GET /api/attendance/history` returns `{"records", "page", "total_pages", "total", "month"}`.
- `GET /api/attendance/report` (Admin, Mentor) adds `interns`, `monthly_summary` and `filters`.

### 7.3 Manual entries and corrections (Admin; Mentor for own interns)
- `POST /api/attendance/manual`:
  `{"user_id": 18, "date": "2026-09-02", "check_in": "09:40", "check_out": "18:10", "reason": "Forgot to punch"}`.
  Times are `HH:MM`; `status_override` is admin-only. Returns `409` if a record exists for that day.
- `PUT /api/attendance/{record_id}` edits `check_in`, `check_out`, `status_override` (admin only) with a `reason`.
- `DELETE /api/attendance/{record_id}` requires a JSON body `{"reason": "..."}`.
- `GET /api/attendance/{record_id}/audit` lists the edit history.
- `POST /api/attendance/auto-checkout` closes the organization's open sessions from earlier days as missed
  check-outs.

---

## 8. Internship period summary

`internship_summary` is included in `GET /api/profile`, `GET /api/leave/mine` and `GET /api/dashboard/intern`:

```json
{
  "start_date": "2026-08-13", "end_date": "2027-02-13",
  "duration_months": 6, "duration_label": "6 Months",
  "approved_leaves": 1, "leaves_used": 1, "pending_leaves": 1,
  "remaining_leave_balance": 9, "total_leave_quota": 10, "days_remaining": 139,
  "summary_text": "Internship Period – 6 Months | Approved Leaves – 1 Days",
  "leave_balance": {
    "used": 1, "deducted_used": 0, "future_approved": 1, "attended_saved": 0,
    "pending": 1, "quota": 10, "remaining": 9, "available_after_pending": 8
  }
}
```

`GET /api/leave/balance` returns the `leave_balance` object on its own.

---

## 9. Leave

### 9.1 Apply (interns)
`POST /api/leave` — `multipart/form-data` (or JSON without the file):

| Field | Required | Notes |
|---|---|---|
| `start_date`, `end_date` | yes | `YYYY-MM-DD`; the start must be at least one day ahead and the range must contain a working day. |
| `reason` | yes | At least 3 characters. |
| `leave_type` | no | `casual` (default), `sick`, `earned` or `comp`; unknown values become `casual`. |
| `attachment` | no | Supporting document, e.g. a medical certificate. |

Overlapping pending/approved requests return `409`; requesting more days than the remaining balance returns `422`.
The request is returned as:

```json
{
  "id": 8, "user_id": 18, "user_name": "Sakshi Patil", "start_date": "2026-10-20", "end_date": "2026-10-20",
  "days": 1, "reason": "Medical check-up at Sassoon hospital", "leave_type": "sick", "status": "pending",
  "reviewed_by": null, "reviewer_name": null, "reviewed_at": null,
  "has_attachment": true, "attachment_name": "note.pdf", "attachment_url": "/api/leave/8/attachment",
  "created_at": "2026-09-26T22:11:22.000000Z"
}
```

The intern's mentor and the organization's admins are notified.

### 9.2 Review (Admin; Mentor for own interns)
`POST /api/leave/{leave_id}/review` (also `PUT`, and `/api/leave/review/{leave_id}`) with
`{"decision": "approve" | "reject", "comment": "..."}` (`approved`/`rejected` are accepted too). Approval marks the
leave days as `on_leave` in attendance. The comment is stored and returned as `review_comment` on the request.

### 9.3 Lists and documents
- `GET /api/leave/mine` returns `requests`, `pending_requests`, `approved_requests`, `rejected_requests`,
  `summary` (`total`, `pending`, `approved`, `rejected`, `days_taken`, `days_pending`), `balance` and
  `internship_summary`.
- `GET /api/leave/manage` (Admin, Mentor) lists requests to review.
- `GET /api/leave/{leave_id}/attachment` streams the supporting document to the applicant, an admin, or any mentor
  of the organization.
