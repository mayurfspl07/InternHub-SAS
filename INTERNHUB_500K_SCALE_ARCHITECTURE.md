# InternHub 500k-Scale Architecture Blueprint
## High-Throughput Modular Monolith Design for 500,000+ Registered Users

> **Document ID:** `INTERNHUB_500K_SCALE_ARCHITECTURE.md`  
> **Target Scale:** 500,000+ Registered Users | 5,000–20,000 Organizations | 50k–100k DAU | 5k–15k Peak CCU  
> **Core Strategy:** Horizontally Scalable FastAPI Modular Monolith + Managed MySQL + Redis Cluster + Object Storage (S3/R2) + Asynchronous Worker Queue

---

## 1. System Topology & Request Lifecycle

```text
                                  CLIENT TIER
             Web Browser (React 19 SPA) | Mobile App | Partner Integrations
                                       │
                                       ▼
                       EDGE TIER (Cloudflare CDN / WAF / DNS)
                         - Static Frontend Hosting (.js, .css, .html)
                         - DDoS Mitigation & TLS 1.3 Termination
                         - Edge Asset Caching
                                       │
                                       ▼
                     LOAD BALANCING TIER (HTTPS Load Balancer)
                                       │
                  ┌────────────────────┼────────────────────┐
                  ▼                    ▼                    ▼
          ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
          │ FastAPI #1   │     │ FastAPI #2   │     │ FastAPI #N   │
          │ (Stateless)  │     │ (Stateless)  │     │ (Stateless)  │
          └──────┬───────┘     └──────┬───────┘     └──────┬───────┘
                 │                    │                    │
                 └────────────────────┼────────────────────┘
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         │                            │                            │
         ▼                            ▼                            ▼
  ┌──────────────┐             ┌──────────────┐             ┌──────────────┐
  │ Redis        │             │ Managed      │             │ S3 / R2      │
  │ Cluster      │             │ MySQL 8.0+   │             │ Object Store │
  │ - Rate Limit │             │ - Primary DB │             │ - Selfies    │
  │ - Cache      │             │ - Read Reps  │             │ - Exports    │
  │ - Job Queue  │             └──────────────┘             └──────────────┘
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐
  │ Worker Pool  │
  │ - Geocoding  │
  │ - Push/Email │
  │ - Exports    │
  │ - Auto-sweep │
  └──────────────┘
```

---

## 2. Key Architecture Pillars

### 2.1 Pillar 1: Completely Stateless FastAPI Replicas
- **No in-process state:** In-memory sessions, local upload folders, and in-memory rate limits are eliminated.
- **Horizontal Elasticity:** Any replica can terminate without dropping user sessions or job state.
- **Railway / Container Deployment:** Traffic automatically distributes across active replicas.

### 2.2 Pillar 2: Direct-to-Storage Presigned Uploads
- Attendance selfies (1–2 MB each) bypass the FastAPI process entirely:
  1. Client calls `POST /api/attendance/upload-url` $\rightarrow$ FastAPI generates S3/R2 presigned PUT URL.
  2. Client uploads photo directly to Cloudflare R2 / AWS S3.
  3. Client posts check-in metadata (`object_key`, `lat`, `lng`) to `POST /api/attendance/check-in`.
- **Bandwidth & CPU Savings:** Prevents 50,000 concurrent 10:00 AM check-in photos from saturating backend bandwidth.

### 2.3 Pillar 3: Asynchronous Non-Blocking Attendance Pipeline
```text
Client Check-In (10:00 AM Rush)
   │
   ├── 1. Validate Auth & Tenant Membership (Redis Cache / DB)
   ├── 2. Save Attendance Record (lat, lng, photo_key, status)
   ├── 3. Enqueue Background Jobs (Redis Queue)
   │      ├── Job A: Reverse Geocode (with rounded-lat/lng cache)
   │      ├── Job B: Audit Log Persistence
   │      └── Job C: Push / Webhook Notifications
   └── 4. Return HTTP 200 OK (< 30ms response time)
```

### 2.4 Pillar 4: Multi-Tenant Query-Shaped Composite Indexing
All high-volume tables use composite indexes ordered by `(organization_id, ...)`:
- `attendance`: `UNIQUE (organization_id, user_id, date)` and `INDEX (organization_id, date, status)`
- `tasks`: `INDEX (organization_id, project_id, status)` and `INDEX (organization_id, assigned_to, deadline)`
- `audit_logs`: `INDEX (organization_id, created_at)` and `INDEX (organization_id, actor_id)`
- `notifications`: `INDEX (organization_id, user_id, is_read, created_at)`
- `bin_items`: `INDEX (organization_id, expires_at, restored_at)`

### 2.5 Pillar 5: Redis Distributed Rate Limiting & Multi-Level Caching
- **Distributed Login Rate Limiter:** Keyed as `rate_limit:auth:{ip}` and `rate_limit:user:{user_id}`.
- **Tenant Permission Cache:** `org_perms:{membership_id}` (TTL: 300s, invalidated on role change).
- **Dashboard Analytics Cache:** `dashboard:{organization_id}:{role}` (TTL: 60s).

---

## 3. Dedicated Background Worker Architecture

APScheduler is decoupled from API worker processes into a dedicated, single-instance scheduler that dispatches idempotent tasks to a Redis worker queue:
1. `auto_checkout_job`: Dispatched at tenant-local midnight.
2. `overdue_tasks_job`: Dispatched at tenant-local 00:10.
3. `bin_purge_job`: Dispatched at tenant-local 00:05.
4. `async_export_worker`: Handles large CSV/Excel report generation and uploads result to object storage.
