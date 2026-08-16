# InternHub Modular Monolith Project Structure

> **Architectural Paradigm:** Domain-Driven Modular Monolith with Clean Architecture & Multi-Tenancy  
> **Framework:** FastAPI + SQLAlchemy + Pydantic v2 + MySQL + Redis  

---

## 1. Directory Tree & Layering Overview

```text
internhub-backend/
│
├── app/                        # Main Application Package (Modular Monolith)
│   ├── core/                   # Cross-cutting foundational infrastructure
│   │   ├── constants.py        # System enums (UserRole, Statuses, Types)
│   │   ├── security.py         # Passwords, token sign/verify, CSRF
│   │   ├── permissions.py      # RBAC permission registry & evaluate()
│   │   ├── tenant.py           # CurrentContext & TenantContext DI engine
│   │   ├── exceptions.py       # Domain & HTTP exception types
│   │   └── pagination.py       # Pagination models and calculations
│   │
│   ├── db/                     # Persistence & Database Base Layer
│   │   └── mixins.py           # TenantMixin, TimestampMixin, SoftDeleteMixin
│   │
│   └── modules/                # Self-Contained Business Domains
│       ├── attendance/         # Check-in/out, GPS/Selfie rules, calculator.py, policies.py
│       ├── leave/              # Leave balances, calendar math, calculator.py
│       ├── projects/           # Projects, assignments, policies.py
│       ├── tasks/              # Kanban tasks, drag-drop status, policies.py
│       ├── organizations/      # Workspace profile & dynamic settings
│       └── platform_admin/     # Super Admin metrics & tenant provisioning
│
├── services/                   # High-Throughput Distributed Services
│   ├── redis_service.py        # Redis rate limiter, distributed caching, locks
│   └── storage_service.py      # S3/Cloudflare R2 presigned URLs & local storage
│
├── repositories/               # Tenant-Scoped Data Access Layer
│   └── tenant_repository.py    # Auto-scoping base repository enforcing organization_id
│
├── routes/                     # HTTP Endpoints Layer
│   └── api/                    # API Route Controllers
│       ├── auth.py             # Login, invite links, session validation
│       ├── org.py              # Organization settings & workspace management
│       ├── platform.py         # Platform Super Admin metrics & management
│       ├── attendance.py       # Attendance operations
│       ├── projects.py         # Projects & Kanban task operations
│       ├── leave.py            # Leave request and review operations
│       ├── search.py           # Multi-entity tenant search
│       └── ...                 # Additional API routers
│
├── migrations/                 # Schema Migration & Backfill Engine
│   └── 20260815_multi_tenant_saas.py # Multi-tenant schema DDL & default org backfill
│
├── tests/                      # Automated Verification & Test Suites
│   ├── test_tenant_security.py # Cross-tenant IDOR & boundary tests
│   ├── test_attendance_*.py    # Attendance domain tests
│   ├── test_leave_*.py         # Leave domain tests
│   └── test_project_*.py       # Projects & tasks domain tests
│
├── config.py                   # Environment configuration loader
├── database.py                 # SQLAlchemy SessionLocal & connection engine
├── dependencies.py             # Central FastAPI dependency injection
├── main.py                     # Application entry point, lifespan, & router loop
├── migrate_db.py               # Auto-migration runner on startup
├── models.py                   # Complete SQLAlchemy ORM Domain Models
├── utils.py                    # Domain utilities and calculation helpers
├── requirements.txt            # Python dependencies
└── RAILWAY.md                  # Deployment & container environment guide
```

---

## 2. Standardized Request Lifecycle

Every API call traverses a strict, predictable pipeline:

```text
HTTP Request
     │
     ▼
[CORS / Correlation ID Middleware]
     │
     ▼
[Authentication Dependency] (Decode JWT Token → Resolve User)
     │
     ▼
[Tenant Resolution Dependency] (Extract Header / Org → Verify Active Membership)
     │
     ▼
[Authorization Policy Layer] (Evaluate CurrentContext.has_permission())
     │
     ▼
[Domain Router Handler] (Parse & Validate Pydantic Schema)
     │
     ▼
[Domain Service / Calculator] (Pure Business Logic Execution)
     │
     ▼
[Tenant Repository] (Auto-inject WHERE organization_id = :org_id)
     │
     ▼
[SQLAlchemy ORM / MySQL DB / Redis Cache]
     │
     ▼
HTTP JSON Response
```

---

## 3. Core Architectural Rules

1. **Strict Multi-Tenancy:** Every domain query for tenant resources must begin with `organization_id` or utilize `TenantRepository`. No global queries on tenant-owned entities.
2. **Stateless API Replicas:** No in-memory state or sticky sessions. Caching, rate limiting, and locks are handled via `services.redis_service`. File uploads use direct presigned URLs via `services.storage_service`.
3. **Thin HTTP Routers:** Routers only handle HTTP deserialization and response formatting. Complex business math and validation belong in `calculator.py` or domain services.
4. **Decoupled Authorization Policies:** RBAC and entity-level permission rules are defined in `policies.py`, not inlined across endpoints.
