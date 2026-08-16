# InternHub B2B SaaS Test Scenarios & Verification Matrix

> **Document ID:** `INTERNHUB_SAAS_TEST_SCENARIOS.md`  
> **Status:** Test Specification & IDOR Boundary Verification

---

## 1. Cross-Tenant Security & IDOR Isolation Test Suite

A dedicated automated test suite (`tests/test_tenant_security.py`) validates tenant isolation across two test organizations: **`Org_Alpha` (ID: 1)** and **`Org_Beta` (ID: 2)**.

| Test Case ID | Actor | Action Under Test | Target Tenant Resource | Expected Assertion |
| :--- | :--- | :--- | :--- | :--- |
| `SEC-001` | Admin Alpha | Read Project Details (`GET /api/projects/{beta_project_id}`) | Org Beta Project | **`404 Not Found`** |
| `SEC-002` | Mentor Alpha | Drag/Drop Task (`PATCH /api/projects/tasks/{beta_task_id}/status`) | Org Beta Task | **`404 Not Found`** |
| `SEC-003` | Admin Alpha | Edit Intern Attendance (`PUT /api/attendance/{beta_att_id}`) | Org Beta Attendance | **`404 Not Found`** |
| `SEC-004` | Mentor Alpha | Review Leave Request (`POST /api/leave/{beta_leave_id}/review`) | Org Beta Leave Request | **`404 Not Found`** |
| `SEC-005` | Admin Alpha | Restore Recycle Bin Item (`POST /api/admin/bin/{beta_bin_id}/restore`) | Org Beta Bin Item | **`404 Not Found`** |
| `SEC-006` | Admin Alpha | Query Audit Feed (`GET /api/audit`) | Org Beta Activity Logs | **0 records from Beta** |
| `SEC-007` | Intern Alpha | Workspace Search (`GET /api/search?q=BetaSecret`) | Org Beta Project Title | **0 results from Beta** |
| `SEC-008` | Intern Alpha | Download Staff Report (`GET /api/attendance/report?intern_id={beta_id}`) | Org Beta Intern | **`403/404 Forbidden`** |
| `SEC-009` | Org Admin | Attempt Database Clear (`POST /api/admin/clear-database`) | Application Database | **`404 Not Found` (Endpoint Removed)** |
| `SEC-010` | User Alpha | Direct Object Photo Access (`GET /api/attendance/{beta_att_id}/photo/checkin`) | Org Beta Selfie | **`404 Not Found`** |

---

## 2. Regression Test Scenarios

All 98 existing baseline unit and integration tests must pass without modification or regression:
- `test_attendance_manual.py` (13 tests)
- `test_attendance_report.py` (7 tests)
- `test_attendance_window_30d.py` (5 tests)
- `test_audit_log.py` (4 tests)
- `test_comment_timestamps.py` (3 tests)
- `test_determine_status.py` (11 tests)
- `test_leave_attendance_sync.py` (4 tests)
- `test_overdue_task_notifications.py` (6 tests)
- `test_profile_leave.py` (4 tests)
- `test_project_collaboration.py` (20 tests)
- `test_project_multi_mentor.py` (5 tests)
- `test_railway_config.py` (4 tests)
- `test_recycle_bin.py` (4 tests)
- `test_task_ownership.py` (8 tests)
