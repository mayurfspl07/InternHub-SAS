# InternHub B2B SaaS API Mapping

> **Document ID:** `INTERNHUB_SAAS_API_MAPPING.md`  
> **Status:** Target API Specification

---

## 1. API Mapping & Tenant Resolution

All existing 62 endpoints remain backward-compatible at their routes (`/api/*`) while resolving tenant context automatically via the `RequestContext` dependency (`X-Organization-Id` header with automatic fallback to primary active membership).

### 1.1 New Platform Administration APIs (`/api/platform/*`)
- `GET /api/platform/organizations`: List all SaaS organizations with status and metrics.
- `POST /api/platform/organizations`: Onboard a new tenant organization with admin credentials.
- `GET /api/platform/organizations/{id}`: Inspect organization configuration and statistics.
- `PUT /api/platform/organizations/{id}/status`: Suspend, activate, or archive a tenant.

### 1.2 New Organization Management APIs (`/api/org/*`)
- `GET /api/org/current`: Get active organization profile and settings.
- `PUT /api/org/settings`: Update tenant shift hours, leave quotas, and verification requirements.
- `GET /api/org/members`: List all members in active organization.
- `POST /api/org/members`: Invite/add new member to active organization.
- `PUT /api/org/members/{id}`: Update membership role, department, or assigned mentor.

### 1.3 Tenant-Scoped Existing API Mapping
| Route Prefix | Existing Handlers | SaaS Tenant Scope Rule |
| :--- | :--- | :--- |
| `/api/auth/*` | Login, Logout, Register, Me, Invite | Resolves memberships; Me returns active organization list |
| `/api/admin/*` | User management, Bin, Invites, **Task Status Master (`/api/admin/task-statuses`)** | Scoped to active `organization_id`; Bin items & Status Buckets isolated to tenant |
| `/api/admin/students/*` | Admin student attendance overview, today live, detail, search, CSV export | Scoped to active tenant; full visibility for admins |
| `/api/mentor/students/*` | Mentor student attendance overview, today live, mentee detail, search, CSV export | Scoped to active tenant; strictly filtered to assigned mentees |
| `/api/attendance/*` | Check-in, Check-out, History, Reports, Personal Export (`/my/export`), Manual | Shift rules read from `organization_settings`; timestamps converted to IST (`Asia/Kolkata`) |
| `/api/projects/*` | Projects, Tasks, Comments, Links, **Task Attachments (`/tasks/{id}/attachments`)**, **Task Statuses** | Project, task, attachment, and comment queries bound to active `organization_id` |
| `/api/leave/*` | Requests, Reviews, Quota Balance, **Leave Attachments (`/{id}/attachment`)** | Quota and sync rules read from `organization_settings`; optional supporting doc attachment |
| `/api/profile/*` | Profile details, password update, **Internship Period Visibility (`internship_summary`)** | Profile enriched with start/end date, duration, approved leaves, and leave balance |
| `/api/standup/*` | Daily log submission and history | Standup records bound to active `organization_id` |
| `/api/cohorts/*` | Cohorts and member associations | Cohorts filtered by `organization_id` |
| `/api/reviews/*` | Performance reviews | Filtered and saved under active `organization_id` |
| `/api/announcements/*`| Broadcast announcements | Scoped to organization and optional project |
| `/api/notifications/*`| User push notifications | Scoped to `organization_id` and recipient |
| `/api/audit/*` | Activity audit trail | Scoped to tenant `organization_id` |
| `/api/dashboard/*`, `/api/admin/dashboard`, `/api/mentor/dashboard`, `/api/intern/dashboard`, `/api/superadmin/dashboard` | Role-specific single-response dashboards, 30-day analytics, **Internship Summary & IST Attendance** | Aggregated strictly for active `organization_id` |
