# Phase 0: Complete Existing System Analysis
## InternHub Workspace to B2B Multi-Tenant SaaS Platform

> **Document ID:** `SAAS_MIGRATION_EXISTING_SYSTEM_ANALYSIS.md`  
> **Status:** Completed Baseline Analysis  
> **Target:** Reverse-Engineered Technical Analysis of Existing Backend, Database, Auth, Jobs, and Design Systems

---

## 1. Executive Codebase Inventory

### 1.1 Backend Structural Layout
```
internhub backend/
├── main.py                     # App factory, middleware (CSRF, Proxy, Headers, CORS), APScheduler, SPA hosting
├── config.py                   # Environment configuration (MySQL settings, shift times, token TTL, CORS)
├── database.py                 # SQLAlchemy engine, pool settings, SessionLocal factory, get_db generator
├── dependencies.py             # Auth verification, timed URLSafe token serializer, require_roles, CSRF checks
├── models.py                   # 20 SQLAlchemy ORM models, UserRole/Status constants, helper methods
├── recycle_bin.py              # Soft-delete handler, JSON snapshot serializer, entity restore, 15-day purge
├── utils.py                    # Shift hours & status calculation, streak counter, leave balance, audit, push alerts
├── attendance_photos.py        # Disk persistence for selfie captures (attendance_photos/)
├── geocoding.py                # Reverse geocoding client for OpenStreetMap Nominatim
├── log_files.py                # File appender for logs/activity.log and logs/terminal.log
├── migrate_db.py               # Custom startup schema synchronization and migration script executor
├── init_db.py                  # Standalone database and table initialization script
├── seed.py                     # Demo dataset seeder (10 mentors, 100 interns, 5 projects, cohorts, reviews)
├── templating.py               # Legacy Starlette Jinja2 template renderer (unused/dead)
├── routes/api/                 # 16 API router modules covering all system domains
│   ├── auth.py, admin.py, attendance.py, audit.py, announcements.py, cohorts.py,
│   ├── dashboard.py, leave.py, notifications.py, profile.py, projects.py,
│   └── reviews.py, search.py, standup.py, users.py
├── migrations/                 # Custom procedural migration scripts
└── tests/                      # 14 Pytest test suites
```

---

## 2. Backend Architecture Analysis

### 2.1 ORM Entities & Relationships
The backend currently defines **20 SQLAlchemy ORM models** in `models.py`:
1. `User` (`users`): Global identity and role storage (`admin`, `mentor`, `intern`).
2. `Attendance` (`attendance`): Daily check-in/out records with GPS and selfie photo relative paths.
3. `AttendanceAuditLog` (`attendance_audit_logs`): Immutable record of attendance corrections with editor ID and reason.
4. `Project` (`projects`): Workspace projects with start/end dates, primary mentor (`mentor_id`), and status.
5. `ProjectAssignment` (`project_assignments`): Many-to-many relationship between `projects` and `users` (interns).
6. `ProjectMentorAssignment` (`project_mentor_assignments`): Many-to-many relationship between `projects` and co-mentors.
7. `Task` (`tasks`): Work items assigned to interns with deadline, status (`todo`, `in_progress`, `testing`, `completed`), priority.
8. `TaskComment` (`task_comments`): 100-character threaded task comments with soft delete support.
9. `ProjectComment` (`project_comments`): 100-character project collaboration board comments.
10. `ProjectLink` (`project_links`): Shared project documentation URLs and remarks.
11. `LeaveRequest` (`leave_requests`): Intern leave requests with start/end date, type, and review status.
12. `StandupLog` (`standup_logs`): Daily standup logs (`did`, `plan`, `blockers`, `mood`).
13. `Announcement` (`announcements`): Broadcast notices with pinning and optional project scoping.
14. `Cohort` (`cohorts`): Batch groups for interns.
15. `CohortMember` (`cohort_members`): Association between cohorts and intern users.
16. `PerformanceReview` (`performance_reviews`): Periodic evaluation of interns across 4 rating dimensions (1–5 scale).
17. `InternInviteLink` (`intern_invite_links`): Shareable registration tokens with usage counts.
18. `Notification` (`notifications`): In-app push notifications with target links and read states.
19. `AuditLog` (`audit_logs`): Action audit trail entries with actor, action, verb, and target entity IDs.
20. `BinItem` (`bin_items`): 15-day soft-delete recycle bin entries with serialized JSON snapshots.

### 2.2 Existing Authentication & Authorization
- **Token Mechanism:** ItsDangerous `URLSafeTimedSerializer` with salt `"auth-salt"`.
- **Session Lifetimes:** 8 hours default (`Config.SESSION_DEFAULT_AGE`), 30 days for Remember Me (`Config.SESSION_REMEMBER_AGE`).
- **Transport Mechanisms:** Dual transport support:
  1. `ih_session` HttpOnly, SameSite=Lax cookie (Web client default).
  2. `Authorization: Bearer <token>` header (API and testing default).
