# InternHub B2B SaaS Role & Permission Matrix

> **Document ID:** `INTERNHUB_SAAS_ROLE_PERMISSION_MATRIX.md`  
> **Status:** Target Permission Matrix

---

## 1. Granular Permission Mapping

| Granular Permission Code | Platform Super Admin | Organization Admin | Mentor / Faculty | Intern / Student | Description |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `platform.orgs.manage` | ✅ | ❌ | ❌ | ❌ | Create, suspend, view all SaaS organizations |
| `platform.metrics.view` | ✅ | ❌ | ❌ | ❌ | View SaaS platform-wide performance metrics |
| `org.settings.manage` | ❌ | ✅ | ❌ | ❌ | Configure tenant shift, leave, and verification policies |
| `org.members.manage` | ❌ | ✅ | ❌ | ❌ | Add, edit, activate/deactivate tenant members |
| `org.roles.assign` | ❌ | ✅ | ❌ | ❌ | Assign/mutate membership roles within organization |
| `attendance.view_all` | ❌ | ✅ | ❌ | ❌ | View organization-wide staff attendance reports |
| `attendance.view_scoped`| ❌ | ✅ | ✅ (Mentees) | ✅ (Self) | View attendance history |
| `attendance.checkin` | ❌ | ✅ | ✅ | ✅ | Submit daily shift check-in/out with selfie & GPS |
| `attendance.correct` | ❌ | ✅ | ✅ (Mentees) | ❌ | Manually adjust or backfill attendance records |
| `attendance.override` | ❌ | ✅ | ❌ | ❌ | Set attendance status override (`on_leave`, `excused`) |
| `projects.create` | ❌ | ✅ | ✅ | ❌ | Create projects within active organization |
| `projects.edit` | ❌ | ✅ | ✅ (Assigned) | ❌ | Edit project properties and staffing |
| `tasks.create` | ❌ | ✅ | ✅ | ✅ (Project) | Create tasks on staffed projects |
| `tasks.move_status` | ❌ | ✅ | ✅ | ✅ (Project) | Transition task status on Kanban board |
| `leave.request` | ❌ | ❌ | ❌ | ✅ | Submit advance leave requests within annual quota |
| `leave.review` | ❌ | ✅ | ✅ (Mentees) | ❌ | Approve/reject intern leave requests |
| `standup.log` | ❌ | ✅ | ✅ | ✅ (Today) | Submit daily standup log entries |
| `reviews.create` | ❌ | ✅ | ✅ | ❌ | Submit periodic 1–5 performance evaluations |
| `cohorts.manage` | ❌ | ✅ | ✅ | ❌ | Create and manage intern cohorts |
| `announcements.manage` | ❌ | ✅ | ✅ (Project) | ❌ | Broadcast announcements to organization or project |
| `bin.restore_purge` | ❌ | ✅ | ❌ | ❌ | View, restore, or purge items from tenant recycle bin |
| `audit.view` | ✅ (Platform) | ✅ (Tenant) | ✅ (Scoped) | ✅ (Scoped) | View scoped activity audit trail |
