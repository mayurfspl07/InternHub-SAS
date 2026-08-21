# InternHub — Product Understanding Document (Reverse-Engineered from Codebase)

> **Document Type:** Reverse-Engineered Product Architecture & Functional Specification  
> **Source of Truth:** InternHub Backend Codebase (`c:\Users\satya\Downloads\internhub backend\internhub backend`)  
> **Rule Enforcement:** Every role, feature, API, model, status, workflow, and rule in this document is extracted strictly from the implemented code. No features, roles, or multi-tenant structures are assumed. If a capability cannot be confirmed from code, it is explicitly noted as **Not confirmed from current codebase**.

---

## Table of Contents
1. [Executive Product Summary](#1-executive-product-summary)
2. [Codebase Architecture & Technology Inventory](#2-codebase-architecture--technology-inventory)
3. [Actual Roles Found in Code](#3-actual-roles-found-in-code)
4. [Role Permission Matrix](#4-role-permission-matrix)
5. [Actual Modules Discovered](#5-actual-modules-discovered)
6. [Complete Feature Inventory](#6-complete-feature-inventory)
7. [Frontend Screen & Client Route Inventory](#7-frontend-screen--client-route-inventory)
8. [Complete API Inventory (62 Endpoints)](#8-complete-api-inventory)
9. [Database Entity & Schema Map (20 ORM Models)](#9-database-entity--schema-map)
10. [Role-Wise Functionality & Access Bounds](#10-role-wise-functionality--access-bounds)
11. [Feature-Wise Workflows](#11-feature-wise-workflows)
12. [Status Lifecycles & State Transitions](#12-status-lifecycles--state-transitions)
13. [Authentication, Session & Authorization Architecture](#13-authentication-session--authorization-architecture)
14. [Notification Engine](#14-notification-engine)
15. [Scheduled & Automated Jobs (APScheduler)](#15-scheduled--automated-jobs)
16. [Audit Logging & Activity Tracking](#16-audit-logging--activity-tracking)
17. [Soft Delete & Recycle Bin Lifecycle](#17-soft-delete--recycle-bin-lifecycle)
18. [Multi-Tenancy Current State Analysis](#18-multi-tenancy-current-state-analysis)
19. [Frontend ↔ API ↔ Database Traceability](#19-frontend--api--database-traceability)
20. [Complete Role-Wise User Journeys](#20-complete-role-wise-user-journeys)
21. [Feature Interaction Map](#21-feature-interaction-map)
22. [Feature Completeness Classification Matrix](#22-feature-completeness-classification-matrix)
23. [Unused, Dead, or Disconnected Code](#23-unused-dead-or-disconnected-code)
24. [Missing or Incomplete Flows](#24-missing-or-incomplete-flows)
25. [Technical & Architectural Risks](#25-technical--architectural-risks)
26. [Final Consolidated Product Feature List](#26-final-consolidated-product-feature-list)

---

## 1. Executive Product Summary

**InternHub** is a single-workspace operations and intern lifecycle management backend built on **FastAPI (Python 3.9+)**, **SQLAlchemy ORM**, and **MySQL/MariaDB**, configured to host and serve a companion single-page client application (React/Vite).

Based strictly on the codebase implementation, InternHub automates five core operational domains for organizations managing intern cohorts:

1. **Intern Lifecycle & Onboarding:** Self-service registration via shareable invite tokens, pending approval gates, mentor matching, cohort grouping, role assignment, and administrative profile management.
2. **Shift Attendance with Geo-Verification & Selfies:** Strict daily attendance tracking (10:00 AM – 7:00 PM shift, cutoff rules at 10:30 AM, 12:00 PM, and 8:00 PM block) featuring client-captured geolocation (reverse-geocoded via OpenStreetMap Nominatim), mandatory selfie photo uploads, auto-checkout at midnight for missed checkouts, mentor/admin corrections with mandatory change audit trails, and CSV export.
3. **Project Management & Collaboration:** Multi-mentor project assignments, intern staffing, task assignment with priority/deadlines, Kanban/drag-drop status updates (`todo`, `in_progress`, `testing`, `completed`), 100-character task and project comment threads, shared document links with URL validation, and full JSON project bundle exports.
4. **Leave Management & Quota Tracking:** 15-day annual casual leave quota, business-day duration calculation (excluding weekends), advance request enforcement (≥1 day), overlap conflict prevention, mentor/admin approval workflows, and automated synchronization of approved leave days into attendance records with `on_leave` status.
5. **Operational Governance & Resilience:** Daily standup submissions (`did`, `plan`, `blockers`, `mood`), performance reviews with multidimensional ratings (1–5 scale), targeted broadcast announcements, scoped in-app notifications, persistent disk + database audit logging, and a 15-day soft-delete **Recycle Bin** with snapshot serialization, admin restoration, and daily background purge.

---

## 2. Codebase Architecture & Technology Inventory

### 2.1 Backend Directory & File Layout
```
internhub backend/
├── main.py                     # FastAPI application factory, middleware, APScheduler, lifespan, static/SPA hosting
├── config.py                   # Application settings (MySQL URLs, shift cutoffs, token TTL, CORS, paths)
├── database.py                 # SQLAlchemy engine, connection pooling, SessionLocal factory, get_db dependency
├── dependencies.py             # Auth verification, cookie/bearer token extractors, role guards, CSRF validation
├── models.py                   # 20 SQLAlchemy ORM models, status constants, UserRole enum
├── recycle_bin.py              # Soft-delete, snapshot JSON generation, entity restore, permanent purge
├── utils.py                    # Attendance calculations, streak counter, leave balance, audit logging, notifications
├── attendance_photos.py        # Disk-based attendance selfie persistence and safe path resolver
├── geocoding.py                # Reverse-geocoding via OpenStreetMap Nominatim REST API
├── log_files.py                # File handlers for logs/activity.log (JSON lines) and logs/terminal.log
├── migrate_db.py               # Startup schema sync (table creation, missing column additions, migration triggers)
├── init_db.py                  # Standalone CLI script to create database and tables
├── seed.py                     # Standalone CLI demo seeder (10 mentors, 100 interns, 5 projects, cohorts, reviews)
├── templating.py               # Legacy Starlette Jinja2 template renderer & session flash helpers (dormant)
├── routes/api/
│   ├── admin.py                # Admin & mentor management (users, invite links, signup approvals, bin, wipe)
│   ├── announcements.py        # Broadcast announcements (global and project-scoped)
│   ├── attendance.py           # Check-in, check-out, photos, history, reports, manual creation, corrections
│   ├── audit.py                # Scoped audit trail querying and filtering
│   ├── auth.py                 # /me, login, logout, registration, invite-based registration
│   ├── cohorts.py              # Cohort CRUD and member associations
│   ├── dashboard.py            # Aggregated analytics, 30-day attendance chart, present today, open tasks
│   ├── leave.py                # Leave request submission, quota calculation, approval/rejection review
│   ├── notifications.py        # In-app notifications, unread counter, mark-read, delete
│   ├── profile.py              # Current user profile reading, updating, and password change
│   ├── projects.py             # Projects, assignments, tasks, task comments, project comments, project links
│   ├── reviews.py              # Performance reviews CRUD and mentor-intern evaluations
│   ├── search.py               # Global search across users, projects, and tasks
│   ├── standup.py              # Daily standup log submission, query, and editing
│   └── users.py                # User profile overview dialog endpoint (embedded stats, projects, tasks, attendance, leave)
├── migrations/                 # Migration scripts (task creator, audit UTC, recycle bin, activated_at)
├── scripts/                    # Attendance backfill scripts for specific intern datasets
├── tests/                      # Pytest suite (14 automated test files covering attendance, RBAC, leave sync, audit)
└── logs/                       # Runtime logs (activity.log, terminal.log)
```

### 2.2 Frontend Context & Repository Scope
- **Current Workspace Content:** Backend service only (`internhub backend`).
- **Configured Client Build Directory:** `Config.FRONTEND_DIST_DIR` points by default to `../internhub frontend/dist`.
- **Hosting Mechanism in Code:** `main.py` serves static assets from `/assets` via `StaticFiles` and falls back all non-API paths to `index.html` (SPA routing).
- **CORS / Allowed Origins:** Configured for `http://localhost:5173`, `http://127.0.0.1:5173`, `http://localhost:3001`, `http://127.0.0.1:3001`, plus dynamic `PUBLIC_SITE_URL` and `CORS_ORIGIN_REGEX`.

---

## 3. Actual Roles Found in Code

Defined in [models.py](file:///c:/Users/satya/Downloads/internhub%20backend/internhub%20backend/models.py#L24-L29) (`UserRole`):

| Role Identifier | Constant in Code | DB Storage | Role Purpose Discovered in Logic |
| :--- | :--- | :--- | :--- |
| **`admin`** | `UserRole.ADMIN` | `users.role = 'admin'` | Full system administrator. Manages all users, system invite links, system-wide recycle bin, database wipe, role mutations, all projects, all leaves, and all attendance records. |
| **`mentor`** | `UserRole.MENTOR` | `users.role = 'mentor'` | Senior engineer / team lead. Manages assigned interns and projects where they are primary or co-mentor. Can create intern accounts, review intern leave, create tasks, edit attendance of mentees, post announcements, and write performance reviews. Account requires admin approval upon registration. |
| **`intern`** | `UserRole.INTERN` | `users.role = 'intern'` | Standard learner / team member. Submits shift check-in/out, logs daily standups, creates/updates tasks on assigned projects, adds task/project comments, shares links, submits leave requests, and views their own performance reviews. |

*Note on additional roles:* No other roles (such as "HR", "SuperAdmin", "Guest", "Manager", or "Viewer") exist in the database or authorization checks. `GuestUser` in `models.py` is a transient Python object for unauthenticated template context.

---

## 4. Role Permission Matrix

Derived strictly from endpoint dependencies (`get_optional_user`, `require_roles`, `user.role`, `user.is_admin`, `user.is_mentor`, `user.is_intern`):

| Capability / Action | Admin | Mentor | Intern | Code Enforcement Location |
| :--- | :---: | :---: | :---: | :--- |
| **Login / Logout / View Own Profile** | ✅ | ✅ | ✅ | `auth.py`, `profile.py` |
| **Self-Registration (Direct)** | ❌ (Bootstrap) | ✅ *(Pending Admin)* | ✅ *(Instant Active)* | `auth.py:register` |
| **Self-Registration (via Invite Link)** | ❌ | ❌ | ✅ *(Pending Mentor/Admin)* | `auth.py:register_via_invite` |
| **View User List** | ✅ (All) | ✅ *(Own Interns Only)* | ❌ (403) | `admin.py:list_users` |
| **Create Users** | ✅ (Any Role) | ✅ *(Interns Only, self-assigned)* | ❌ (403) | `admin.py:create_user` |
| **Update User Profile / Password** | ✅ (Any) | ✅ *(Own Interns Only)* | ❌ (Own profile only via `/api/profile`) | `admin.py:update_user` |
| **Toggle User Active Status** | ✅ (Any) | ✅ *(Own Interns Only)* | ❌ (403) | `admin.py:toggle_active` |
| **Change User Role** | ✅ (Except Self) | ❌ (403) | ❌ (403) | `admin.py:change_role` |
| **Soft-Delete User** | ✅ (Except Self) | ❌ (403) | ❌ (403) | `admin.py:delete_user` |
| **Create / Manage Invite Links** | ✅ (System-wide) | ✅ *(Assigned to self)* | ❌ (403) | `admin.py:create_invite_link` |
| **Review Intern Signup Requests** | ✅ (All) | ✅ *(Created by / Assigned to)* | ❌ (403) | `admin.py:review_intern_signup_request` |
| **View / Restore / Purge Recycle Bin** | ✅ (All) | ❌ (403) | ❌ (403) | `admin.py:list_recycle_bin` |
| **Clear Application Database** | ✅ *(Requires Password)* | ❌ (403) | ❌ (403) | `admin.py:clear_database` |
| **Check-in / Check-out with Selfie** | ✅ | ✅ | ✅ | `attendance.py:check_in`, `check_out` |
| **View Attendance History** | ✅ (All) | ✅ *(Own Interns + Self)* | ✅ *(Self Only)* | `attendance.py:history` |
| **View Attendance Staff Report** | ✅ (All) | ✅ *(Own Interns Only)* | ❌ (403) | `attendance.py:report` |
| **Manual Attendance Entry / Edit** | ✅ (All) | ✅ *(Own Interns Only)* | ❌ (403) | `attendance.py:create_attendance_manual`, `update_attendance` |
| **Delete Attendance Record** | ✅ (All) | ✅ *(Own Interns Only)* | ❌ (403) | `attendance.py:delete_attendance` |
| **Set Attendance Status Override (`on_leave`, `excused`)** | ✅ | ❌ (403) | ❌ (403) | `attendance.py:update_attendance` |
| **Trigger Auto-Checkout Sweep** | ✅ | ✅ | ❌ (403) | `attendance.py:trigger_auto_checkout` |
| **Create Projects** | ✅ | ✅ *(Must include self as mentor)* | ❌ (403) | `projects.py:create_project` |
| **Edit / Delete Projects** | ✅ | ✅ *(Assigned Mentor Only)* | ❌ (403) | `projects.py:update_project`, `delete_project` |
| **Create Task on Project** | ✅ | ✅ *(Assigned Mentor)* | ✅ *(Assigned Member; defaults to self)* | `projects.py:create_task` |
| **Edit Task Details (Title/Due/Assignee)** | ✅ | ✅ *(Assigned Mentor)* | ✅ *(If Assigned to Task or Project Member)* | `projects.py:update_task` |
| **Change Task Status (Kanban Move)** | ✅ | ✅ *(Assigned Mentor)* | ✅ *(Any Assigned Project Member)* | `projects.py:update_task_status` |
| **Delete Task** | ✅ | ✅ *(Assigned Mentor)* | ✅ *(If Task Creator + Project Member)* | `projects.py:delete_task` |
| **Post Task / Project Comments** | ✅ | ✅ *(Project Mentor/Admin)* | ✅ *(Assigned Member)* | `projects.py:add_comment`, `create_project_comment` |
| **Delete Project Comment** | ✅ | ✅ *(Project Mentor)* | ✅ *(Comment Author Only)* | `projects.py:delete_project_comment` |
| **Post / Delete Project Links** | ✅ | ✅ *(Project Mentor)* | ✅ *(Assigned Member / Submitter)* | `projects.py:create_project_link`, `delete_project_link` |
| **Submit Leave Request** | ❌ (403) | ❌ (403) | ✅ *(Advance ≥ 1 day, within quota)* | `leave.py:request_leave` |
| **Review Leave (Approve/Reject)** | ✅ (All) | ✅ *(Assigned Interns Only)* | ❌ (403) | `leave.py:review` |
| **Submit Daily Standup** | ✅ | ✅ | ✅ *(Today's date only for Interns)* | `standup.py:submit_standup` |
| **Edit / Delete Standup** | ✅ (Any) | ❌ (Own Only) | ❌ (Own Only) | `standup.py:update_standup`, `delete_standup` |
| **Create / Update Cohorts** | ✅ | ✅ *(Creator Only for update/delete)* | ❌ (403) | `cohorts.py` |
| **Create / Manage Announcements** | ✅ (Global/Project) | ✅ *(Project-scoped where mentor)* | ❌ (403) | `announcements.py` |
| **Create / Edit Performance Reviews** | ✅ | ✅ | ❌ (403) | `reviews.py:create_review` |
| **View Audit Logs** | ✅ (Full System) | ✅ *(Scoped: projects + interns)* | ✅ *(Scoped: assigned projects)* | `audit.py:list_audit_logs` |

---

## 5. Actual Modules Discovered

Modules discovered by inspecting routes, models, and business logic:

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                                       INTERNHUB                                       │
└──────┬────────────┬─────────────┬─────────────┬─────────────┬───────────┬───────────┬─┘
       │            │             │             │             │           │           │
┌──────▼──────┐┌────▼───────┐┌────▼───────┐┌────▼───────┐┌────▼──────┐┌───▼─────┐┌────▼───────┐
│Auth & Access││ Attendance ││ Projects & ││   Leave    ││ Standups  ││ Cohorts ││Performance│
│ & Identity  ││ Operations ││ Tasks Mgmt ││ Operations ││ & Reviews ││ & Comms ││ & Governance│
└─────────────┘└────────────┘└────────────┘└────────────┘└───────────┘└─────────┘└───────────┘
```

### Module 1: Authentication, Identity & Onboarding
- **Files:** `routes/api/auth.py`, `dependencies.py`, `models.py`
- **Models:** `User`, `InternInviteLink`
- **Endpoints:** `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me`, `POST /api/auth/register`, `GET /api/auth/invite/{token}`, `POST /api/auth/invite/{token}/register`
- **Purpose:** Handles user credential verification, timed URLSafe token generation, HttpOnly cookie issuance, CSRF tokens, self-registration, and invite-based intern onboarding.

### Module 2: Administration & Workspace Management
- **Files:** `routes/api/admin.py`, `recycle_bin.py`, `utils.py`
- **Models:** `User`, `InternInviteLink`, `BinItem`
- **Endpoints:** 14 endpoints under `/api/admin/*`
- **Purpose:** User provisioning, role switching, account deactivation, mentor-intern pairing, invite link generation/deactivation, intern signup request approvals, recycle-bin lifecycle, and database wiping.

### Module 3: Shift Attendance & Location Verification
- **Files:** `routes/api/attendance.py`, `attendance_photos.py`, `geocoding.py`, `utils.py`
- **Models:** `Attendance`, `AttendanceAuditLog`
- **Endpoints:** 12 endpoints under `/api/attendance/*`
- **Purpose:** Shift check-in and check-out with mandatory selfie photos and GPS coordinates, Nominatim reverse-geocoding, automatic/manual checkout, attendance corrections with audit logging, status recalculation, and CSV reporting.

### Module 4: Project Management, Tasks & Collaboration Board
- **Files:** `routes/api/projects.py`, `utils.py`
- **Models:** `Project`, `ProjectAssignment`, `ProjectMentorAssignment`, `Task`, `TaskComment`, `ProjectComment`, `ProjectLink`
- **Endpoints:** 20 endpoints under `/api/projects/*` and `/api/tasks/*`
- **Purpose:** Project CRUD, multi-mentor and intern staffing, Kanban task workflows with priority and deadlines, 100-character task/project discussions, shared project documentation links, and project export.

### Module 5: Leave Management & Quota Accounting
- **Files:** `routes/api/leave.py`, `utils.py`
- **Models:** `LeaveRequest`, `Attendance`
- **Endpoints:** 5 endpoints under `/api/leave/*`
- **Purpose:** Annual 15-day leave quota calculation, advance leave submission, overlap validation, mentor/admin approval/rejection, and automated syncing into attendance tables with `on_leave` status.

### Module 6: Daily Standups & Performance Reviews
- **Files:** `routes/api/standup.py`, `routes/api/reviews.py`
- **Models:** `StandupLog`, `PerformanceReview`
- **Endpoints:** 5 standup endpoints + 5 review endpoints
- **Purpose:** Daily logging of intern progress (`did`, `plan`, `blockers`, `mood`) and mentor evaluation of interns with multidimensional ratings (overall, technical, communication, initiative) and period-based uniqueness constraints.

### Module 7: Cohorts, Broadcast Announcements & Search
- **Files:** `routes/api/cohorts.py`, `routes/api/announcements.py`, `routes/api/search.py`
- **Models:** `Cohort`, `CohortMember`, `Announcement`
- **Endpoints:** 7 cohort endpoints + 4 announcement endpoints + 1 global search endpoint
- **Purpose:** Grouping interns into structured batches/cohorts, broadcasting global or project-specific pinned announcements, and global entity search across users, projects, and tasks.

### Module 8: Analytics, Notifications & Audit Governance
- **Files:** `routes/api/dashboard.py`, `routes/api/notifications.py`, `routes/api/audit.py`, `log_files.py`
- **Models:** `Notification`, `AuditLog`
- **Endpoints:** 4 dashboard endpoints + 4 notification endpoints + 1 audit log endpoint
- **Purpose:** Role-scoped dashboard metric cards and charts (30-day attendance trends, project status breakdowns, open tasks), in-app notifications, and dual audit logging (DB table + `logs/activity.log`).

---

## 6. Complete Feature Inventory

### 6.1 Authentication & Profile Features
1. **Timed Token Authentication:** Issues URLSafe tokens with 8-hour default TTL or 30-day "remember me" TTL.
2. **Double-Submit CSRF Protection:** Middleware checks `x-csrf-token` header against `ih_csrf` cookie for cookie-based state mutations (`POST`, `PUT`, `DELETE`, `PATCH`).
3. **Session Invalidation on Password Change:** Increments `session_version` in DB; old tokens are instantly rejected.
4. **Login Rate Limiting:** In-memory tracker limits failed requests to 10 attempts per 5-minute window per IP.
5. **Mentor Approval Gate:** Mentor registrations are created with `is_active=False` and `activated_at=None` requiring admin approval before login.
6. **Self-Profile Update:** Users can modify bio, department, phone, job title, and comma-separated skills list.
7. **In-Session Password Change:** Verifies current password and updates password hash and session token atomically.

### 6.2 Attendance Features
8. **Shift Window Enforcement:** Standard shift 10:00 AM – 7:00 PM. Check-in blocked at ≥ 8:00 PM (`CHECKIN_BLOCK`).
9. **Selfie Capture & Disk Persistence:** Check-in/out requires JPEG upload, stored under `attendance_photos/<date>/<user_id>_<slug>/<kind>/<HHMMSS>.jpg`.
10. **GPS Reverse-Geocoding:** Captures lat/lng coordinates and queries OpenStreetMap Nominatim with fallback to raw coordinates on timeout.
11. **Provisional vs. Finalized Status Logic:** Check-in after 10:30 AM marks status provisionally as `late`. Final checkout status uses hours worked:
    - `< 5.0 hours` $\rightarrow$ `absent`
    - `5.0 – 6.99 hours` $\rightarrow$ `half_day`
    - `≥ 7.0 hours` $\rightarrow$ `present` (or `late` if check-in was at or after 12:00 PM noon).
12. **Streak Counter:** Computes consecutive Monday–Friday presence/late/half-day streak over the past 90 days.
13. **Midnight Auto-Checkout:** Scheduled job closes open sessions from prior days as `checkout_missed=True`, `hours_worked=0.0`, `status='absent'`.
14. **Manual Attendance Entry:** Admins and mentors can backfill missing attendance records with mandatory audit reasons.
15. **Attendance Correction & Audit Trail:** Admins/mentors can edit check-in/out times or set status overrides (`on_leave`, `excused`), writing an immutable entry into `attendance_audit_logs`.
16. **CSV Export:** Streams attendance history to CSV with dates, names, check-in/out times, hours, and status.

### 6.3 Project & Task Management Features
17. **Multi-Mentor Staffing:** Projects support a primary mentor (`mentor_id`) and multiple co-mentors (`project_mentor_assignments`).
18. **Intern Staffing:** Interns assigned to projects via `project_assignments`.
19. **Progress Calculation:** Dynamically calculates percentage completed based on tasks with status `done` or `completed`.
20. **Task Lifecycle Management:** CRUD tasks with status (`todo`, `in_progress`, `testing`, `completed`), priority (`low`, `medium`, `high`), and deadlines.
21. **Overdue Task Reminder Sweep:** Daily scheduler identifies overdue tasks and sends push notifications to the intern and mentor.
22. **Task Discussion Threads:** Comments on tasks capped at 100 characters; soft-deleted comments retain author metadata while blanking content.
23. **Project Collaboration Board:** Project-level discussion feed (100-character limit) with role badges.
24. **Shared Project Links:** Link repository with URL validation and mandatory remarks.
25. **Full Project Export:** Generates complete JSON project manifest including members, tasks, and comments.

### 6.4 Leave & Quota Features
26. **15-Day Annual Leave Quota:** Tracks used days against fixed 15-day balance within current calendar year.
27. **Business-Day Calculation:** Automatically excludes Saturdays and Sundays when deducting leave balance.
28. **Advance Submission Enforcement:** Requests must be submitted at least 1 day in advance (`start_date > local_today()`).
29. **Overlap Guard:** Rejects requests overlapping any existing `pending` or `approved` leave ranges.
30. **Attendance Auto-Sync:** Approving a leave request automatically creates/updates attendance rows for all weekdays in the range with status `on_leave`.

### 6.5 Standup, Cohort & Review Features
31. **Daily Standup Logging:** Captures `did`, `plan`, `blockers`, and `mood` (`great`, `good`, `okay`, `tired`, `stressed`). Interns restricted to today's date.
32. **Cohort Management:** Organizes interns into named batches with start/end dates.
33. **Broadcast Announcements:** Pinned or standard announcements scoped globally or to specific projects.
34. **Performance Evaluations:** Mentors grade interns on 1–5 scale across overall rating, technical skills, communication, and initiative with feedback text.

### 6.6 Administration & Recycle Bin Features
35. **Shareable Invite Links:** Generates tokens for intern self-registration with pre-assigned mentor linkage and usage counters.
36. **Intern Signup Approval Queue:** Review queue allowing mentors/admins to approve or reject pending intern signups.
37. **15-Day Recycle Bin:** Soft-deletes projects, tasks, comments, users, announcements, cohorts, reviews, standups, and leave requests into `bin_items` with snapshot JSON.
38. **Daily Bin Purge:** APScheduler purges expired bin items older than 15 days (`Config.BIN_RETENTION_DAYS`).
39. **Emergency Database Wipe:** `POST /api/admin/clear-database` truncates all application tables (preserving admin accounts) guarded by `DB_CLEAR_PASSWORD`.

---

## 7. Frontend Screen & Client Route Inventory

Discovered from frontend route fallbacks in `main.py`, links in `utils.py`, `README.md`, and API link builders:

| Screen / Client Route | Expected Accessible Roles | Discovered Purpose in Code | APIs Supporting This Screen | Status in Codebase |
| :--- | :--- | :--- | :--- | :--- |
| **`/` (Login / Auth)** | Public / All | User login, remember-me checkbox, session creation | `POST /api/auth/login`, `GET /api/auth/me` | **COMPLETE** |
| **`/register`** | Public | Direct registration for intern/mentor | `POST /api/auth/register` | **COMPLETE** |
| **`/join/:token`** | Public (Interns) | Self-onboarding registration via invite link | `GET /api/auth/invite/{token}`, `POST /api/auth/invite/{token}/register` | **COMPLETE** |
| **`/dashboard`** | Admin, Mentor, Intern | KPI stats cards, 30-day attendance chart, present today list, open tasks | `GET /api/dashboard`, `/dashboard/present-today`, `/dashboard/open-tasks`, `/dashboard/attendance-chart` | **COMPLETE** |
| **`/attendance`** | Admin, Mentor, Intern | Selfie check-in/out, today's status, monthly history calendar | `GET /api/attendance/today`, `POST /api/attendance/check-in`, `POST /api/attendance/check-out`, `GET /api/attendance/history` | **COMPLETE** |
| **`/attendance/report`** | Admin, Mentor | Staff attendance overview table, monthly aggregation, CSV export, manual record modal | `GET /api/attendance/report`, `GET /api/attendance/export.csv`, `POST /api/attendance/manual`, `PUT /api/attendance/{id}`, `DELETE /api/attendance/{id}` | **COMPLETE** |
| **`/projects`** | Admin, Mentor, Intern | Project cards/list, filters (status, mentor, date), project creation modal | `GET /api/projects`, `POST /api/projects` | **COMPLETE** |
| **`/projects/:id`** | Admin, Mentor, Intern | Project detail, task Kanban board, task creation/edit modal, comments board, shared links, project export | `GET /api/projects/{id}`, `PUT /api/projects/{id}`, `POST /api/projects/{id}/tasks`, `PATCH /api/projects/tasks/{id}/status`, `GET /api/projects/{id}/comments-board`, `GET /api/projects/{id}/links`, `GET /api/projects/{id}/export` | **COMPLETE** |
| **`/leave`** | Admin, Mentor, Intern | Intern leave request submission, leave balance card, mentor/admin review table | `GET /api/leave/mine`, `POST /api/leave`, `GET /api/leave/balance`, `GET /api/leave/manage`, `POST /api/leave/{id}/review` | **COMPLETE** |
| **`/standup`** | Admin, Mentor, Intern | Daily standup logger form, past standup history list with date filters | `GET /api/standup`, `GET /api/standup/today`, `POST /api/standup`, `PUT /api/standup/{id}` | **COMPLETE** |
| **`/cohorts`** | Admin, Mentor, Intern | Cohort batch list, member management dialog | `GET /api/cohorts`, `POST /api/cohorts`, `GET /api/cohorts/{id}`, `POST /api/cohorts/{id}/members` | **COMPLETE** |
| **`/announcements`** | Admin, Mentor, Intern | Broadcast announcement feed, pinned items, create/edit announcement modal | `GET /api/announcements`, `POST /api/announcements`, `PUT /api/announcements/{id}`, `DELETE /api/announcements/{id}` | **COMPLETE** |
| **`/reviews`** | Admin, Mentor, Intern | Performance review submission form, evaluation history view | `GET /api/reviews`, `POST /api/reviews`, `GET /api/reviews/{id}`, `PUT /api/reviews/{id}` | **COMPLETE** |
| **`/admin/users`** | Admin, Mentor | User table, role filtering, search, pagination, add user modal, edit user dialog | `GET /api/admin/users`, `POST /api/admin/users`, `PUT /api/admin/users/{id}`, `POST /api/admin/users/{id}/toggle`, `POST /api/admin/users/{id}/role`, `DELETE /api/admin/users/{id}` | **COMPLETE** |
| **`/admin/assignments`** | Admin, Mentor | Unassigned interns matrix, staffing by mentor | `GET /api/admin/intern-assignments` | **COMPLETE** |
| **`/invite-links`** | Admin, Mentor | Invite link generator, active links table, signup approval queue | `GET /api/admin/invite-link`, `POST /api/admin/invite-link`, `GET /api/admin/intern-signup-requests`, `POST /api/admin/intern-signup-requests/{id}/review`, `POST /api/admin/invite-link/regenerate` | **COMPLETE** |
| **`/admin/bin`** | Admin | Recycle bin table, snapshot viewer, restore button, purge button, clear all | `GET /api/admin/bin`, `POST /api/admin/bin/{id}/restore`, `DELETE /api/admin/bin/{id}`, `DELETE /api/admin/bin` | **COMPLETE** |
| **`/audit`** | Admin, Mentor, Intern | System audit log feed, category/actor/project/date filters | `GET /api/audit` | **COMPLETE** |
| **`/profile`** | Admin, Mentor, Intern | User profile editor, password change form | `GET /api/profile`, `PUT /api/profile`, `POST /api/profile/change-password` | **COMPLETE** |
| **`/api/docs`** | Public / Dev | FastAPI Swagger Interactive API documentation | `/api/docs` | **COMPLETE** |

---

## 8. Complete API Inventory

Below is the complete inventory of all **62 endpoints** registered on the FastAPI application:

| # | Method | Endpoint | Router/File | Purpose | Authentication | Allowed Roles | Main Input | Main Output | Related Model |
| :- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | `GET` | `/api/health` | `main.py` | Liveness health probe | None | All | None | `{"status": "ok"}` | None |
| 2 | `GET` | `/api/auth/me` | `auth.py` | Current session user | Token/Cookie | All authenticated | None | User profile object | `User` |
| 3 | `POST` | `/api/auth/login` | `auth.py` | User login | IP Rate Limit | Public | `email`, `password`, `remember` | `user`, `token`, `ok` | `User` |
| 4 | `POST` | `/api/auth/logout` | `auth.py` | User logout | Cookie/Header | All | None | `{"ok": True}` | None |
| 5 | `POST` | `/api/auth/register` | `auth.py` | Self-registration | IP Rate Limit | Public | `name`, `email`, `password`, `role` | `user`, `message`, `ok` | `User` |
| 6 | `GET` | `/api/auth/invite/{token}` | `auth.py` | Inspect invite link | None | Public | Token in URL | `valid`, `label`, `mentor_name` | `InternInviteLink` |
| 7 | `POST` | `/api/auth/invite/{token}/register` | `auth.py` | Register via invite | None | Public | `name`, `email`, `password`, `phone`, `department`, `job_title`, `joining_date` | `ok`, `pending_approval`, `message` | `User`, `InternInviteLink` |
| 8 | `GET` | `/api/admin/users` | `admin.py` | List paginated users | Required | Admin, Mentor (scoped) | `role`, `search`, `page`, `page_size` | `users`, `counts`, `total_pages` | `User` |
| 9 | `GET` | `/api/admin/mentors` | `admin.py` | List active mentors | Required | Admin, Mentor | None | List of mentor objects | `User` |
| 10 | `GET` | `/api/admin/intern-assignments` | `admin.py` | Intern staffing summary | Required | Admin, Mentor (scoped) | None | `unassigned`, `no_project`, `by_mentor` | `User`, `ProjectAssignment` |
| 11 | `POST` | `/api/admin/users` | `admin.py` | Admin/mentor create user | Required | Admin, Mentor (interns only) | `name`, `email`, `password`, `role`, `mentor_id`, `department`, `job_title`, `phone` | Created User object | `User` |
| 12 | `PUT` | `/api/admin/users/{id}` | `admin.py` | Update user details | Required | Admin, Mentor (own interns) | `name`, `email`, `phone`, `job_title`, `department`, `joining_date`, `password`, `role`, `mentor_id` | Updated User object | `User` |
| 13 | `POST` | `/api/admin/users/{id}/toggle` | `admin.py` | Toggle active status | Required | Admin, Mentor (own interns) | None (User ID in URL) | User object with flipped `is_active` | `User` |
| 14 | `POST` | `/api/admin/users/{id}/role` | `admin.py` | Change user role | Required | Admin only | `role` | Updated User object | `User` |
| 15 | `DELETE`| `/api/admin/users/{id}` | `admin.py` | Soft-delete user | Required | Admin only | None (User ID in URL) | `{"ok": True}` | `User`, `BinItem` |
| 16 | `GET` | `/api/admin/invite-link` | `admin.py` | Get active invite links | Required | Admin, Mentor (own) | None | `link`, `links` list | `InternInviteLink` |
| 17 | `POST` | `/api/admin/invite-link` | `admin.py` | Create invite link | Required | Admin, Mentor | `label`, `mentor_id` | Created invite link object | `InternInviteLink` |
| 18 | `DELETE`| `/api/admin/invite-link/{id}` | `admin.py` | Delete invite link | Required | Admin, Mentor (creator) | Link ID in URL | `{"ok": True}` | `InternInviteLink` |
| 19 | `GET` | `/api/admin/intern-signup-requests` | `admin.py` | List pending intern signups | Required | Admin, Mentor (scoped) | None | `requests` list, `total` | `User`, `InternInviteLink` |
| 20 | `POST` | `/api/admin/intern-signup-requests/{id}/review` | `admin.py` | Approve/reject signup | Required | Admin, Mentor (scoped) | `decision` (`approved`/`rejected`) | User object or `{"ok": True}` | `User` |
| 21 | `POST` | `/api/admin/invite-link/regenerate` | `admin.py` | Invalidate & make new | Required | Admin only | None | New invite link object | `InternInviteLink` |
| 22 | `POST` | `/api/admin/invite-link/deactivate` | `admin.py` | Deactivate all links | Required | Admin only | None | `{"ok": True}` | `InternInviteLink` |
| 23 | `GET` | `/api/admin/bin` | `admin.py` | Query recycle bin | Required | Admin only | `entity_type`, `page`, `page_size` | `items`, `page`, `total_pages` | `BinItem` |
| 24 | `POST` | `/api/admin/bin/{id}/restore` | `admin.py` | Restore soft-deleted item | Required | Admin only | Bin ID in URL | `{"ok": True, "entity_type": ...}` | `BinItem`, Any Entity |
| 25 | `DELETE`| `/api/admin/bin/{id}` | `admin.py` | Permanently purge item | Required | Admin only | Bin ID in URL | `{"ok": True}` | `BinItem`, Any Entity |
| 26 | `DELETE`| `/api/admin/bin` | `admin.py` | Purge entire recycle bin | Required | Admin only | None | `{"ok": True, "deleted_count": N}` | `BinItem`, Any Entity |
| 27 | `POST` | `/api/admin/clear-database` | `admin.py` | Wipe application tables | Required | Admin only | `password` (`DB_CLEAR_PASSWORD`) | `deleted_rows`, `tables` counts | All Models |
| 28 | `GET` | `/api/attendance/today` | `attendance.py`| Check today's shift status | Required | All authenticated | None | `record`, `today` | `Attendance` |
| 29 | `POST` | `/api/attendance/check-in` | `attendance.py`| Submit shift check-in | Required | All authenticated | Form: `lat`, `lng`, File: `photo` | Attendance record object | `Attendance` |
| 30 | `POST` | `/api/attendance/check-out` | `attendance.py`| Submit shift check-out | Required | All authenticated | Form: `lat`, `lng`, File: `photo` | Attendance record object | `Attendance` |
| 31 | `GET` | `/api/attendance/{id}/photo/{kind}` | `attendance.py`| Retrieve selfie image | Required | Admin, Mentor (mentee), Intern (self) | Attendance ID, `kind` (`checkin`/`checkout`) | JPEG Image stream | `Attendance` |
| 32 | `GET` | `/api/attendance/history` | `attendance.py`| Monthly attendance history | Required | Admin, Mentor (scoped), Intern (self) | `month` (`YYYY-MM`), `user_id`, `page`, `page_size` | `records`, `total`, `month` | `Attendance` |
| 33 | `GET` | `/api/attendance/report` | `attendance.py`| Staff attendance overview | Required | Admin, Mentor (scoped) | `intern_id`, `start`, `end`, `page`, `page_size` | `records`, `monthly_summary`, `interns` | `Attendance` |
| 34 | `GET` | `/api/attendance/export.csv` | `attendance.py`| Export attendance to CSV | Required | Admin, Mentor, Intern (self) | `intern_id`, `start`, `end` | CSV text file download | `Attendance` |
| 35 | `POST` | `/api/attendance/auto-checkout` | `attendance.py`| Run auto-checkout sweep | Required | Admin, Mentor | None | `count`, `message` | `Attendance` |
| 36 | `PUT` | `/api/attendance/{id}` | `attendance.py`| Correct attendance record | Required | Admin, Mentor (mentee) | `reason`, `check_in`, `check_out`, `status_override` | Updated Attendance record | `Attendance`, `AttendanceAuditLog` |
| 37 | `DELETE`| `/api/attendance/{id}` | `attendance.py`| Delete attendance record | Required | Admin, Mentor (mentee) | `reason` (JSON body) | `{"ok": True}` | `Attendance`, `AuditLog` |
| 38 | `GET` | `/api/attendance/{id}/audit` | `attendance.py`| Attendance edit history | Required | Admin, Mentor (mentee) | Record ID in URL | `logs` list | `AttendanceAuditLog` |
| 39 | `POST` | `/api/attendance/manual` | `attendance.py`| Manual attendance entry | Required | Admin, Mentor (mentee) | `user_id`, `date`, `check_in`, `check_out`, `status_override`, `reason` | Created Attendance record | `Attendance`, `AttendanceAuditLog` |
| 40 | `GET` | `/api/audit` | `audit.py` | System audit log feed | Required | Admin, Mentor (scoped), Intern (scoped) | `action`, `actor_id`, `project_id`, `date`, `page` | `logs`, `page`, `total_pages` | `AuditLog` |
| 41 | `GET` | `/api/announcements` | `announcements.py`| List announcements | Required | All authenticated (scoped) | `project_id` | List of Announcement objects | `Announcement` |
| 42 | `POST` | `/api/announcements` | `announcements.py`| Create announcement | Required | Admin, Mentor | `title`, `body`, `is_pinned`, `project_id` | Created Announcement object | `Announcement` |
| 43 | `PUT` | `/api/announcements/{id}` | `announcements.py`| Update announcement | Required | Admin, Mentor (author) | `title`, `body`, `is_pinned` | Updated Announcement object | `Announcement` |
| 44 | `DELETE`| `/api/announcements/{id}` | `announcements.py`| Delete announcement | Required | Admin, Mentor (author) | Announcement ID in URL | `{"ok": True}` | `Announcement`, `BinItem` |
| 45 | `GET` | `/api/cohorts` | `cohorts.py` | List cohorts | Required | All authenticated (scoped) | None | List of Cohort objects | `Cohort`, `CohortMember` |
| 46 | `POST` | `/api/cohorts` | `cohorts.py` | Create cohort | Required | Admin, Mentor | `name`, `description`, `start_date`, `end_date` | Created Cohort object | `Cohort` |
| 47 | `GET` | `/api/cohorts/{id}` | `cohorts.py` | Get cohort details | Required | Admin, Mentor, Intern (member) | Cohort ID in URL | Cohort object with `members` | `Cohort`, `CohortMember` |
| 48 | `PUT` | `/api/cohorts/{id}` | `cohorts.py` | Update cohort | Required | Admin, Mentor (creator) | `name`, `description`, `start_date`, `end_date` | Updated Cohort object | `Cohort` |
| 49 | `DELETE`| `/api/cohorts/{id}` | `cohorts.py` | Delete cohort | Required | Admin, Mentor (creator) | Cohort ID in URL | `{"ok": True}` | `Cohort`, `BinItem` |
| 50 | `POST` | `/api/cohorts/{id}/members` | `cohorts.py` | Add intern to cohort | Required | Admin, Mentor | `user_id` | `{"ok": True}` | `CohortMember` |
| 51 | `DELETE`| `/api/cohorts/{id}/members/{uid}` | `cohorts.py` | Remove intern from cohort | Required | Admin, Mentor | Cohort ID and User ID in URL | `{"ok": True}` | `CohortMember` |
| 52 | `GET` | `/api/dashboard` | `dashboard.py` | Dynamic role dashboard | Required | All authenticated (scoped) | None | `stats`, `role`, `attendance_chart`, `project_status`, `task_status`, `streak` | Multiple Models |
| 52a | `GET` | `/api/admin/dashboard` / `/admin/dashboard` | `dashboard.py` | Single-response Admin Dashboard | Required | Admin, SuperAdmin | None | `role`, `stats`, `present_today_list`, `open_tasks`, `active_projects`, `pending_leave_requests`, `attendance_chart` | `Organization`, `Attendance`, `Task`, `Project`, `LeaveRequest` |
| 52b | `GET` | `/api/mentor/dashboard` / `/mentor/dashboard` | `dashboard.py` | Single-response Mentor Dashboard | Required | Mentor, Admin | None | `role`, `stats`, `assigned_interns`, `present_today_list`, `projects`, `open_tasks`, `pending_leave_requests` | `User`, `Attendance`, `Project`, `Task`, `LeaveRequest` |
| 52c | `GET` | `/api/intern/dashboard` / `/intern/dashboard` | `dashboard.py` | Single-response Intern Dashboard | Required | Intern, All authenticated | None | `role`, `today_attendance`, `streak`, `stats`, `assigned_projects`, `assigned_tasks`, `attendance_chart` | `Attendance`, `Task`, `Project`, `LeaveRequest`, `Announcement` |
| 52d | `GET` | `/api/superadmin/dashboard` / `/superadmin/dashboard` | `dashboard.py` | Single-response SuperAdmin Dashboard | Required | SuperAdmin | None | `role`, `stats`, `organizations`, `system_health`, `recent_activity` | `Organization`, `User`, `Project`, `AuditLog` |
| 53 | `GET` | `/api/dashboard/present-today` | `dashboard.py` | Present interns today | Required | All authenticated (scoped) | None | `interns` list | `Attendance`, `User` |
| 54 | `GET` | `/api/dashboard/open-tasks` | `dashboard.py` | Open tasks list | Required | All authenticated (scoped) | None | `tasks` list | `Task`, `Project` |
| 55 | `GET` | `/api/dashboard/attendance-chart`| `dashboard.py` | Calendar month chart | Required | All authenticated (scoped) | `month` (`YYYY-MM`) | `month`, `chart`, `total_interns` | `Attendance` |
| 56 | `GET` | `/api/leave/mine` | `leave.py` | Own leave requests | Required | All authenticated | None | `requests`, `balance` | `LeaveRequest` |
| 57 | `POST` | `/api/leave` | `leave.py` | Submit leave request | Required | Intern only | `start_date`, `end_date`, `reason`, `leave_type` | Created LeaveRequest object | `LeaveRequest` |
| 58 | `GET` | `/api/leave/manage` | `leave.py` | Leave review queue | Required | Admin, Mentor (mentees) | `status`, `page`, `page_size` | `requests`, `total_pages` | `LeaveRequest` |
| 59 | `POST` | `/api/leave/{id}/review` | `leave.py` | Review leave request | Required | Admin, Mentor (mentees) | `decision` (`approved`/`rejected`) | Updated LeaveRequest object | `LeaveRequest`, `Attendance` |
| 60 | `GET` | `/api/leave/balance` | `leave.py` | Check leave quota | Required | All authenticated | None | `{"used": N, "quota": 15, "remaining": N}` | `LeaveRequest` |
| 61 | `GET` | `/api/notifications` | `notifications.py`| User notifications | Required | All authenticated | `page` | `notifications`, `unread_count` | `Notification` |
| 62 | `GET` | `/api/notifications/unread-count`| `notifications.py`| Unread badge count | Required | All authenticated | None | `{"count": N}` | `Notification` |
| 63 | `POST` | `/api/notifications/mark-read` | `notifications.py`| Mark all as read | Required | All authenticated | None | `{"ok": True}` | `Notification` |
| 64 | `DELETE`| `/api/notifications/{id}` | `notifications.py`| Delete notification | Required | All authenticated | Notification ID in URL | `{"ok": True}` | `Notification` |
| 65 | `GET` | `/api/profile` | `profile.py` | Get current profile | Required | All authenticated | None | User profile object | `User` |
| 66 | `PUT` | `/api/profile` | `profile.py` | Update current profile | Required | All authenticated | `name`, `email`, `bio`, `department`, `phone`, `job_title`, `skills` | Updated User object | `User` |
| 67 | `POST` | `/api/profile/change-password` | `profile.py` | Change own password | Required | All authenticated | `current_password`, `new_password`, `confirm_password` | `{"ok": True}` | `User` |
| 68 | `GET` | `/api/projects` | `projects.py` | List visible projects | Required | All authenticated (scoped) | `status`, `mentor_id`, `from_date`, `to_date`, `page`, `page_size` | `projects`, `total_pages` | `Project` |
| 69 | `POST` | `/api/projects` | `projects.py` | Create project | Required | Admin, Mentor | `name`, `description`, `start_date`, `end_date`, `status`, `mentor_ids`, `intern_ids` | Created Project object | `Project`, `ProjectMentorAssignment`, `ProjectAssignment` |
| 70 | `GET` | `/api/projects/{id}` | `projects.py` | Project details & tasks | Required | Admin, Mentor, Intern (member) | Project ID in URL | Project object with `tasks`, `can_edit` | `Project`, `Task` |
| 71 | `GET` | `/api/projects/{id}/export` | `projects.py` | Export project bundle | Required | Admin, Mentor, Intern (member) | Project ID in URL | `project`, `members`, `tasks` | Multiple Models |
| 72 | `PUT` | `/api/projects/{id}` | `projects.py` | Update project & staff | Required | Admin, Mentor (assigned) | `name`, `description`, `start_date`, `end_date`, `status`, `mentor_ids`, `intern_ids` | Updated Project object | `Project` |
| 73 | `DELETE`| `/api/projects/{id}` | `projects.py` | Soft-delete project | Required | Admin, Mentor (assigned) | Project ID in URL | `{"ok": True}` | `Project`, `BinItem` |
| 74 | `POST` | `/api/projects/{id}/assign` | `projects.py` | Assign intern to project | Required | Admin, Mentor (assigned) | `user_id` | `{"ok": True}` | `ProjectAssignment` |
| 75 | `DELETE`| `/api/projects/{id}/assign/{uid}`| `projects.py` | Remove intern from project | Required | Admin, Mentor (assigned) | Project ID and User ID in URL | `{"ok": True}` | `ProjectAssignment` |
| 76 | `POST` | `/api/projects/{id}/tasks` | `projects.py` | Create task on project | Required | Admin, Mentor (assigned), Intern (member) | `title`, `description`, `due_date`, `assigned_to`, `status`, `priority` | Created Task object | `Task` |
| 77 | `PUT` | `/api/projects/tasks/{id}` | `projects.py` | Update task details | Required | Admin, Mentor, Intern (assignee/member) | `title`, `description`, `due_date`, `assigned_to`, `status`, `priority` | Updated Task object | `Task` |
| 78 | `PATCH` | `/api/projects/tasks/{id}/status` | `projects.py` | Drag-drop status change | Required | Admin, Mentor, Intern (project member) | `status` (`todo`/`in_progress`/`testing`/`completed`) | Updated Task object | `Task` |
| 79 | `DELETE`| `/api/tasks/{id}` *(alias: `/api/projects/tasks/{id}`)* | `projects.py` | Soft-delete task | Required | Admin, Mentor, Intern (task creator) | Task ID in URL | `{"ok": True}` | `Task`, `BinItem` |
| 80 | `GET` | `/api/projects/tasks/{id}/comments` | `projects.py` | Get task comments | Required | Admin, Mentor, Intern (project member) | Task ID in URL | List of TaskComment objects | `TaskComment` |
| 81 | `POST` | `/api/projects/tasks/{id}/comments` | `projects.py` | Post task comment (≤100 chars) | Required | Admin, Mentor, Intern (project member) | `body` (max 100 chars) | Created TaskComment object | `TaskComment` |
| 82 | `DELETE`| `/api/projects/tasks/comments/{id}` | `projects.py` | Soft-delete task comment | Required | Admin, Author | Comment ID in URL | `{"ok": True}` | `TaskComment`, `BinItem` |
| 83 | `GET` | `/api/projects/{id}/comments-board` | `projects.py` | Get project comments | Required | Admin, Mentor, Intern (project member) | Project ID in URL | List of ProjectComment objects | `ProjectComment` |
| 84 | `POST` | `/api/projects/{id}/comments-board` | `projects.py` | Post project comment (≤100 chars) | Required | Admin, Mentor, Intern (project member) | `body` (max 100 chars) | Created ProjectComment object | `ProjectComment` |
| 85 | `DELETE`| `/api/projects/comments-board/{id}` | `projects.py` | Delete project comment | Required | Admin, Project Mentor, Author | Comment ID in URL | `{"ok": True}` | `ProjectComment` |
| 86 | `GET` | `/api/projects/{id}/links` | `projects.py` | Get shared project links | Required | Admin, Mentor, Intern (project member) | Project ID in URL | List of ProjectLink objects | `ProjectLink` |
| 87 | `POST` | `/api/projects/{id}/links` | `projects.py` | Share document link | Required | Admin, Mentor, Intern (project member) | `link` (HTTP/HTTPS URL), `remark` | Created ProjectLink object | `ProjectLink` |
| 88 | `DELETE`| `/api/projects/links/{id}` | `projects.py` | Delete project link | Required | Admin, Project Mentor, Submitter | Link ID in URL | `{"ok": True}` | `ProjectLink` |
| 89 | `GET` | `/api/reviews` | `reviews.py` | List performance reviews | Required | Admin, Mentor (authored), Intern (received) | None | List of Review objects | `PerformanceReview` |
| 90 | `POST` | `/api/reviews` | `reviews.py` | Submit performance review | Required | Admin, Mentor | `intern_id`, `rating`, `technical_rating`, `communication_rating`, `initiative_rating`, `period`, `feedback`, `strengths`, `improvements` | Created Review object | `PerformanceReview` |
| 91 | `GET` | `/api/reviews/{id}` | `reviews.py` | Get review details | Required | Admin, Reviewer, Intern (subject) | Review ID in URL | Review object | `PerformanceReview` |
| 92 | `PUT` | `/api/reviews/{id}` | `reviews.py` | Update review | Required | Admin, Reviewer | Rating fields, feedback text | Updated Review object | `PerformanceReview` |
| 93 | `DELETE`| `/api/reviews/{id}` | `reviews.py` | Soft-delete review | Required | Admin, Reviewer | Review ID in URL | `{"ok": True}` | `PerformanceReview`, `BinItem` |
| 94 | `GET` | `/api/search` | `search.py` | Global workspace search | Required | All authenticated (scoped) | `q` (min 2 chars) | `users`, `projects`, `tasks` | Multiple Models |
| 95 | `GET` | `/api/standup` | `standup.py` | Query standup logs | Required | All authenticated (scoped) | `from`, `to`, `user_id`, `page`, `page_size` | `logs`, `total_pages` | `StandupLog` |
| 96 | `GET` | `/api/standup/today` | `standup.py` | Today's standup entry | Required | All authenticated | None | StandupLog object or `None` | `StandupLog` |
| 97 | `POST` | `/api/standup` | `standup.py` | Submit/update standup | Required | All authenticated (Interns: today only) | `did`, `plan`, `blockers`, `mood`, `date` | StandupLog object | `StandupLog` |
| 98 | `PUT` | `/api/standup/{id}` | `standup.py` | Edit standup entry | Required | Admin, Author | `did`, `plan`, `blockers`, `mood` | Updated StandupLog object | `StandupLog` |
| 99 | `DELETE`| `/api/standup/{id}` | `standup.py` | Soft-delete standup | Required | Admin, Author | Standup ID in URL | `{"ok": True}` | `StandupLog`, `BinItem` |
| 100| `GET` | `/api/users/{id}/overview` | `users.py` | User 360 overview | Required | Admin, Mentor (staff/interns), Intern (teammates) | User ID in URL | `user`, `stats`, `projects`, `tasks`, `attendance`, `leave_requests` | Multiple Models |
| 101| `GET` | `/api/users/{id}/leave` | `users.py` | User leave history dialog | Required | Admin, Mentor, Intern (self) | User ID in URL | `requests`, `summary`, `balance` | `LeaveRequest` |

---

## 9. Database Entity & Schema Map

Mapped directly from [models.py](file:///c:/Users/satya/Downloads/internhub%20backend/internhub%20backend/models.py):

| Table Name | Model Class | Primary Purpose | Key Fields | Foreign Keys & Relationships | Soft-Delete Support |
| :--- | :--- | :--- | :--- | :--- | :---: |
| `users` | `User` | User accounts, credentials, profiles, mentor matching | `id`, `name`, `email`, `password_hash`, `role`, `is_active`, `activated_at`, `is_deleted`, `deleted_at`, `bio`, `department`, `skills`, `phone`, `job_title`, `joining_date`, `session_version`, `mentor_id`, `signup_invite_link_id` | `mentor_id` $\rightarrow$ `users.id`<br>`signup_invite_link_id` $\rightarrow$ `intern_invite_links.id`<br>Relationships: `attendance_records`, `projects_as_mentor`, `project_mentor_assignments`, `project_assignments`, `tasks_assigned`, `tasks_created`, `leave_requests`, `notifications`, `mentees` | ✅ (`is_deleted`, `deleted_at`, deactivates `is_active`) |
| `attendance` | `Attendance` | Daily shift check-in/out records, selfies & GPS | `id`, `user_id`, `date`, `check_in`, `check_out`, `status`, `notes`, `checkout_source`, `checkout_missed`, `hours_worked`, `check_in_lat`, `check_in_lng`, `check_in_address`, `check_in_photo`, `check_out_lat`, `check_out_lng`, `check_out_address`, `check_out_photo` | `user_id` $\rightarrow$ `users.id` (CASCADE)<br>UniqueConstraint(`user_id`, `date`)<br>Relationship: `audit_entries` | ❌ (Hard-deleted by admin/mentor correction) |
| `attendance_audit_logs` | `AttendanceAuditLog`| Immutable log of mentor/admin attendance edits | `id`, `attendance_id`, `editor_id`, `editor_name`, `field_name`, `old_value`, `new_value`, `reason`, `created_at` | `attendance_id` $\rightarrow$ `attendance.id` (CASCADE)<br>`editor_id` $\rightarrow$ `users.id` (SET NULL) | ❌ (Immutable) |
| `projects` | `Project` | Work project definition & schedule | `id`, `name`, `description`, `start_date`, `end_date`, `status`, `mentor_id`, `created_at`, `is_deleted`, `deleted_at` | `mentor_id` $\rightarrow$ `users.id`<br>Relationships: `mentor`, `tasks`, `assignments`, `mentor_assignments`, `comments`, `links` | ✅ (`is_deleted`, `deleted_at`) |
| `project_assignments` | `ProjectAssignment` | Intern staffing on projects | `id`, `project_id`, `user_id`, `assigned_at` | `project_id` $\rightarrow$ `projects.id` (CASCADE)<br>`user_id` $\rightarrow$ `users.id` (CASCADE)<br>UniqueConstraint(`project_id`, `user_id`) | ❌ (Hard deleted on unassign) |
| `project_mentor_assignments`| `ProjectMentorAssignment`| Co-mentor staffing on projects | `id`, `project_id`, `user_id`, `assigned_at` | `project_id` $\rightarrow$ `projects.id` (CASCADE)<br>`user_id` $\rightarrow$ `users.id` (CASCADE)<br>UniqueConstraint(`project_id`, `user_id`) | ❌ (Hard deleted on unassign) |
| `tasks` | `Task` | Work items assigned to interns | `id`, `project_id`, `created_by_id`, `title`, `description`, `assigned_to`, `deadline`, `status`, `priority`, `created_at`, `is_deleted`, `deleted_at`, `overdue_notified_at` | `project_id` $\rightarrow$ `projects.id` (CASCADE)<br>`created_by_id` $\rightarrow$ `users.id` (SET NULL)<br>`assigned_to` $\rightarrow$ `users.id`<br>Relationship: `comments` | ✅ (`is_deleted`, `deleted_at`) |
| `task_comments` | `TaskComment` | Discussion comments on tasks | `id`, `task_id`, `user_id`, `body`, `created_at`, `updated_at`, `is_deleted`, `deleted_at`, `deleted_by_id` | `task_id` $\rightarrow$ `tasks.id` (CASCADE)<br>`user_id` $\rightarrow$ `users.id` (CASCADE)<br>`deleted_by_id` $\rightarrow$ `users.id` (SET NULL) | ✅ (`is_deleted`, `deleted_at`, `deleted_by_id`) |
| `project_comments`| `ProjectComment` | Project-level collaboration comments | `id`, `project_id`, `user_id`, `body`, `created_at`, `is_deleted`, `deleted_at`, `deleted_by_id` | `project_id` $\rightarrow$ `projects.id` (CASCADE)<br>`user_id` $\rightarrow$ `users.id` (SET NULL)<br>`deleted_by_id` $\rightarrow$ `users.id` (SET NULL) | ✅ (`is_deleted`, `deleted_at`) |
| `project_links` | `ProjectLink` | Shared URLs/wiki references on projects | `id`, `project_id`, `user_id`, `link`, `remark`, `created_at`, `is_deleted`, `deleted_at`, `deleted_by_id` | `project_id` $\rightarrow$ `projects.id` (CASCADE)<br>`user_id` $\rightarrow$ `users.id` (SET NULL)<br>`deleted_by_id` $\rightarrow$ `users.id` (SET NULL) | ✅ (`is_deleted`, `deleted_at`) |
| `leave_requests`| `LeaveRequest` | Intern time-off requests | `id`, `user_id`, `start_date`, `end_date`, `reason`, `leave_type`, `status`, `reviewed_by`, `reviewed_at`, `created_at`, `is_deleted`, `deleted_at` | `user_id` $\rightarrow$ `users.id` (CASCADE)<br>`reviewed_by` $\rightarrow$ `users.id` (SET NULL) | ✅ (`is_deleted`, `deleted_at`) |
| `standup_logs` | `StandupLog` | Daily work logs | `id`, `user_id`, `date`, `did`, `plan`, `blockers`, `mood`, `created_at`, `is_deleted`, `deleted_at` | `user_id` $\rightarrow$ `users.id` (CASCADE)<br>UniqueConstraint(`user_id`, `date`) | ✅ (`is_deleted`, `deleted_at`) |
| `announcements` | `Announcement` | Workspace broadcast notices | `id`, `title`, `body`, `is_pinned`, `project_id`, `author_id`, `created_at`, `is_deleted`, `deleted_at` | `project_id` $\rightarrow$ `projects.id` (SET NULL)<br>`author_id` $\rightarrow$ `users.id` (SET NULL) | ✅ (`is_deleted`, `deleted_at`) |
| `cohorts` | `Cohort` | Intern batch groups | `id`, `name`, `description`, `start_date`, `end_date`, `is_active`, `created_at`, `is_deleted`, `deleted_at`, `created_by_id` | `created_by_id` $\rightarrow$ `users.id` (SET NULL)<br>Relationship: `members` | ✅ (`is_deleted`, `deleted_at`) |
| `cohort_members`| `CohortMember` | Intern membership in cohorts | `id`, `cohort_id`, `user_id`, `joined_at` | `cohort_id` $\rightarrow$ `cohorts.id` (CASCADE)<br>`user_id` $\rightarrow$ `users.id` (CASCADE)<br>UniqueConstraint(`cohort_id`, `user_id`) | ❌ (Hard deleted on member remove) |
| `performance_reviews`| `PerformanceReview`| Periodic mentor review of intern | `id`, `intern_id`, `reviewer_id`, `project_id`, `period`, `rating`, `technical_rating`, `communication_rating`, `initiative_rating`, `feedback`, `strengths`, `improvements`, `created_at`, `is_deleted`, `deleted_at` | `intern_id` $\rightarrow$ `users.id` (CASCADE)<br>`reviewer_id` $\rightarrow$ `users.id` (CASCADE)<br>`project_id` $\rightarrow$ `projects.id` (SET NULL)<br>UniqueConstraint(`intern_id`, `reviewer_id`, `period`) | ✅ (`is_deleted`, `deleted_at`) |
| `intern_invite_links`| `InternInviteLink`| Shareable registration tokens | `id`, `token`, `label`, `created_by_id`, `mentor_id`, `is_active`, `usage_count`, `created_at` | `created_by_id` $\rightarrow$ `users.id` (SET NULL)<br>`mentor_id` $\rightarrow$ `users.id` (SET NULL) | ❌ (Hard deleted or set `is_active=False`) |
| `notifications` | `Notification` | In-app user notifications | `id`, `user_id`, `message`, `link`, `is_read`, `created_at` | `user_id` $\rightarrow$ `users.id` (CASCADE) | ❌ (Hard deleted on dismissal) |
| `audit_logs` | `AuditLog` | System activity log entries | `id`, `actor_id`, `actor_name`, `action`, `verb`, `target`, `target_id`, `project_id`, `affected_user_id`, `created_at` | `actor_id` $\rightarrow$ `users.id` (SET NULL)<br>`project_id` $\rightarrow$ `projects.id` (SET NULL)<br>`affected_user_id` $\rightarrow$ `users.id` (SET NULL) | ❌ (Immutable append-only) |
| `bin_items` | `BinItem` | Soft-deleted entity index for restore/purge | `id`, `entity_type`, `entity_id`, `title`, `deleted_by_id`, `deleted_by_name`, `deleted_at`, `expires_at`, `restored_at`, `snapshot_json` | `deleted_by_id` $\rightarrow$ `users.id` (SET NULL) | ❌ (Purged permanently upon expiry/clear) |

---

## 10. Role-Wise Functionality & Access Bounds

### 10.1 Role: `admin`
- **Dashboard Data Scope:** Full system aggregate metrics across all users, projects, attendance records, tasks, and pending leave requests.
- **Allowed Actions:** Full CRUD on users, roles, projects, tasks, cohorts, announcements, and performance reviews. Can restore or purge recycle-bin items, trigger manual attendance sweeps, override attendance status to `excused` or `on_leave`, view full unredacted audit logs with actor emails, and clear the database with password verification.
- **Restrictions in Code:** Cannot change own role, cannot deactivate own account, cannot soft-delete own account. Cannot trigger database wipe without setting and verifying `DB_CLEAR_PASSWORD`.

### 10.2 Role: `mentor`
- **Dashboard Data Scope:** Scoped to assigned mentees (`User.mentor_id == mentor.id`) and projects where primary mentor (`Project.mentor_id == mentor.id`) or co-mentor (`project_mentor_assignments`).
- **Allowed Actions:** Create intern accounts (automatically assigned to themselves), edit own mentees, toggle active status on own mentees, generate invite links, approve/reject intern signups for their links, create/manage projects where they are assigned, create/assign tasks, review leave requests of their mentees, edit/delete attendance of their mentees with mandatory audit reason, write performance reviews for any intern, post announcements to their projects, view scoped audit logs.
- **Restrictions in Code:** Cannot create admin or mentor accounts, cannot change user roles, cannot delete user accounts, cannot access or restore the recycle bin, cannot wipe database, cannot edit attendance or review leave of interns not assigned to them, cannot view email addresses in global search results (PII protection).

### 10.3 Role: `intern`
- **Dashboard Data Scope:** Scoped strictly to own attendance history, own running streak, own assigned tasks across staffed projects, and active projects where assigned.
- **Allowed Actions:** Shift check-in and check-out with selfie upload and GPS coordinates, submit daily standups for today, submit advance leave requests, create tasks on assigned projects (defaults assignee to self), move task Kanban status across columns on assigned projects, post comments (≤100 chars) on assigned project tasks and collaboration boards, share document links, delete own created tasks, view own received performance reviews, update own profile and password.
- **Restrictions in Code:** Cannot submit leave requests for today or past dates, cannot exceed 15-day annual leave quota, cannot review leave requests, cannot create projects, cannot edit other users' profiles, cannot view other interns' attendance report, cannot manually backfill or correct attendance records, cannot delete other users' comments or links, cannot post announcements, cannot create cohorts, cannot write performance reviews, cannot access admin APIs or recycle bin.

---

## 11. Feature-Wise Workflows

### 11.1 Intern Onboarding via Shareable Invite Link
```text
1. Admin or Mentor generates Invite Link (POST /api/admin/invite-link)
   ↓
2. Shareable URL created (/join/{token})
   ↓
3. Candidate opens /join/{token} (GET /api/auth/invite/{token})
   ↓
4. Candidate submits registration form (POST /api/auth/invite/{token}/register)
   ↓
5. Backend creates User (role='intern', is_active=False, activated_at=None, signup_invite_link_id=link.id)
   ↓
6. Audit log recorded ("user.register_invite_pending")
   ↓
7. Push notification sent to link creator, assigned mentor, and all system admins
   ↓
8. Mentor or Admin reviews signup request (POST /api/admin/intern-signup-requests/{id}/review)
   ├── If Approved: User.is_active=True, activated_at=_utcnow(), signup_invite_link_id=None, push notification sent to Intern
   └── If Rejected: User row deleted, audit log recorded ("user.signup_reject")
```

### 11.2 Daily Attendance Lifecycle with Auto-Checkout
```text
1. Intern checks in from camera/location-enabled browser (POST /api/attendance/check-in)
   ├── Validates time < 8:00 PM (CHECKIN_BLOCK)
   ├── Uploads check-in selfie to disk (attendance_photos/...)
   ├── Reverse-geocodes lat/lng via OpenStreetMap Nominatim
   └── Sets provisional status ('late' if check-in >= 10:30 AM, else 'present')
   ↓
2. At end of shift, Intern checks out (POST /api/attendance/check-out)
   ├── Uploads check-out selfie to disk
   ├── Reverse-geocodes check-out location
   ├── Computes hours_worked = (check_out - check_in)
   └── Evaluates final status:
         • hours < 5.0  → 'absent'
         • check-in >= 12:00 PM → 'late'
         • hours >= 7.0 → 'present'
         • hours >= 5.0 → 'half_day'
   ↓
3. IF Intern fails to check out before midnight:
   └── Scheduled Job (_run_auto_checkout at 00:00 Config.TIMEZONE) executes:
         • Finds open records where date < local_today()
         • Sets check_out = 19:00, checkout_source='auto', checkout_missed=True
         • Sets hours_worked=0.0, status='absent'
         • Writes AttendanceAuditLog entry ("system: midnight auto-checkout")
```

### 11.3 Leave Request & Attendance Synchronization Workflow
```text
1. Intern submits leave request (POST /api/leave)
   ├── Validates start_date > local_today() (at least 1 day in advance)
   ├── Validates end_date >= start_date
   ├── Computes business days (excluding Saturday & Sunday)
   ├── Checks remaining leave balance (Quota 15 - Used)
   ├── Checks for overlapping pending/approved leave requests
   └── Creates LeaveRequest (status='pending')
   ↓
2. Notifications dispatched to intern's mentor and all admins
   ↓
3. Mentor or Admin reviews request (POST /api/leave/{id}/review)
   ├── If Rejected: status='rejected', reviewed_by=user.id, notification sent to Intern
   └── If Approved: status='approved', reviewed_by=user.id, notification sent to Intern
         ↓
4. sync_attendance_for_approved_leave() executes automatically:
   └── For each weekday in [start_date, end_date]:
         • If Attendance row exists: update status='on_leave', hours_worked=0.0, check_out=None
         • If Attendance row does not exist: create Attendance row with status='on_leave', check_in=10:00 AM, hours_worked=0.0
```

### 11.4 Kanban Task Status & Overdue Notification Workflow
```text
1. Mentor, Admin, or Intern creates Task (POST /api/projects/{id}/tasks)
   ├── Sets status='todo', priority, deadline
   └── If assigned to another user, dispatches push notification
   ↓
2. Project members collaborate:
   ├── Post comments (POST /api/projects/tasks/{id}/comments) -> Notifies assignee & mentors
   └── Move task card (PATCH /api/projects/tasks/{id}/status) -> 'todo' -> 'in_progress' -> 'testing' -> 'completed'
   ↓
3. Daily Overdue Sweep (_run_overdue_task_notifications at 00:10 Config.TIMEZONE):
   ├── Queries non-deleted, uncompleted tasks where deadline < today and overdue_notified_at IS NULL
   ├── Dispatches overdue notification to intern assignee
   ├── Dispatches missed-deadline notification to intern's mentor
   └── Sets overdue_notified_at = UTC timestamp (resets if task deadline is updated)
```

---

## 12. Status Lifecycles & State Transitions

### 12.1 Attendance Statuses (`AttendanceStatus`)
- **Values:** `present`, `late`, `half_day`, `absent`, `on_leave`, `excused`
- **Transition Priority Hierarchy (`determine_status`):**
  1. Missed Checkout (`checkout_missed == True`) $\rightarrow$ `absent` (0.0 hrs)
  2. Hours Worked $< 5.0$ hrs $\rightarrow$ `absent`
  3. Check-in Time $\ge 12:00\text{ PM}$ (Noon Cutoff) $\rightarrow$ `late`
  4. Hours Worked $\ge 7.0$ hrs $\rightarrow$ `present`
  5. Hours Worked $\ge 5.0$ hrs $\rightarrow$ `half_day`
  6. Status Overrides (Admin only): manual assignment of `on_leave` or `excused`.

### 12.2 Project Statuses (`ProjectStatus`)
- **Values:** `planning`, `active`, `completed`, `on_hold`
- **Transitions:** Mutated via `PUT /api/projects/{id}` by Admin or assigned Mentor.

### 12.3 Task Statuses (`TaskStatus`)
- **Values:** `todo`, `in_progress`, `testing`, `completed` (code accepts `done` as an alias for `completed`)
- **Transitions:** Mutated via `PATCH /api/projects/tasks/{id}/status` or `PUT /api/projects/tasks/{id}` by Admin, assigned Mentor, Task Assignee, or staffed Intern.

### 12.4 Leave Statuses (`LeaveStatus`)
- **Values:** `pending` $\rightarrow$ `approved` | `rejected`
- **Transitions:** Intern creates $\rightarrow$ `pending`. Mentor/Admin review $\rightarrow$ `approved` or `rejected`. No transitions out of `approved`/`rejected` exist.

---

## 13. Authentication, Session & Authorization Architecture

```text
Incoming Request
    │
    ├── 1. ProxyHeadersMiddleware (Trusts X-Forwarded-Proto for HTTPS)
    ├── 2. GZipMiddleware (Compresses responses >= 500 bytes)
    ├── 3. SessionMiddleware (Secret key, session cookie max age)
    ├── 4. CSRF Guard Middleware:
    │      • Checks state-changing HTTP verbs (POST, PUT, DELETE, PATCH)
    │      • Exempts /api/auth/login, /register, /invite/*
    │      • Exempts Bearer Authorization header requests
    │      • If session cookie present: validates secrets.compare_digest(ih_csrf cookie, x-csrf-token header)
    │      • Returns 403 JSONResponse on CSRF mismatch
    ├── 5. Security Headers Middleware (Nosniff, Referrer, Camera/Geolocation permissions, CSP, HSTS)
    └── 6. CORSMiddleware (Preflight OPTIONS, credentials=True)
           │
           ▼
Route Dependency: get_optional_user() / require_login()
    ├── Checks Authorization: Bearer <token> (Pytest / API clients)
    ├── Fallback: checks 'ih_session' HttpOnly cookie (Browsers)
    ├── Verifies serializer token signature & expiration (itsdangerous.URLSafeTimedSerializer)
    ├── Loads User from DB (verifies is_active=True and not is_deleted)
    ├── Validates stored session_version matches user.session_version
    └── Role Checker: require_roles("admin", "mentor") raises 403 Forbidden if mismatched
```

---

## 14. Notification Engine

The system contains an internal push notification system persisted to the `notifications` table (`push_notification` in `utils.py`):

| Triggering Event | Recipient | Notification Message in Code | Action Link |
| :--- | :--- | :--- | :--- |
| **Intern registers via invite link** | Link Creator (Mentor) & Assigned Mentor | `"{name} requested an intern account via your invite link. Review and approve or reject."` | `/invite-links` |
| **Intern registers via invite link** | All Active Admins | `"New intern signup request from {name} (mentor: {mentor_name})."` | `/invite-links` |
| **Admin/Mentor approves intern signup** | Intern | `"Your intern account was approved. You can now sign in."` | `/` |
| **Account activated from toggle** | User | `"Your account has been activated."` | None |
| **Admin changes user role** | User | `"Your role was changed from {old_role} to {new_role} by an admin."` | None |
| **Intern assigned to project** | Intern | `"You have been assigned to project: {project.name}"` | `/projects/{id}` |
| **Task assigned / reassigned to intern** | Assignee Intern | `"New task assigned: {title} (Project: {name})"` / `"Task reassigned to you: ..."` | `/projects/{id}` |
| **Comment posted on task** | Task Assignee + Project Mentors | `"{user.name} commented on task \"{title}\" ({project.name}): \"{body_preview}\""` | `/projects/{id}` |
| **Comment posted on project board** | All Project Mentors + Staffed Interns | `"{user.name} commented on {project.name}: \"{body_preview}\""` | `/projects/{id}` |
| **Intern submits leave request** | Intern's Mentor + All Active Admins | `"{name} requested {type} leave for {start} → {end} ({days} days)."` | `/leave` |
| **Mentor/Admin reviews leave request** | Intern | `"Your leave request ({start} → {end}) was {approved/rejected} by {name}."` | `/leave` |
| **Performance review submitted** | Intern | `"You received a performance review from {mentor_name}."` | `/reviews` |
| **Task deadline missed (Scheduled Job)** | Intern Assignee | `"Your task \"{title}\" in {project} was due {deadline} and is now overdue."` | `/projects/{id}` |
| **Task deadline missed (Scheduled Job)** | Intern's Mentor | `"{intern.name} missed the deadline for \"{title}\" in {project} (was due {deadline})."` | `/projects/{id}` |

---

## 15. Scheduled & Automated Jobs

Implemented with **APScheduler (`BackgroundScheduler`)** in `main.py`, bound to `Config.TIMEZONE` (`Asia/Kolkata`):

| Job ID | Cron Trigger Schedule | Target Function | Records Modified | Notifications Sent | Failure Handling |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`auto_checkout`** | Daily at `00:00` | `_run_auto_checkout()` $\rightarrow$ `utils.auto_checkout_missed_sessions` | Open `attendance` records from prior dates (`date < local_today()`): sets `checkout_missed=True`, `hours_worked=0.0`, `status='absent'`, logs to `attendance_audit_logs`. | None | Own DB session; caught with traceback logger |
| **`bin_purge`** | Daily at `00:05` | `_run_bin_purge()` $\rightarrow$ `recycle_bin.purge_expired_bin_items` | Queries `bin_items` where `restored_at IS NULL` and `expires_at < now`. Permanently deletes entities from DB and deletes `bin_items` rows. | None | Own DB session; caught with traceback logger |
| **`overdue_tasks`**| Daily at `00:10` | `_run_overdue_task_notifications()` $\rightarrow$ `utils.notify_overdue_tasks` | Queries uncompleted tasks where `deadline < local_today()` and `overdue_notified_at IS NULL`. Sets `overdue_notified_at = UTC timestamp`. | Push notification to Intern Assignee and Mentor | Own DB session; caught with traceback logger |

*Startup catch-up execution:* In `main.py:lifespan`, all three routines are executed immediately on startup in worker threads before starting the scheduler.

---

## 16. Audit Logging & Activity Tracking

Audit tracking is implemented via dual mechanisms: database records in `audit_logs` and JSON lines written to `logs/activity.log` (`record_audit` in `utils.py`).

### 16.1 Audited Actions in Code
- **User Actions:** `user.register`, `user.register_mentor_pending`, `user.register_invite_pending`, `user.create`, `user.update`, `user.activated`, `user.deactivated`, `user.role_change`, `user.delete`, `user.signup_approve`, `user.signup_reject`, `user.password_change`.
- **Attendance Actions:** `attendance.checkin`, `attendance.checkout`, `attendance.auto_checkout`, `attendance.create`, `attendance.edit`, `attendance.delete`.
- **Project Actions:** `project.create`, `project.update`, `project.delete`, `project.assign`, `project.unassign`, `project.comment`, `project.comment_deleted`, `project.link_added`, `project.link_deleted`.
- **Task Actions:** `task.create`, `task.update`, `task.status`, `task.delete`, `task.comment`, `task.comment_delete`.
- **Leave Actions:** `leave.request`, `leave.approved`, `leave.rejected`.
- **Standup Actions:** `standup.submit`, `standup.update`, `standup.delete`.
- **Cohort Actions:** `cohort.create`, `cohort.update`, `cohort.delete`, `cohort.add_member`, `cohort.remove_member`.
- **Announcement Actions:** `announcement.create`, `announcement.pin`, `announcement.update`, `announcement.delete`.
- **Review Actions:** `review.create`, `review.update`, `review.delete`.
- **Invite Actions:** `invite.create`, `invite.delete`, `invite.regenerate`, `invite.deactivate`.
- **Recycle Bin Actions:** `bin.restore`, `bin.purge`, `bin.clear_all`.
- **System Actions:** `database.clear`.

### 16.2 Scoped Audit Querying (`scoped_audit_query`)
- **Admin:** Can view all audit logs across the entire system.
- **Mentor:** Filtered to logs matching projects they mentor, or where their assigned interns are actors or affected users.
- **Intern:** Filtered strictly to activity on projects they belong to.

---

## 17. Soft Delete & Recycle Bin Lifecycle

Implemented in `recycle_bin.py` and `routes/api/admin.py`:

```
Entity Delete Triggered (User, Project, Task, Comment, Announcement, Cohort, Review, Standup, LeaveRequest)
    │
    ▼
move_to_bin(db, actor, entity_type, entity)
    ├── Sets entity.is_deleted = True, entity.deleted_at = UTC timestamp
    ├── If User: sets entity.is_active = False
    ├── Serializes entity key attributes into JSON snapshot (snapshot_json)
    ├── Calculates expires_at = now + Config.BIN_RETENTION_DAYS (15 days)
    └── Inserts BinItem row into database
           │
           ├───────────────────────────────────────────────────────┐
           │                                                       │
           ▼ (Before 15 days)                                      ▼ (After 15 days / Manual Clear)
Admin Restores (POST /api/admin/bin/{id}/restore)        Permanent Purge (DELETE /api/admin/bin/{id})
    ├── Verifies restored_at IS NULL & not expired             ├── permanently_delete_entity() deletes DB row
    ├── Sets entity.is_deleted = False, deleted_at = None      ├── If User: sets LeaveRequest.reviewed_by = NULL
    ├── If User: sets entity.is_active = True                  └── Deletes BinItem row from database
    └── Sets BinItem.restored_at = UTC timestamp
```

---

## 18. Multi-Tenancy Current State Analysis

### 18.1 Classification: **NOT IMPLEMENTED (Single-Workspace Dedicated Instance)**

### 18.2 Evidence from Codebase:
1. **No Tenant/Organization Models:** There is no `Organization`, `Company`, `Tenant`, or `Workspace` table in `models.py`.
2. **No Tenant Discriminator Columns:** None of the 20 database tables contain an `organization_id`, `tenant_id`, `company_id`, or `workspace_id` foreign key.
3. **Global Uniqueness Constraints:**
   - `User.email` has a global unique constraint (`unique=True` on `users.email`). Two organizations cannot have users with the same email.
   - `InternInviteLink.token` is globally unique.
   - `Attendance` has a single `uq_user_date` unique constraint.
4. **Single-Tenant Database Configuration:** `config.py` connects to a single MySQL schema defined by `MYSQL_DATABASE`.

### 18.3 Potential Cross-Tenant Risk:
Deploying this single codebase for multiple companies without code-level isolation would result in complete cross-tenant data leakage. All users exist in one shared space.

---

## 19. Frontend ↔ API ↔ Database Traceability

```text
[Screen: /attendance]
    │── (Check-in Selfie + GPS) ──> POST /api/attendance/check-in ──> require_login ──> Attendance + Nominatim ──> 200 JSON
    └── (History Calendar)     ──> GET /api/attendance/history   ──> require_login ──> Attendance query     ──> 200 JSON

[Screen: /projects/:id]
    │── (Load Project Board)   ──> GET /api/projects/{id}         ──> _is_project_member ──> Project+Task+Comment ──> 200 JSON
    │── (Move Task Column)     ──> PATCH /api/projects/tasks/{id}/status ──> _can_move_task ──> Task.status update ──> 200 JSON
    │── (Post Task Comment)    ──> POST /api/projects/tasks/{id}/comments ──> _is_project_member ──> TaskComment + Notification ──> 200 JSON
    └── (Add Project Link)     ──> POST /api/projects/{id}/links ──> _is_project_member ──> ProjectLink + URL validation ──> 200 JSON

[Screen: /leave]
    │── (Submit Leave Form)    ──> POST /api/leave                ──> require_login(intern) ──> LeaveRequest + Balance check ──> 200 JSON
    └── (Review Leave Queue)   ──> POST /api/leave/{id}/review    ──> require_roles(admin, mentor) ──> sync_attendance_for_approved_leave ──> Attendance rows updated

[Screen: /admin/users]
    │── (Create Intern/Mentor) ──> POST /api/admin/users          ──> require_roles(admin, mentor) ──> User + Password hash ──> 200 JSON
    └── (Deactivate User)      ──> POST /api/admin/users/{id}/toggle ──> require_roles(admin, mentor) ──> User.is_active flipped ──> 200 JSON
```

---

## 20. Complete Role-Wise User Journeys

### 20.1 Journey: Admin Setup & Operational Governance
```text
1. Admin logs in with bootstrap credentials at /
   ↓
2. Opens Dashboard (/dashboard) -> Views overall metrics (100 interns, 10 mentors, active projects, attendance counts)
   ↓
3. Opens Admin Users (/admin/users) -> Provisions new Mentor and assigns Department
   ↓
4. Opens Invite Links (/invite-links) -> Generates onboarding invite token linked to Mentor
   ↓
5. Receives push notifications of incoming Intern signups -> Opens review queue and approves accounts
   ↓
6. Opens Projects (/projects) -> Creates new Project, assigns primary and co-mentors, and staffs interns
   ↓
7. Audits Operations (/attendance/report) -> Filters records, corrects attendance mistakes with mandatory audit notes
   ↓
8. Manages System Health (/admin/bin) -> Inspects soft-deleted items, restores mistaken deletions, or triggers DB wipe
```

### 20.2 Journey: Mentor Project & Mentee Management
```text
1. Mentor registers at /register -> Waits for Admin approval -> Logs in after approval notification
   ↓
2. Opens Dashboard (/dashboard) -> Views mentee-scoped presence counts and open mentee tasks
   ↓
3. Opens Invite Links (/invite-links) -> Generates invite link for their own batch -> Reviews incoming intern signups
   ↓
4. Opens Projects (/projects/:id) -> Creates tasks, sets deadlines/priorities, and assigns to interns
   ↓
5. Interacts on Collaboration Board -> Posts task comments, project comments, and document links
   ↓
6. Reviews Leave Requests (/leave) -> Approves intern casual leave (automatically updating attendance calendar)
   ↓
7. Evaluates Intern Performance (/reviews) -> Submits end-of-period review with 1-5 ratings across 4 dimensions
```

### 20.3 Journey: Intern Daily Work Lifecycle
```text
1. Intern registers via /join/{token} -> Awaits mentor approval -> Logs in
   ↓
2. Morning Attendance (/attendance) -> Takes selfie with webcam, allows GPS location -> Clicks Check-in (marked present/late)
   ↓
3. Logs Daily Standup (/standup) -> Fills 'did', 'plan', 'blockers', selects 'mood' for today
   ↓
4. Works on Project Tasks (/projects/:id) -> Moves assigned tasks from 'todo' to 'in_progress' to 'testing' to 'completed'
   ↓
5. Communicates -> Posts progress comments on task and adds Figma/GitHub links to shared links board
   ↓
6. Evening Attendance (/attendance) -> Takes checkout selfie -> Clicks Check-out (system computes hours and status)
   ↓
7. Applies for Leave (/leave) -> Checks 15-day balance, submits 2-day advance request -> Receives notification upon review
```

---

## 21. Feature Interaction Map

```mermaid
graph TD
    Users[Users & Roles] -->|Authentication & Authorization| AllModules[All System Endpoints]
    Users -->|Assigned Mentees| Attendance[Shift Attendance]
    Users -->|Staffed On| Projects[Projects & Collaboration]
    Users -->|Submits| Leave[Leave Requests & Quotas]
    Users -->|Logs| Standup[Daily Standups]
    Users -->|Evaluated By| Reviews[Performance Reviews]
    
    Projects -->|Contains| Tasks[Tasks & Kanban Board]
    Projects -->|Contains| ProjComments[Project Comments]
    Projects -->|Contains| ProjLinks[Project Links]
    Projects -->|Scope For| Announcements[Announcements]
    Tasks -->|Contains| TaskComments[Task Comments]
    
    Leave -->|On Approval Syncs| Attendance
    
    Attendance -->|Audit Logs| AttAudit[Attendance Audit Logs]
    AllModules -->|Activity Audit| Audit[Audit Log Table & File]
    AllModules -->|Alerts| Notifications[In-App Notifications]
    
    Projects -->|Soft Delete| RecycleBin[Recycle Bin (15 Days)]
    Tasks -->|Soft Delete| RecycleBin
    Users -->|Soft Delete| RecycleBin
    Reviews -->|Soft Delete| RecycleBin
    Standup -->|Soft Delete| RecycleBin
    Leave -->|Soft Delete| RecycleBin
    Announcements -->|Soft Delete| RecycleBin
    Cohorts -->|Soft Delete| RecycleBin
    
    Scheduler[APScheduler] -->|00:00| Attendance
    Scheduler -->|00:05| RecycleBin
    Scheduler -->|00:10| Tasks
```

---

## 22. Feature Completeness Classification Matrix

| Feature | Frontend View | Backend API | Database Model | Auth & Role Guards | Workflow Complete | Classification |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Auth Login / Logout / Me** | ✅ | ✅ | `User` | ✅ | ✅ | **COMPLETE** |
| **Direct Registration** | ✅ | ✅ | `User` | ✅ | ✅ | **COMPLETE** |
| **Invite-link Registration** | ✅ | ✅ | `User`, `InternInviteLink` | ✅ | ✅ | **COMPLETE** |
| **Admin User CRUD & Role Change** | ✅ | ✅ | `User` | ✅ | ✅ | **COMPLETE** |
| **Selfie & GPS Attendance Check-in/out**| ✅ | ✅ | `Attendance` | ✅ | ✅ | **COMPLETE** |
| **Attendance Monthly Calendar & History**| ✅ | ✅ | `Attendance` | ✅ | ✅ | **COMPLETE** |
| **Attendance Corrections & Audit Logs**| ✅ | ✅ | `AttendanceAuditLog` | ✅ | ✅ | **COMPLETE** |
| **Attendance CSV Export** | ✅ | ✅ | `Attendance` | ✅ | ✅ | **COMPLETE** |
| **Midnight Auto-Checkout Sweep** | ⚙️ (Background)| ✅ | `Attendance` | ✅ | ✅ | **COMPLETE** |
| **Project CRUD & Multi-Mentor Staffing**| ✅ | ✅ | `Project`, `ProjectMentorAssignment`| ✅ | ✅ | **COMPLETE** |
| **Task Kanban & Drag-Drop Status** | ✅ | ✅ | `Task` | ✅ | ✅ | **COMPLETE** |
| **Task Comments & Soft Deletion** | ✅ | ✅ | `TaskComment`, `BinItem` | ✅ | ✅ | **COMPLETE** |
| **Project Collaboration Board** | ✅ | ✅ | `ProjectComment` | ✅ | ✅ | **COMPLETE** |
| **Project Document Links** | ✅ | ✅ | `ProjectLink` | ✅ | ✅ | **COMPLETE** |
| **Project Bundle JSON Export** | ✅ | ✅ | `Project`, `Task`, `User` | ✅ | ✅ | **COMPLETE** |
| **Overdue Task Reminder Sweep** | ⚙️ (Background)| ✅ | `Task`, `Notification` | ✅ | ✅ | **COMPLETE** |
| **Leave Quota (15d) & Overlap Guard** | ✅ | ✅ | `LeaveRequest` | ✅ | ✅ | **COMPLETE** |
| **Leave Approval & Attendance Sync** | ✅ | ✅ | `LeaveRequest`, `Attendance` | ✅ | ✅ | **COMPLETE** |
| **Daily Standup Logging & Mood** | ✅ | ✅ | `StandupLog` | ✅ | ✅ | **COMPLETE** |
| **Cohort Batch Management** | ✅ | ✅ | `Cohort`, `CohortMember` | ✅ | ✅ | **COMPLETE** |
| **Broadcast Announcements** | ✅ | ✅ | `Announcement` | ✅ | ✅ | **COMPLETE** |
| **Performance Reviews (1-5 Ratings)** | ✅ | ✅ | `PerformanceReview` | ✅ | ✅ | **COMPLETE** |
| **15-Day Recycle Bin & Restore** | ✅ | ✅ | `BinItem`, All Models | ✅ | ✅ | **COMPLETE** |
| **Activity Audit Logging (DB + File)** | ✅ | ✅ | `AuditLog` | ✅ | ✅ | **COMPLETE** |
| **Global Search (Users, Projects, Tasks)**| ✅ | ✅ | Multiple Models | ✅ | ✅ | **COMPLETE** |
| **Database Wipe with Password** | ✅ | ✅ | All Models | ✅ | ✅ | **COMPLETE** |
| **Legacy Jinja2 Server Templates** | ❌ (No files)| ⚠️ `templating.py`| `GuestUser` | ❌ | ❌ | **UNUSED / DEAD** |

---

## 23. Unused, Dead, or Disconnected Code

1. **`templating.py` (Dead Legacy File):**
   - Implements `Jinja2Templates(directory="templates")`, `flash()`, `pop_flashes()`, and `render()`.
   - The project has no `templates/` directory on disk.
   - `dependencies.py:13` still imports `flash` from `templating` and calls `flash(request, "You do not have permission...")` at line 102 inside `require_roles`, but because the entire frontend is an API-driven SPA, this session flash is never rendered or read by any client.
2. **`LoginRequired` Exception Handler Missing in `main.py`:**
   - `dependencies.py:55` defines `class LoginRequired(Exception)` and `require_login` raises `LoginRequired(request.url.path)` at line 94.
   - However, `main.py` has no `@app.exception_handler(LoginRequired)`. Raising `LoginRequired` produces an unhandled 500 error instead of a clean 401 response (though API routes primarily use `get_optional_user` and raise `HTTPException(401)` directly).
3. **Legacy Function Aliases in `utils.py`:**
   - `finalize_checkout_status` and `resolve_attendance_status` are legacy wrappers around `determine_status`.

---

## 24. Missing or Incomplete Flows

1. **Password Reset / Recovery via Email:**
   - `Config.RESET_TOKEN_MAX_AGE` is configured (3600s), but there are no backend routes, email services (SMTP/SendGrid), or database tokens to support forgotten password recovery. Users who forget passwords must have an admin/mentor manually update their password via `PUT /api/admin/users/{id}`.
2. **Project Link Soft-Delete vs Bin Entry:**
   - Deleting a project link (`DELETE /api/projects/links/{link_id}`) sets `is_deleted=True` on the `ProjectLink` model, but does NOT create a `BinItem` in `bin_items`, meaning project links cannot be viewed or restored from the admin Recycle Bin screen.
3. **Project Comment Soft-Delete vs Bin Entry:**
   - Similarly, `DELETE /api/projects/comments-board/{comment_id}` sets `is_deleted=True` but does not invoke `move_to_bin()`. Only `TaskComment` invokes `move_to_bin()`.

---

## 25. Technical Risks Found

1. **OpenStreetMap Nominatim Rate Limiting in Reverse Geocoding:**
   - `geocoding.py` calls OpenStreetMap Nominatim with a 5-second timeout. Nominatim's public policy limits requests to 1 req/sec. If a cohort of 50 interns checks in simultaneously at 10:00 AM, upstream HTTP 429 throttling will cause geocoding to return `None` for most check-ins.
2. **In-Memory Login Rate Limiter Resets on Worker Restart:**
   - `_login_attempts` in `utils.py` is a standard Python `defaultdict(list)`. Rate limits do not persist across server restarts or across multiple uvicorn workers.
3. **Synchronous File Writes in File Logging:**
   - `log_files.py:write_activity_log` opens and appends to `logs/activity.log` synchronously on every audited mutation.
4. **Attendance Photos Stored on Local Disk by Default:**
   - Stored in `./attendance_photos`. On containerized ephemeral environments (e.g. Railway without persistent volume attached to `ATTENDANCE_PHOTOS_DIR`), selfie photos will be lost on redeploy.

---

## 26. Final Actual Product Feature List

### Module: Identity & Access Management
- [x] HttpOnly session cookie authentication with URLSafe timed tokens
- [x] Authorization Bearer token header support for external clients/tests
- [x] Session versioning for instant revocation across password changes
- [x] Double-submit CSRF header/cookie guard
- [x] Login rate limiting (10 attempts / 5 minutes)
- [x] Direct registration for interns and mentors (mentors require admin activation)
- [x] Shareable invite links with assigned mentor pairing
- [x] Candidate invite-link self-onboarding with mentor/admin approval queue
- [x] Role-based access control (`admin`, `mentor`, `intern`)
- [x] User management: creation, profile updating, active toggle, role change, soft deletion
- [x] Self profile management: update bio, department, phone, job title, skills
- [x] In-session password change with credential verification

### Module: Shift Attendance & Location Operations
- [x] Daily shift window tracking (10:00 AM – 7:00 PM)
- [x] Check-in blocking after 8:00 PM
- [x] Webcam selfie capture for check-in and check-out
- [x] GPS capture with reverse-geocoding via OpenStreetMap
- [x] Late arrival detection (provisional at 10:30 AM, hard cutoff at 12:00 PM noon)
- [x] Automated status calculation (`present`, `late`, `half_day`, `absent`) based on hours worked
- [x] Consecutive working-day presence streak calculation (90-day window)
- [x] Scheduled midnight auto-checkout for missed checkouts
- [x] Manual attendance record backfilling with mandatory reason
- [x] Attendance record corrections with immutable audit log entries (`attendance_audit_logs`)
- [x] Admin status overrides (`on_leave`, `excused`)
- [x] Attendance record deletion with audit logging
- [x] Staff attendance report with monthly aggregations and filtering
- [x] Attendance CSV export

### Module: Projects, Tasks & Collaboration
- [x] Project creation and lifecycle status management (`planning`, `active`, `completed`, `on_hold`)
- [x] Multi-mentor staffing (primary mentor + co-mentors)
- [x] Intern staffing on projects
- [x] Dynamic project progress calculation (% tasks completed)
- [x] Task creation with priority (`low`, `medium`, `high`), deadlines, and assignees
- [x] Kanban drag-and-drop task status transitions (`todo`, `in_progress`, `testing`, `completed`)
- [x] Scheduled daily overdue task sweep with intern and mentor notifications
- [x] Task discussion comments (100-character cap) with author notifications
- [x] Project-level discussion board (100-character cap)
- [x] Shared project documentation links with URL validation
- [x] Complete project bundle export in JSON format

### Module: Leave Management
- [x] 15-day annual casual leave quota tracking
- [x] Business-day leave duration calculation (excluding Saturdays and Sundays)
- [x] Advance notice validation (minimum 1 day in advance)
- [x] Overlapping leave request prevention
- [x] Mentor and Admin leave review queue (approve / reject)
- [x] Automatic synchronization of approved leave into attendance calendar with `on_leave` status

### Module: Standups, Cohorts & Reviews
- [x] Daily standup logging (`did`, `plan`, `blockers`, `mood`)
- [x] Intern standup submission restricted to current date
- [x] Cohort batch creation and intern membership management
- [x] Broadcast announcements with pinning and project-level scoping
- [x] Periodic performance reviews with 1–5 scoring across overall, technical, communication, and initiative dimensions

### Module: Governance, Notifications & System Tools
- [x] Real-time in-app push notifications for assignments, comments, leave, reviews, and signups
- [x] Role-scoped analytics dashboard (30-day attendance chart, presence list, open tasks)
- [x] Dual audit logging (SQLAlchemy `audit_logs` table + `logs/activity.log` file)
- [x] Scoped audit log queries per role
- [x] Global search across users, projects, and tasks
- [x] 15-day Recycle Bin with snapshot JSON serialization, restoration, and daily background purge
- [x] Emergency database wipe endpoint guarded by `DB_CLEAR_PASSWORD`
- [x] Idempotent database schema migration on startup

---
*(End of Reverse-Engineered Product Understanding Document)*