- **CSRF Guard:** Double-submit cookie check comparing `ih_csrf` cookie against `x-csrf-token` header on state-changing methods (`POST`, `PUT`, `DELETE`, `PATCH`). Exempts login, register, and Bearer requests.
- **Session Revocation:** Every password change increments `User.session_version`. Mismatched token payloads fail validation immediately.
- **Rate Limiting:** In-memory dictionary tracking IP failed login attempts (max 10 attempts per 300-second window).

### 2.3 Existing Background Schedulers
Powered by APScheduler (`BackgroundScheduler`) in `main.py` locked to `Config.TIMEZONE` (`Asia/Kolkata`):
1. `00:00`: `_run_auto_checkout` closes open sessions where `date < today` as `absent` (`hours_worked=0.0`).
2. `00:05`: `_run_bin_purge` permanently deletes non-restored bin items where `expires_at < now`.
3. `00:10`: `_run_overdue_task_notifications` sweeps uncompleted tasks where `deadline < today` and sends push notifications to intern and mentor.

---

## 3. Frontend Architecture & Design System Analysis

### 3.1 Frontend Stack & Routing Patterns
- **Framework:** React 19 + TypeScript / JSX with Vite build tool.
- **State Management & Data Fetching:** TanStack Query (`@tanstack/react-query`) with cache invalidation.
- **Routing:** React Router v6/v7 with client-side SPA routing and fallback to `index.html`.
- **Icons & Visualization:** Lucide React icons, Recharts for 30-day analytics charts.

### 3.2 Visual Design System & Component Tokens
- **Typography:** Modern clean sans-serif stack (`Inter`, system sans-serif), crisp letter-spacing and tabular numbers for dates/times.
- **Color Palette:**
  - *Primary Brand / Accents:* Indigo / Deep Blue (`#4F46E5` / `#4338CA`) with Slate/Zinc neutrals.
  - *Status Badges:*
    - Present / Completed / Approved: Emerald Green (`bg-emerald-50 text-emerald-700 border-emerald-200`)
    - Late / In Progress / Pending: Amber / Yellow (`bg-amber-50 text-amber-700 border-amber-200`)
    - Half-Day / Testing: Blue (`bg-blue-50 text-blue-700 border-blue-200`)
    - Absent / Rejected / Overdue: Rose / Red (`bg-rose-50 text-rose-700 border-rose-200`)
  - *Backgrounds & Surfaces:* Pure white cards (`#FFFFFF`) with subtle borders (`border-slate-200`) on neutral app background (`bg-slate-50`).
- **Surface Elevation & Radius:** Rounded corners (`rounded-xl` for cards, `rounded-lg` for inputs/buttons), subtle drop shadows (`shadow-sm`, `shadow-md` for modals).
- **Interactive Component Patterns:**
  - Modal dialogs with backdrop blur (`backdrop-blur-sm bg-slate-900/40`).
  - Kanban drag-and-drop board with smooth column drop indicators.
  - Webcam selfie capture preview with active shutter button and GPS status badge.
  - Responsive tables with sticky headers, search inputs, status filter chips, and pagination controls.

---

## 4. Architectural Deficiencies for Multi-Tenant B2B SaaS

| Current Single-Tenant Implementation | Multi-Tenant B2B SaaS Requirement | Risk / Gap Severity |
| :--- | :--- | :--- |
| **No `organization_id` on any model** | All domain entities must belong to an organization | **CRITICAL (Cross-tenant data exposure)** |
| **User role stored on `users.role`** | Role belongs to `organization_memberships` | **CRITICAL (Blocks multi-org users)** |
| **Global unique constraints on email** | One identity can belong to multiple workspaces | **HIGH (Blocks multi-org membership)** |
| **Single `admin` role with global scope** | Separate Platform Super Admin vs Org Admin | **CRITICAL (Privilege escalation)** |
| **Shift & leave constants in `config.py`** | Tenant-configurable attendance and leave policies | **HIGH (Rigid for varied customers)** |
| **Hardcoded `Asia/Kolkata` timezone** | Timezone resolved from `organization.timezone` | **HIGH (Incorrect for global orgs)** |
| **Local disk photo storage (`./attendance_photos`)**| Abstract storage provider (S3 / Cloudflare R2) | **HIGH (Data loss on container redeploy)** |
| **Synchronous Nominatim geocoding** | Asynchronous geocoding with coordinate caching | **MEDIUM (Upstream rate limit throttling)** |
| **`POST /api/admin/clear-database` endpoint** | Restrict/Remove dangerous wipe endpoint from API | **CRITICAL (Accidental tenant data wipe)** |
