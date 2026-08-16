# InternHub B2B SaaS Migration Plan
## Step-by-Step Transition & Execution Strategy

> **Document ID:** `INTERNHUB_SAAS_MIGRATION_PLAN.md`  
> **Status:** Approved Execution Blueprint

---

## 1. Migration Overview & Core Tenet

The migration follows a strict zero-downtime, regression-free principle:
```text
CURRENT SINGLE-TENANT BASELINE
       ↓
STEP 1: Schema Migration & Default Tenant Creation
       ↓
STEP 2: Data Backfill & Foreign Key Binding
       ↓
STEP 3: Auth & RequestContext Resolution Engine
       ↓
STEP 4: Service & Tenant Repository Layer
       ↓
STEP 5: Route Adaptation & Policy Enforcement
       ↓
STEP 6: Storage Abstraction (S3/R2 Support)
       ↓
STEP 7: Regression & Cross-Tenant IDOR Testing
       ↓
PRODUCTION MULTI-TENANT SAAS
```

---

## 2. Step-by-Step Transition Modules

### Step 1: Database Migration (Alembic Pipeline)
- **Current:** Startup schema sync via `migrate_db.py`.
- **Problem:** Dynamic schema modifications in production lead to table locks and lack migration rollback history.
- **Target:** Alembic version-controlled migrations.
- **Actions:**
  1. Add `organizations`, `organization_memberships`, `organization_settings` tables.
  2. Add `organization_id` column to: `projects`, `attendance`, `tasks`, `leave_requests`, `standup_logs`, `announcements`, `cohorts`, `performance_reviews`, `intern_invite_links`, `notifications`, `audit_logs`, `bin_items`.
  3. Create "Default Workspace" (`id=1`, `slug='default'`, `type='business'`).
  4. Backfill all existing records with `organization_id = 1`.
  5. Migrate all existing `users` into `organization_memberships` for `organization_id = 1`.

### Step 2: Authentication & Context Resolution
- **Current:** `get_optional_user` returns `User` based on token.
- **Problem:** No organization context or tenant permission binding.
- **Target:** `get_request_context` returns `RequestContext(user, organization, membership, role, permissions, settings)`.
- **Backward Compatibility:** If `X-Organization-Id` is omitted, automatically defaults to the user's primary active membership.

### Step 3: Service & Tenant Repository Layer
- **Current:** Direct ORM calls with manual `user.mentor_id` or `user.id` filters in routers.
- **Problem:** High risk of IDOR or missed tenant filter on newly added endpoints.
- **Target:** All data access delegated to `TenantRepository(db, org_id)`.

### Step 4: Route Adaptations (62 Endpoints)
- **Current:** Endpoints perform manual role checks and query global tables.
- **Target:** All endpoints inject `RequestContext` and execute through tenant repositories.

### Step 5: Background Jobs Tenant Iteration
- **Current:** Schedulers run once globally at fixed Asia/Kolkata midnight.
- **Target:** APScheduler iterates over active organizations and triggers based on `org.timezone`.

### Step 6: Dangerous Endpoint Remediation
- **Current:** `POST /api/admin/clear-database` exposed as an HTTP route.
- **Target:** Removed from API; moved to isolated CLI script.
