# InternHub B2B SaaS API Mapping

> **Document ID:** `INTERNHUB_SAAS_API_MAPPING.md`
> **Status:** Implemented — verified against the code and production on 2026-09-27.
> Full endpoint reference: [`docs/API_DOCUMENTATION.md`](docs/API_DOCUMENTATION.md). Interactive reference: `/docs`.

---

## 1. Tenant resolution

The API serves 220 route/method pairs under `/api/*` (plus the dashboard shortcuts `/admin|mentor|intern|superadmin/dashboard`).
Every signed-in request runs in one organization:

1. `X-Organization-Id` header, honoured only when the user is an active member of that organization;
2. otherwise the user's first active membership.

Records from another organization are answered as `404` (or `422` when referenced in a request body). Members of a
suspended or cancelled organization get `403`. Accounts created through public self-registration belong to no
organization and see no tenant data until an org admin adds them or they join with an invite link. Platform admins
are not bound to one organization.

### 1.1 Platform administration (`/api/platform/*`, platform admins only)
- `GET /api/platform/metrics`: platform-wide counts.
- `GET /api/platform/organizations`: list organizations (`page`, `page_size`, `search`).
- `POST /api/platform/organizations`: onboard an organization with its first org admin.
- `GET /api/platform/organizations/{org_id}`: configuration, settings and members.
- `PUT /api/platform/organizations/{org_id}/status`: `active`, `trial`, `suspended` or `cancelled`.
- `GET /api/platform/leads`: marketing leads captured by `POST /api/leads`.
- `GET /api/superadmin/dashboard` (also `/api/dashboard/superadmin`, `/superadmin/dashboard`).

### 1.2 Organization management (`/api/org/*`)
- `GET /api/org/current`: active organization, settings, and the caller's membership and role.
- `PUT /api/org/profile`: name, timezone, logo URL (Admin).
- `PUT /api/org/settings`: shift hours, cut-offs, leave quota, selfie/GPS flags, auto-checkout (Admin).
- `GET /api/org/members`: members with contact and stipend details (Admin, Mentor).
- `POST /api/org/members`: add a new or existing user to the organization (Admin; Mentors add interns only).
- `GET|PUT /api/org/smtp`, `POST /api/org/smtp/test`, `GET /api/org/smtp/logs`: tenant e-mail settings and log (Admin).

Member details are edited through `PUT /api/admin/users/{user_id}`; there is no `PUT /api/org/members/{id}`.

### 1.3 Tenant scope of the existing APIs
| Route prefix | Handlers | Tenant scope rule |
| :--- | :--- | :--- |
| `/api/auth/*` | Login, logout, public register, invite info and invite register, me | Invite sign-ups join the link's organization on approval; public sign-ups join none. |
| `/api/profile*` | Profile, `internship_summary`, change password | The caller's own record. |
| `/api/admin/users`, `/api/admin/mentors`, `/api/users/*` | User management and dropdowns | Users of the active organization; mentors see their own interns. |
| `/api/admin/invite-link*`, `/api/admin/intern-signup-requests*` | Invite links and sign-up approval | Links and requests of the active organization; regenerate/deactivate never touch other tenants. |
| `/api/admin/task-statuses`, `/api/admin/project-statuses`, `/api/admin/internship-durations` | Masters | Per organization. |
| `/api/admin/bin*` | Recycle bin list, restore, purge, clear | Bin items carry the deleting organization; clear-all empties only the caller's bin. |
| `/api/admin/clear-database` | Global data wipe | Platform admins only. |
| `/api/admin/students/*`, `/api/mentor/students/*` (+ `/attendance/*` aliases) | Student attendance overview, today, detail, search, CSV | Active organization; mentors see their own interns. |
| `/api/attendance/*` | Check-in/out, history, report, exports, manual entry, edits, auto-checkout | Rows are filed under the member's organization; auto-checkout covers only the caller's organization. |
| `/api/projects/*`, `/api/tasks/*` | Projects, tasks, comments, links, attachments, statuses | Project, task, comment and attachment ids are checked against the active organization; assignees and mentors must belong to it. |
| `/api/leave/*` | Apply, review, balance, lists, attachments | Organization quota and settings; reviewers are the org's admins and the intern's mentor. |
| `/api/assignments/*` | Assignments, attachments, submissions, grading | Assignment and submission ids, and referenced projects, cohorts and users, are checked against the organization. |
| `/api/cohorts/*` | Cohorts and members | Filtered by `organization_id`. |
| `/api/standup*` | Daily standups | Filed under the active organization. |
| `/api/reviews/*` | Performance reviews | Filed under the active organization. |
| `/api/announcements/*` | Announcements | Organization-wide or for one of the organization's projects. |
| `/api/blogs*` | Public blog and admin editor | Published posts are public; drafts and editing are per organization. |
| `/api/notifications/*` | Notifications, unread count, SSE stream | The recipient's own notifications. |
| `/api/audit` | Activity trail | Entries are filed under the organization they happened in. |
| `/api/search` | Global search | Active organization, scoped by role. |
| `/api/dashboard/*` and dashboard shortcuts | Role dashboards, present-today, open tasks, attendance chart | Aggregated for the active organization. |
| `/api/upload/*` | Avatar, generic image, organization logo | Organization logo: Admin of the active organization. |
