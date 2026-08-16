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
| `/api/admin/*` | User management, Bin, Invites | Scoped to active `organization_id`; Bin items isolated to tenant |
| `/api/attendance/*` | Check-in, Check-out, History, Reports, Manual | Shift rules read from `organization_settings`; records filtered by `organization_id` |
| `/api/projects/*` | Projects, Tasks, Comments, Links | Project and task queries bound to active `organization_id` |
| `/api/leave/*` | Requests, Reviews, Quota Balance | Quota and sync rules read from `organization_settings` |
| `/api/standup/*` | Daily log submission and history | Standup records bound to active `organization_id` |
| `/api/cohorts/*` | Cohorts and member associations | Cohorts filtered by `organization_id` |
| `/api/reviews/*` | Performance reviews | Filtered and saved under active `organization_id` |
| `/api/announcements/*`| Broadcast announcements | Scoped to organization and optional project |
| `/api/notifications/*`| User push notifications | Scoped to `organization_id` and recipient |
| `/api/audit/*` | Activity audit trail | Scoped to tenant `organization_id` |
| `/api/dashboard/*` | KPI cards and 30-day analytics | Aggregated strictly for active `organization_id` |
