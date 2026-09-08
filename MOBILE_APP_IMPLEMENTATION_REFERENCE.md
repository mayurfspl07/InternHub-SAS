# InternHub — Mobile App Implementation Reference

> **Purpose:** Complete functional specification of the existing InternHub web frontend so a mobile app can implement the **same functionality** against the **same backend APIs**.
>
> **Rules followed:** Documents only what exists in this repository. No redesign. No invented endpoints or permissions.
>
> **Source of truth:**
> - Routes / guards: `src/App.tsx`
> - Permissions: `src/lib/permissions.ts`
> - Navigation: `src/components/layout/AppSidebar.tsx`
> - Session: `src/lib/session.tsx`
> - HTTP API: `src/lib/api.ts` (all network calls)
> - Validation limits: `src/lib/validation.ts`
> - Pages: `src/routes/*.tsx`
>
> **Generated from codebase.** If web UI and this doc ever diverge, trust the code.

---

## Table of contents

1. [System overview](#1-system-overview)
2. [Environment & networking](#2-environment--networking)
3. [Authentication & session](#3-authentication--session)
4. [Roles & permissions](#4-roles--permissions)
5. [Route / screen inventory](#5-route--screen-inventory)
6. [Role × page access matrix](#6-role--page-access-matrix)
7. [Global chrome (header / sidebar / providers)](#7-global-chrome-header--sidebar--providers)
8. [Forms catalog](#8-forms-catalog)
9. [Actions & buttons (by area)](#9-actions--buttons-by-area)
10. [API endpoint catalog](#10-api-endpoint-catalog)
11. [Shared validation constants](#11-shared-validation-constants)
12. [Data / query layer](#12-data--query-layer)
13. [Explicit absences](#13-explicit-absences)

---

## 1. System overview

InternHub is a multi-tenant internship operations SPA (React + React Router + TanStack Query).

| Layer | Implementation |
|-------|----------------|
| UI | React components under `src/components`, pages under `src/routes` |
| Routing | `react-router-dom` in `src/App.tsx` |
| Server state | `@tanstack/react-query` via `src/hooks/useApi.ts`, `src/lib/queryClient.ts`, `src/lib/queryKeys.ts` |
| Session | React context `SessionProvider` (`src/lib/session.tsx`) |
| Theme | `ThemeProvider` (styles: `neo`, `aurora`; light/dark) |
| HTTP | Custom `fetch` wrapper in `src/lib/api.ts` — **not axios** |
| Toasts | `sonner` via `<Toaster />` |
| Errors | `RootErrorBoundary`, `RouteErrorBoundary`, `QueryErrorState`, pages `/500` `/error`, catch-all `NotFound` |

**Roles in code:** `superadmin` | `admin` | `mentor` | `intern`.

**App shells:**
- **Public:** login, signup, join invite, server-error pages.
- **Protected:** requires authenticated session.
- **SuperadminOnly:** `/tenants`, `/tenants/:orgId`, `/leads`.
- **TenantAppOnly:** most workspace features; requires `canAccessTenantApp` (admin | mentor | intern). Superadmin navigating these is redirected to `/dashboard`.

---

## 2. Environment & networking

### Env vars (`.env.example`)

| Variable | Meaning |
|----------|---------|
| `VITE_API_BASE` | Remote API origin for SPA (cross-origin Bearer). Empty = same-origin `/api` via Vite proxy. |
| `VITE_API_PROXY_TARGET` | Proxy target when `VITE_API_BASE` empty (default `http://127.0.0.1:3001`). |

### Base URL

```
BASE = VITE_API_BASE without trailing slash (or "")
apiUrl(path) = BASE + path
```

All API paths start with `/api/...`.

### Request defaults (`request()` in `api.ts`)

| Item | Behavior |
|------|----------|
| Credentials | `credentials: "include"` always |
| JSON body | `Content-Type: application/json` |
| FormData | No manual Content-Type (multipart boundary) |
| Bearer | `Authorization: Bearer <token>` when in-memory token set |
| CSRF | Cookie `ih_csrf` → header `X-CSRF-Token` on non-GET/HEAD |
| Org | `X-Organization-Id` when active org id set |
| Success 204 | Returns `undefined` |
| Failure | Throws `Error` with `.status`; may parse JSON `.detail`; 429 may set `.retryAfter` |

### CSRF-exempt path prefixes

`/api/auth/login`, `/api/auth/register`, `/api/auth/invite/`, `/api/auth/logout`, `/api/leads`, `/api/demo`

> `/api/demo` is CSRF-exempt in code; **no client call** to `/api/demo` exists.

### Authed binary helpers

| Helper | Use |
|--------|-----|
| `fetchAuthedImage(path)` | Attendance photos |
| `downloadFile(path)` | Attachment download |
| `fetchAuthedBlob(path)` | Preview/download with mime |

---

## 3. Authentication & session

### Session states (`src/lib/session.tsx`)

| State | UI |
|-------|-----|
| `loading` | AppLoader “Authenticating…” |
| `authenticated` | Protected routes |
| `unauthenticated` | Redirect to `/` |

### Flows

| Flow | API | Notes |
|------|-----|-------|
| Bootstrap | `GET /api/auth/me` | On mount; 401 clears Bearer |
| Login | `POST /api/auth/login` `{ email, password, remember }` | Cross-origin: persist token (`local` if remember, else `session`). Same-origin: cookies; clears Bearer. |
| Logout | `POST /api/auth/logout` | Always clears token; `clearQueryCache()`; navigate `/` |
| Register | `POST /api/auth/register` then login | Signup page forces `role: "intern"` |
| Invite register | `GET /api/auth/invite/:token` then `POST .../register` | May return `pending_approval` |

### Token storage

| Key | Value |
|-----|-------|
| `ih_auth_token` | Bearer string in `sessionStorage` and/or `localStorage` when `VITE_API_BASE` set |

### Change password (authenticated)

`POST /api/profile/change-password` — opened from **header user menu**, not profile page. On success, if response includes `token` and cross-origin API, refresh stored Bearer.

### Not implemented

- Forgot password
- Reset password
- Magic link login

---

## 4. Roles & permissions

Source: `src/lib/permissions.ts`.

| Helper | True when |
|--------|-----------|
| `isSuperadmin` | `superadmin` |
| `isAdmin` | `admin` \| `superadmin` |
| `canAccessTenantApp` | `admin` \| `mentor` \| `intern` |
| `canManageUsers` | `admin` \| `mentor` |
| `canCreateUserWithRole(actor, target)` | Never create `admin`. Admin→mentor/intern. Mentor→intern only. |
| `canCreateProject` | `admin` \| `mentor` |
| `canApproveLeave` | `admin` \| `mentor` |
| `canRequestLeave` | `intern` |
| `canViewActivity` | `admin` \| `mentor` |
| `canViewTeamDirectory` | `admin` only |
| `canManageInviteLinks` | `admin` \| `mentor` |
| `canCreateReview` | `admin` \| `mentor` |
| `canManageCohorts` | `admin` \| `mentor` \| `superadmin` |
| `canManageTaskStatuses` | `admin` \| `superadmin` |
| `canManageProjectStatuses` | `admin` \| `superadmin` |
| `canManageInternshipDurations` | `admin` \| `superadmin` |
| `canManageAssignments` | `admin` \| `mentor` |
| `canManageMailSettings` | `admin` \| `superadmin` |

**Additional page-level checks (not in `permissions.ts`):**

| Check | Where |
|-------|-------|
| Blog write UI | `isAdmin \|\| isSuperadmin` in blogs routes |
| Announcements post | `admin \|\| mentor \|\| superadmin` |
| Data / Bin pages | `role === "admin"` only (not mentor) |
| Activity page | intern redirected to `/dashboard` |
| Attendance detail `/:userId` | intern redirected to `/attendance` |
| Project edit | `project.can_edit && role !== "intern"` |
| Project task manage | admin/mentor, or intern who is project member |
| Profile internship summary / overview fetch | `role === "intern"` |

---

## 5. Route / screen inventory

### 5.1 Public

#### Login
- **Route:** `/`
- **File:** `src/routes/index.tsx`
- **Access:** Public; authenticated users redirected away
- **Purpose:** Sign in
- **Actions:** Sign in; Remember me; show/hide password; theme toggle; open Get Demo modal; link to `/signup`
- **APIs:** `auth.login` (via `signIn`); Get Demo → `leads.submit`
- **States:** loading spinner; pending-approval messaging; 429 retry countdown; toast errors

#### Signup
- **Route:** `/signup`
- **File:** `src/routes/signup.tsx`
- **Access:** Public
- **Purpose:** Self-register as intern then sign in
- **APIs:** `auth.register` (`role: "intern"`), then `signIn`
- **Fields:** name, email, password, confirm_password, terms checkbox

#### Join via invite
- **Route:** `/join/:token`
- **File:** `src/routes/join.$token.tsx`
- **Access:** Public (warns if already authenticated)
- **APIs:** `auth.getInvite`, `auth.registerViaInvite`
- **Fields:** name, email, password, confirm, phone?, department?, job_title?, joining_date

#### Server error
- **Routes:** `/500`, `/error`
- **File:** `src/components/ServerError.tsx`
- **Access:** Public

#### Not found
- **Route:** `*`
- **File:** `src/components/NotFound.tsx`

---

### 5.2 Authenticated (all roles with access)

#### Dashboard
- **Route:** `/dashboard`
- **File:** `src/routes/dashboard.tsx`
- **Access:** Any authenticated user
- **Behavior by role:**
  - `superadmin` → `PlatformDashboard` → `GET /api/superadmin/dashboard`
  - `intern` → `InternDashboard` → `GET /api/intern/dashboard`
  - `mentor` → `MentorDashboard` → `GET /api/mentor/dashboard`
  - `admin` → `AdminDashboard` → `GET /api/admin/dashboard`
  - else → `TenantDashboard` → `GET /api/dashboard` (+ projects list, optional users, intern `attendance.today`)
- **Dialogs:** `DashboardStatDialogs` (stat drill-downs)

#### Blogs list
- **Route:** `/blogs`
- **File:** `src/routes/blogs.index.tsx`
- **Access:** Authenticated
- **Write UI:** admin | superadmin (`blogs.create/update/delete`, admin list mode)
- **APIs:** `blogs.list` / `blogs.listAdminAll`; mutations create/update/delete

#### Blog detail
- **Route:** `/blogs/:slug`
- **File:** `src/routes/blogs.$slug.tsx`
- **APIs:** `blogs.getBySlug`; managers may delete

---

### 5.3 Superadmin-only

#### Tenants
- **Route:** `/tenants`
- **File:** `src/routes/tenants.tsx`
- **APIs:** `platform.organizations.list`; create; status update via dialogs
- **Dialogs:** `CreateTenantDialog`, `TenantStatusDialog`

#### Tenant detail
- **Route:** `/tenants/:orgId`
- **File:** `src/routes/tenants-detail.tsx`
- **APIs:** `platform.organizations.get`; status dialog

#### Leads
- **Route:** `/leads`
- **File:** `src/routes/leads.tsx`
- **APIs:** `leads.list` (platform); search/filter/export/view/copy email in UI

---

### 5.4 Tenant app (admin | mentor | intern)

Route guard: `TenantAppOnly` → else redirect `/dashboard`.

#### Attendance
- **Route:** `/attendance`
- **File:** `src/routes/attendance.tsx`
- **Role split:** intern → `InternAttendance`; else → `StaffAttendance`
- **Related APIs:** `attendance.*`, `adminStudents.*` / `mentorStudents.*` (staff), check-in/out FormData with photo+lat+lng
- **Capture:** global `AttendanceCaptureProvider` + header Check In/Out

#### Attendance user detail
- **Route:** `/attendance/:userId`
- **File:** `src/routes/attendance.$userId.tsx`
- **Access:** Non-intern; intern redirected to `/attendance`
- **UI:** `AdminAttendanceDetail`

#### Activity
- **Route:** `/activity`
- **File:** `src/routes/activity.tsx`
- **Access:** Not intern (redirect `/dashboard`). Sidebar only if `canViewActivity`
- **APIs:** `audit.list`, `announcements.list`

#### Announcements
- **Route:** `/announcements`
- **File:** `src/routes/announcements.tsx`
- **Post/edit/delete:** admin | mentor | superadmin
- **APIs:** `announcements.list/create/update/delete`

#### Users / My Interns
- **Route:** `/admin`
- **File:** `src/routes/admin.tsx`
- **Access:** `canManageUsers`; intern sees Restricted
- **Labels:** Admin “Users”; Mentor “My Interns”
- **APIs:** `admin.users`, `admin.internAssignments`, `toggleActive`, `deleteUser`
- **Dialogs:** `CreateUserDialog`, `EditUserDialog`, delete confirm, profile preview

#### Cohorts
- **Route:** `/cohorts`
- **File:** `src/routes/cohorts.tsx`
- **Access:** `canManageCohorts` (UI/nav primarily admin/mentor; helper also allows superadmin)
- **APIs:** cohorts CRUD + add/remove members

#### Data management
- **Route:** `/data`
- **File:** `src/routes/data.tsx`
- **Access:** `role === "admin"` only
- **UI:** `ClearDatabasePanel` → `POST /api/admin/clear-database` `{ password }`

#### Recycle bin
- **Route:** `/bin`
- **File:** `src/routes/bin.tsx`
- **Access:** admin only
- **UI:** `BinPanel` → list/restore/purge/clear

#### Intern assignments
- **Route:** `/intern-assignments`
- **File:** `src/routes/intern-assignments.tsx`
- **Access:** managers (`canManageAssignments`) or intern (submit own)
- **APIs:** `assignments.*`
- **Dialogs:** `AssignmentFormDialog`, `SubmitAssignmentDialog`, `SubmissionsReviewDialog`

#### Invite links
- **Route:** `/invite-links`
- **File:** `src/routes/invite-links.tsx`
- **Access:** `canManageInviteLinks`
- **UI:** `InternInviteLinkPanel`, `InternSignupRequestsPanel`

#### Leave
- **Route:** `/leave`
- **File:** `src/routes/leave.tsx`
- **Intern:** balance + Apply → `LeaveRequestDialog` + `MyLeave`
- **Admin/Mentor:** `ManageLeave` (approve/reject)
- **APIs:** `leave.mine`, `leave.request` (FormData), `leave.manage`, `leave.review`, `leave.balance`

#### Notifications
- **Route:** `/notifications`
- **File:** `src/routes/notifications.tsx`
- **APIs:** `notifications.list`, `markAllRead`, `delete`
- **Also:** header popover uses unread count + list

#### Profile
- **Route:** `/profile`
- **File:** `src/routes/profile.tsx`
- **Nav:** Account → My Profile (non-superadmin)
- **APIs:** `profile.get`, `profile.update`; intern also `users.overview`; export uses overview
- **Actions:** Edit Profile (dialog); Export Profile 360° Data
- **Intern-only section:** Internship Summary (projects/tasks/attendance/leave from overview)
- **Password:** not on this page (header menu)

#### Projects list
- **Route:** `/projects`
- **File:** `src/routes/projects.index.tsx`
- **Create:** `canCreateProject`
- **APIs:** `projects.list` / `search`; `projects.create`
- **Dialog:** `ProjectFormDialog`

#### Project detail
- **Route:** `/projects/:projectId`
- **File:** `src/routes/projects.$projectId.tsx`
- **APIs:** project get/update/delete; tasks CRUD; assign/unassign; comments board; links; attachments; statuses
- **Dialogs:** `ProjectFormDialog`, `TaskDialog`, assign/unassign, links, delete confirms, file preview

#### Reviews
- **Route:** `/reviews`
- **File:** `src/routes/reviews.tsx`
- **Access:** `canCreateReview` for create; manage if admin/superadmin or mentor who is reviewer
- **APIs:** `reviews.list/create/update/delete`

#### Standup
- **Route:** `/standup`
- **File:** `src/routes/standup.tsx`
- **APIs:** `standup.today`, `standup.list`, `submit`, `update`, `delete`
- **Manage others’ logs:** admin | mentor | superadmin (or own)

#### Team directory
- **Route:** `/team`
- **File:** `src/routes/team.tsx`
- **Access:** admin only (`canViewTeamDirectory`)
- **APIs:** `admin.users` by role tab

#### Task statuses (master)
- **Routes:** `/task-statuses`
- **File:** `src/routes/task-statuses.tsx`
- **Access:** `canManageTaskStatuses` (admin | superadmin)
- **APIs:** `admin.taskStatuses.*` including reorder

#### Project statuses (master)
- **Routes:** `/project-statuses`, `/admin/project-statuses`
- **File:** `src/routes/project-statuses.tsx`
- **Access:** `canManageProjectStatuses`
- **APIs:** `admin.projectStatuses.*`

#### Internship durations (master)
- **Routes:** `/internship-durations`, `/admin/internship-durations`
- **File:** `src/routes/internship-durations.tsx`
- **Access:** `canManageInternshipDurations`
- **APIs:** `admin.internshipDurations.*`

#### Mail settings
- **Route:** `/admin/settings/mail`
- **File:** `src/routes/admin.settings.mail.tsx`
- **Access:** `canManageMailSettings`
- **UI:** `MailConfigPanel`, `MailLogsPanel` → `org.smtp.*`

---

## 6. Role × page access matrix

Legend: **Y** = reachable & intended in nav/UI · **R** = route may exist under TenantAppOnly but page shows Restricted / redirects · **N** = route guard blocks or not in product path · **—** = not applicable

| Page | Intern | Mentor | Admin | Superadmin |
|------|--------|--------|-------|------------|
| Login `/` | public | public | public | public |
| Signup `/signup` | public | public | public | public |
| Join `/join/:token` | public | public | public | public |
| Dashboard | Y | Y | Y | Y (platform) |
| Blogs | Y (read) | Y (read) | Y (read+write) | Y (read+write) |
| Tenants / Leads | N | N | N | Y |
| Attendance | Y (own) | Y (staff) | Y (staff) | R (TenantAppOnly false → `/dashboard`) |
| Attendance `/:userId` | redirect | Y | Y | R |
| Activity | redirect | Y | Y | R |
| Announcements | Y (read) | Y (CRUD) | Y (CRUD) | R |
| Users `/admin` | Restricted | Y (interns) | Y | R |
| Cohorts | no nav* | Y | Y | R (*helper allows superadmin but TenantAppOnly blocks) |
| Data / Bin | N | N | Y | R |
| Assignments | Y (submit) | Y (manage) | Y (manage) | R |
| Invite links | N | Y | Y | R |
| Leave | Y (request) | Y (approve) | Y (approve) | R |
| Notifications | Y | Y | Y | R |
| Profile | Y | Y | Y | no sidebar Account link |
| Projects | Y | Y | Y | R |
| Reviews | no nav | Y | Y | R |
| Standup | Y | Y | Y | R |
| Team | N | N | Y | R |
| Task/Project statuses, Durations, Mail | N | N | Y | R (perms allow superadmin but TenantAppOnly redirects) |

**Sidebar Main Menus (from `AppSidebar.tsx`):**

| Item | Intern | Mentor | Admin | Superadmin |
|------|--------|--------|-------|------------|
| Dashboard | ✓ | ✓ | ✓ | ✓ |
| Tenants / Leads | | | | ✓ |
| Attendance / Projects / Leave / Announcements / Standup | ✓ | ✓ | ✓ | |
| Assignments (main) | ✓ | | | |
| Reviews / Cohorts / Activity | | ✓ | ✓ | |
| Users / Invite / Team / Assignments / Data / Bin | | Mentors+Invite+Assign | all | |
| Masters + Mail | | | ✓ | |
| My Profile | ✓ | ✓ | ✓ | |

---

## 7. Global chrome (header / sidebar / providers)

### AppShell
Wraps authenticated UI: sidebar + header + outlet.

### AppHeader actions
| Control | Behavior | API |
|---------|----------|-----|
| Global search (popover) | Search users/projects/tasks; navigate | `GET /api/search?q=` |
| Theme toggle | Light/dark | local theme state |
| Notifications | Unread badge; list; mark all read; delete | `notifications.*` |
| User menu → Profile | Navigate `/profile` | — (hidden for superadmin) |
| User menu → Change Password | Open `ChangePasswordDialog` | `POST /api/profile/change-password` |
| User menu → Theme style | Neo / Aurora | — |
| User menu → Logout | Confirm dialog → signOut → `/` | `POST /api/auth/logout` |
| Check In / Check Out | Intern only when applicable | `attendance.checkIn` / `checkOut` FormData |

### Providers (non-superadmin protected layout)
- `ProfilePreviewProvider` — open user 360° overview dialog (`users.overview`, leave history for interns)
- `AttendanceCaptureProvider` — camera + geolocation check-in/out dialog

---

## 8. Forms catalog

Shared limits: see [§11](#11-shared-validation-constants).

### Login form
| Field | Type | Required | Notes |
|-------|------|----------|-------|
| email | email | yes | |
| password | password | yes | |
| remember | checkbox | no | Affects Bearer persist mode when cross-origin |

**Submit:** `signIn` → `POST /api/auth/login`

### Signup form
| Field | Required | Notes |
|-------|----------|-------|
| name | yes | validateName |
| email | yes | |
| password / confirm | yes | PASSWORD_MIN 8 |
| terms | yes | checkbox |
| role | fixed | always `"intern"` in request |

### Invite join form
| Field | Required |
|-------|----------|
| name, email, password, confirm_password, joining_date | yes (as implemented) |
| phone, department, job_title | optional |

**APIs:** getInvite → registerViaInvite

### Get Demo modal (`GetDemoModal`)
**API:** `POST /api/leads` — `SubmitLeadPayload`: name, email, phone?, company?, role?, cohort_size?, message?, source?, website?

### Edit profile dialog
| Field | API field | Notes |
|-------|-----------|-------|
| phone | `phone` | Stored as `+91 <digits>` if not already `+` |
| skills | `skills` | Comma-separated string |
| bio | `bio` | |

**API:** `PUT /api/profile`

### Change password dialog
| Field | Required |
|-------|----------|
| current_password | yes |
| new_password | yes (≥8) |
| confirm_password | yes must match |

**API:** `POST /api/profile/change-password`

### Create / edit user (`CreateUserDialog` / `EditUserDialog`)
Create body `AdminCreateUserRequest`: name, email, password, role?, phone?, department?, job_title?, joining_date?, mentor_id?  
Update body `AdminUpdateUserRequest`: name?, email?, phone?, department?, job_title?, joining_date?, mentor_id?  
Role options constrained by `canCreateUserWithRole`.

### Project form (`ProjectFormDialog`)
Uses `Partial<Project>` for create/update — name, description, status, start_date, end_date, mentors, etc. as implemented in dialog.  
**APIs:** `POST/PUT /api/projects`

### Task dialog (`TaskDialog`)
`Partial<Task>` create/update under project.  
**APIs:** `POST /api/projects/:id/tasks`, `PUT /api/projects/tasks/:id`

### Leave request (`LeaveRequestDialog`)
FormData: `start_date`, `end_date`, `reason`, `leave_type?`, `attachment?`  
**API:** `POST /api/leave`

### Leave review (manage UI)
Body: `{ decision: "approved" | "rejected", comment? }`  
**API:** `POST /api/leave/:id/review`

### Standup submit / edit
Body submit: `{ date, did, plan, blockers?, mood? }`  
Update: `{ did, plan, blockers?, mood? }`  
**APIs:** `POST /api/standup`, `PUT /api/standup/:id`

### Announcement create/edit
`Partial<Announcement>` — title, body, is_pinned?, project_id?  
**APIs:** announcements create/update

### Review create/edit
`Partial<PerformanceReview>`  
**APIs:** reviews create/update

### Assignment form / submit / review
- Create/Update: `CreateAssignmentPayload` / `UpdateAssignmentPayload`
- Submit: JSON or FormData (`submission_text?`, `github_url?`, `file?`)
- Review submission: `ReviewSubmissionPayload`

### Cohort create/edit
`Partial<Cohort>` — name, description, start_date, end_date; members via add/remove APIs

### Invite link create
`{ label?, mentor_id? }` → `POST /api/admin/invite-link`

### Signup request review
`{ decision: "approved" | "rejected" }`

### Attendance manual / edit / delete
- Manual: `{ user_id, date, check_in, check_out?, status_override?, reason }`
- Update: `{ check_in?, check_out?, status_override?, reason }`
- Delete: `{ reason }` on DELETE

### Check-in / check-out
FormData: `photo` (jpeg blob), `lat`, `lng`

### Tenant create
`OrganizationCreateRequest`: name, slug, type?, timezone?, admin_name, admin_email, admin_password

### Tenant status
`{ status }` via `PUT /api/platform/organizations/:id/status`

### Task / project status masters
Create/Update payloads + reorder `{ status_ids }`

### Internship duration masters
Create/Update: title, internship_duration?/duration_months?, duration_days?, leaves, is_default?, order_index?, is_active? (update)

### Mail / SMTP
`org.smtp.get/update/test` + logs list with filters

### Clear database
`{ password }` → `POST /api/admin/clear-database`

### Blog editor
Create/Update payloads; HTML sanitized client-side before send (`sanitizeBlogHtml`)

---

## 9. Actions & buttons (by area)

### Auth / marketing
| Action | Page | Result | API |
|--------|------|--------|-----|
| Sign in | Login | Session | POST `/api/auth/login` |
| Create account | Signup | Register + login | POST `/api/auth/register` |
| Register via invite | Join | May pending approval | POST `/api/auth/invite/:token/register` |
| Get Demo | Login modal | Lead submitted | POST `/api/leads` |
| Log out | Header / Sidebar | Clear session | POST `/api/auth/logout` |

### Attendance
| Action | Who | API |
|--------|-----|-----|
| Check In / Check Out | Intern (header/capture) | POST check-in / check-out FormData |
| Export CSV / my export | Staff / intern UIs | GET export endpoints |
| Add manual record | Staff | POST `/api/attendance/manual` |
| Edit / Delete record | Staff | PUT / DELETE `/api/attendance/:id` |
| View student detail | Staff | navigate `/attendance/:userId` |

### Projects
| Action | Who | API / result |
|--------|-----|--------------|
| New Project | admin/mentor | opens form → POST `/api/projects` |
| Edit / Delete project | can_edit & not intern | PUT/DELETE |
| Export project | list/detail | GET `/api/projects/:id/export` |
| Create/Update/Delete task | managers / member intern | tasks APIs |
| Assign / Unassign intern | managers | POST/DELETE assign |
| Comments board | members | GET/POST/DELETE comments-board |
| Project links | members | GET/POST/DELETE links |
| Task attachments | | upload/list/download/delete |

### Leave
| Action | Who | API |
|--------|-----|-----|
| Apply for Leave | intern | POST `/api/leave` FormData |
| Approve / Reject | admin/mentor | POST `/api/leave/:id/review` |

### Users / invites
| Action | Who | API |
|--------|-----|-----|
| New User / Intern | admin/mentor | POST `/api/admin/users` |
| Edit user | | PUT `/api/admin/users/:id` |
| Toggle active | | POST `.../toggle` |
| Change role | | POST `.../role` |
| Delete user | admin (not self) | DELETE |
| Create/delete invite link | | invite-link APIs |
| Approve/reject signup request | | POST review |

### Assignments
| Action | Who | API |
|--------|-----|-----|
| Create/Edit/Delete assignment | admin/mentor | assignments CRUD |
| Submit solution | intern | POST `.../submit` |
| Review submissions | admin/mentor | POST submissions review |

### Standup / Reviews / Announcements
| Action | API |
|--------|-----|
| Submit/Update/Delete standup | standup POST/PUT/DELETE |
| New/Edit/Delete review | reviews POST/PUT/DELETE |
| New/Edit/Delete announcement | announcements POST/PUT/DELETE |

### Profile / password
| Action | API |
|--------|-----|
| Save profile | PUT `/api/profile` |
| Export 360° | GET `/api/users/:id/overview` then client Excel export |
| Change password | POST `/api/profile/change-password` |

### Admin ops
| Action | API |
|--------|-----|
| Restore/purge bin items | bin restore/purge/clear |
| Clear database | POST clear-database |
| Status masters CRUD/reorder | admin task/project-statuses |
| Duration tiers CRUD | internship-durations |
| SMTP save/test | org.smtp |

### Platform
| Action | API |
|--------|-----|
| Create tenant | POST organizations |
| Pause/activate tenant | PUT status |
| View/export leads | platform leads list |

### Notifications / search
| Action | API |
|--------|-----|
| Mark all read | POST mark-read |
| Delete notification | DELETE `/api/notifications/:id` |
| Header search | GET `/api/search?q=` |

---

## 10. API endpoint catalog

All paths relative to API base. Auth required unless noted. **PATCH is not used** by this client.

### Auth
| Method | Path | Client | Body / query |
|--------|------|--------|--------------|
| GET | `/api/auth/me` | `auth.me` | — |
| POST | `/api/auth/login` | `auth.login` | `{ email, password, remember }` |
| POST | `/api/auth/logout` | `auth.logout` | — |
| POST | `/api/auth/register` | `auth.register` | `{ name, email, password, confirm_password, role? }` |
| GET | `/api/auth/invite/:token` | `auth.getInvite` | — |
| POST | `/api/auth/invite/:token/register` | `auth.registerViaInvite` | name, email, passwords, phone?, department?, job_title?, joining_date |

### Dashboards
| Method | Path | Client |
|--------|------|--------|
| GET | `/api/dashboard` | `dashboard.get` |
| GET | `/api/dashboard/present-today` | `dashboard.presentToday` |
| GET | `/api/dashboard/open-tasks` | `dashboard.openTasks` |
| GET | `/api/dashboard/attendance-chart` | `dashboard.attendanceChart` (`month?`) |
| GET | `/api/intern/dashboard` | `internDashboard.get` |
| GET | `/api/mentor/dashboard` | `mentorDashboard.get` |
| GET | `/api/admin/dashboard` | `adminDashboard.get` |
| GET | `/api/superadmin/dashboard` | `superadminDashboard.get` |

### Attendance
| Method | Path | Client | Notes |
|--------|------|--------|-------|
| GET | `/api/attendance/today` | `attendance.today` | |
| POST | `/api/attendance/check-in` | `attendance.checkIn` | FormData photo,lat,lng |
| POST | `/api/attendance/check-out` | `attendance.checkOut` | FormData |
| GET | `/api/attendance/:id/photo/:kind` | path helper | kind checkin\|checkout |
| GET | `/api/attendance/history` | `attendance.history` | page, page_size, month? |
| GET | `/api/attendance/report` | `attendance.report` | intern_id?, start?, end?, page?, page_size? |
| GET | `/api/attendance/export.csv` | `attendance.exportCsv` | raw fetch |
| GET | `/api/attendance/my/export` | `attendance.exportMy` | from_date?, to_date? |
| PUT | `/api/attendance/:id` | `attendance.update` | |
| POST | `/api/attendance/manual` | `attendance.createManual` | |
| GET | `/api/attendance/:id/audit` | `attendance.auditLog` | |
| DELETE | `/api/attendance/:id` | `attendance.deleteRecord` | body `{ reason }` |

### Admin / mentor students
| Method | Path prefix | Client |
|--------|-------------|--------|
| GET | `/api/admin/students` (+ search, :userId/attendance, today, export) | `adminStudents.*` |
| GET | `/api/mentor/students` (+ same suffixes) | `mentorStudents.*` |

### Projects & tasks
| Method | Path | Client |
|--------|------|--------|
| GET/POST | `/api/projects` | list/create |
| GET | `/api/projects/search` | search |
| GET/PUT/DELETE | `/api/projects/:id` | get/update/delete |
| GET | `/api/projects/:id/export` | export |
| GET | `/api/projects/mentors` | mentors |
| GET | `/api/projects/interns` | interns |
| POST | `/api/projects/:id/assign` | `{ user_id }` |
| DELETE | `/api/projects/:id/assign/:userId` | unassign |
| GET | `/api/projects/task-statuses` | |
| GET | `/api/projects/project-statuses` | |
| POST | `/api/projects/:projectId/tasks` | |
| PUT/DELETE | `/api/projects/tasks/:taskId` | |
| GET/POST | `/api/projects/tasks/:taskId/comments` | POST FormData body+file? |
| DELETE | `/api/projects/tasks/comments/:commentId` | |
| GET/POST | `/api/projects/tasks/:taskId/attachments` | POST FormData |
| GET | `/api/projects/tasks/attachments/:id/download` | blob helpers |
| DELETE | `/api/projects/tasks/attachments/:id` | |
| GET/POST | `/api/projects/:projectId/comments-board` | POST `{ body }` |
| DELETE | `/api/projects/comments-board/:commentId` | |
| GET/POST | `/api/projects/:projectId/links` | POST `{ link, remark }` |
| DELETE | `/api/projects/links/:linkId` | |

### Leave
| Method | Path | Client |
|--------|------|--------|
| GET | `/api/leave/mine` | leave.mine |
| POST | `/api/leave` | leave.request FormData |
| GET | `/api/leave/:id/attachment` | download/view helpers |
| GET | `/api/leave/manage` | page?, status? |
| POST | `/api/leave/:id/review` | decision + comment? |
| GET | `/api/leave/balance` | |

### Admin users & invites & bin & masters
| Method | Path | Client |
|--------|------|--------|
| GET/POST | `/api/admin/users` | list/create |
| PUT/DELETE | `/api/admin/users/:id` | update/delete |
| POST | `/api/admin/users/:id/toggle` | |
| POST | `/api/admin/users/:id/role` | `{ role }` |
| GET | `/api/admin/mentors` | |
| GET | `/api/admin/intern-assignments` | |
| GET/POST | `/api/admin/invite-link` | |
| DELETE | `/api/admin/invite-link/:id` | |
| POST | `/api/admin/invite-link/regenerate` | |
| POST | `/api/admin/invite-link/deactivate` | |
| GET | `/api/admin/intern-signup-requests` | |
| POST | `/api/admin/intern-signup-requests/:id/review` | |
| POST | `/api/admin/clear-database` | `{ password }` |
| GET | `/api/admin/bin` | |
| POST | `/api/admin/bin/:id/restore` | |
| DELETE | `/api/admin/bin/:id` | purge |
| DELETE | `/api/admin/bin` | clearAll |
| CRUD+reorder | `/api/admin/task-statuses` (+ `/reorder`) | |
| CRUD+reorder | `/api/admin/project-statuses` (+ `/reorder`) | |
| CRUD | `/api/admin/internship-durations` (+ `/dropdown`) | |

### Profile / notifications / search
| Method | Path | Client |
|--------|------|--------|
| GET/PUT | `/api/profile` | profile.get/update |
| POST | `/api/profile/change-password` | |
| GET | `/api/notifications?page=` | list |
| GET | `/api/notifications/unread-count` | |
| POST | `/api/notifications/mark-read` | |
| DELETE | `/api/notifications/:id` | |
| GET | `/api/search?q=` | |

### Reviews / standup / announcements
| Method | Path |
|--------|------|
| GET/POST | `/api/reviews` |
| GET/PUT/DELETE | `/api/reviews/:id` |
| GET | `/api/standup` (filters) |
| GET | `/api/standup/today` |
| POST | `/api/standup` |
| PUT/DELETE | `/api/standup/:id` |
| GET/POST | `/api/announcements` |
| PUT/DELETE | `/api/announcements/:id` |

### Blogs / leads / audit / cohorts / assignments / users overview
| Method | Path |
|--------|------|
| GET/POST | `/api/blogs` |
| GET | `/api/blogs/:slug` |
| PUT/DELETE | `/api/blogs/:id` |
| GET | `/api/blogs/admin/all` |
| POST | `/api/leads` (public CSRF-exempt) |
| GET | `/api/platform/leads` |
| GET | `/api/audit` |
| CRUD + members | `/api/cohorts`, `/api/cohorts/:id/members/...` |
| CRUD + submit/review/attachment | `/api/assignments...` |
| GET | `/api/users/:id/overview` |
| GET | `/api/users/:id/leave` |

### Platform / org SMTP
| Method | Path |
|--------|------|
| GET/POST | `/api/platform/organizations` |
| GET | `/api/platform/organizations/:orgId` |
| PUT | `/api/platform/organizations/:orgId/status` |
| GET/PUT | `/api/org/smtp` |
| POST | `/api/org/smtp/test` |
| GET | `/api/org/smtp/logs` |

---

## 11. Shared validation constants

From `src/lib/validation.ts`:

| Constant | Value | Typical use |
|----------|-------|-------------|
| `TEXT_LIMIT_SHORT` | 100 | names, titles, departments |
| `TEXT_LIMIT_MEDIUM` | 300 | skills, remarks |
| `TEXT_LIMIT_LONG` | 1000 | comments, task descriptions |
| `TEXT_LIMIT_XLONG` | 3000 | announcement body, review feedback |
| `PASSWORD_MIN` | 8 | passwords |
| `PASSWORD_MAX` | 100 | passwords |
| `PHONE_DIGIT_LIMIT` | 10 | national digits |
| `PHONE_REGEX` | `+91` optional + 10 digits starting 6–9 | phones |
| `EMAIL_REGEX` | standard email | emails |
| `NAME_RE` | unicode letters + spaces `' - .` | names |

Helpers: `validateName`, `validateEmail`, `isValidPhone`, `nationalPhoneDigits`, `toDateInputValue`, `localIsoDate`, date-range validators used by forms.

---

## 12. Data / query layer

| Piece | Role |
|-------|------|
| `queryClient` | Shared TanStack Query client |
| `useApi` | Query wrapper with AbortSignal |
| `useApiMutation` | Mutation wrapper |
| `invalidateQueries` | Cache invalidation after writes |
| `queryKeys` | Canonical key factory (`src/lib/queryKeys.ts`) |

Mobile should mirror: authenticate → fetch with same headers → invalidate related caches after mutations → toast/error from `getErrorMessage`.

---

## 13. Explicit absences

Documented so mobile does **not** invent parity for missing features:

| Feature | Status in this frontend |
|---------|-------------------------|
| Forgot / reset password | **Absent** (no routes, APIs, or UI) |
| HTTP PATCH | **Not used** by client |
| Axios | **Not used** |
| Direct `fetch` outside `api.ts` | **None** (except via api helpers) |
| Superadmin TenantApp pages | Route guard redirects to `/dashboard` even if some `permissions.*` helpers return true for superadmin |
| Creating users with role `admin` | **Forbidden** by `canCreateUserWithRole` |
| Change password on Profile page | **Removed**; lives in header dropdown |

---

## Appendix A — Core TypeScript shapes (selected)

### `User` (session / lists)
Fields used in client: `id`, `name`, `email`, `role`, `is_active`, `bio?`, `department?`, `skills?`, `phone?`, `job_title?`, `joining_date?`, `created_at`, `session_version?`, `mentor_id?`, `mentor_name?`, `organization_id?`, `organization_name?`

### `ProfileUpdatePayload`
`bio?`, `phone?`, `skills?`

### `ChangePasswordPayload`
`current_password`, `new_password`, `confirm_password`

### `LeaveBalance`
`used`, `pending?`, `quota`, `remaining`, `available_after_pending?`

### `UserProfileOverview`
`user`, `stats`, `projects`, `tasks`, `attendance`, `interns`, optional `leave_requests`, `leave_summary`, `leave_balance`

(Full interfaces live in `src/lib/api.ts` — use that file for field-level typing when implementing mobile models.)

---

## Appendix B — Mobile implementation checklist

1. Implement auth (login/register/invite/me/logout) with cookie **or** Bearer persistence matching `VITE_API_BASE` behavior.
2. Send `Authorization`, `X-CSRF-Token` (if cookie session), and `X-Organization-Id` when org context exists.
3. Gate screens using the **matrix in §6** and helpers in §4 — do not assume extra access.
4. Reuse the same endpoints in §10; prefer FormData exactly where web does (attendance, leave, some uploads).
5. Port validation limits from §11.
6. For intern profile, load overview and show Internship Summary; hide for other roles.
7. Expose Change Password from account menu, not only profile.
8. Do not ship forgot-password unless backend + product later add it.

---

*End of reference. Prefer `src/lib/api.ts` and route files when resolving ambiguity.*
