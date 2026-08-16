# InternHub B2B SaaS Database Schema Specification

> **Document ID:** `INTERNHUB_SAAS_DATABASE_SCHEMA.md`  
> **Status:** Target Schema Definition

---

## 1. Multi-Tenant Schema Map

### 1.1 Core Platform & Tenancy Tables

```sql
CREATE TABLE organizations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    slug VARCHAR(64) UNIQUE NOT NULL,
    name VARCHAR(160) NOT NULL,
    type ENUM('business', 'educational_institute') NOT NULL DEFAULT 'business',
    status ENUM('active', 'suspended', 'trial', 'cancelled') NOT NULL DEFAULT 'active',
    timezone VARCHAR(64) NOT NULL DEFAULT 'Asia/Kolkata',
    logo_url VARCHAR(300) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at DATETIME NULL,
    INDEX idx_org_slug (slug),
    INDEX idx_org_status (status)
);

CREATE TABLE organization_settings (
    organization_id INT PRIMARY KEY,
    shift_start TIME NOT NULL DEFAULT '10:00:00',
    shift_end TIME NOT NULL DEFAULT '19:00:00',
    late_cutoff TIME NOT NULL DEFAULT '10:30:00',
    noon_cutoff TIME NOT NULL DEFAULT '12:00:00',
    checkin_block TIME NOT NULL DEFAULT '20:00:00',
    full_day_hours DECIMAL(4,2) NOT NULL DEFAULT 7.00,
    half_day_hours DECIMAL(4,2) NOT NULL DEFAULT 5.00,
    leave_quota_days INT NOT NULL DEFAULT 15,
    advance_leave_days INT NOT NULL DEFAULT 1,
    require_attendance_selfie BOOLEAN NOT NULL DEFAULT TRUE,
    require_attendance_gps BOOLEAN NOT NULL DEFAULT TRUE,
    auto_checkout_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE
);

CREATE TABLE organization_memberships (
    id INT AUTO_INCREMENT PRIMARY KEY,
    organization_id INT NOT NULL,
    user_id INT NOT NULL,
    role VARCHAR(40) NOT NULL, -- 'org_admin', 'mentor', 'intern', 'faculty'
    department VARCHAR(120) NULL,
    job_title VARCHAR(120) NULL,
    joining_date DATE NULL,
    mentor_membership_id INT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    activated_at DATETIME NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at DATETIME NULL,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (mentor_membership_id) REFERENCES organization_memberships(id) ON DELETE SET NULL,
    UNIQUE KEY uq_org_user (organization_id, user_id),
    INDEX idx_membership_org_role (organization_id, role)
);
```

### 1.2 Tenant-Owned Entities (with `organization_id`)

All domain entities include `organization_id` foreign keys with cascade deletion and compound indexing `(organization_id, ...)`:
- `projects` (`organization_id`, `name`, `status`, `start_date`, `end_date`, `mentor_id`, `created_at`, `is_deleted`)
- `attendance` (`organization_id`, `user_id`, `date`, `check_in`, `check_out`, `status`, `hours_worked`, `check_in_photo`, `check_in_lat`, `check_in_lng`)
- `tasks` (`organization_id`, `project_id`, `created_by_id`, `assigned_to`, `title`, `deadline`, `status`, `priority`)
- `leave_requests` (`organization_id`, `user_id`, `start_date`, `end_date`, `reason`, `leave_type`, `status`, `reviewed_by`)
- `standup_logs` (`organization_id`, `user_id`, `date`, `did`, `plan`, `blockers`, `mood`)
- `announcements` (`organization_id`, `project_id`, `author_id`, `title`, `body`, `is_pinned`)
- `cohorts` (`organization_id`, `name`, `description`, `start_date`, `end_date`, `is_active`)
- `performance_reviews` (`organization_id`, `intern_id`, `reviewer_id`, `project_id`, `period`, `rating`)
- `intern_invite_links` (`organization_id`, `token`, `label`, `mentor_id`, `usage_count`, `is_active`)
- `notifications` (`organization_id`, `user_id`, `message`, `link`, `is_read`)
- `audit_logs` (`organization_id`, `actor_id`, `action`, `verb`, `target`, `project_id`, `affected_user_id`)
- `bin_items` (`organization_id`, `entity_type`, `entity_id`, `title`, `deleted_by_id`, `expires_at`, `snapshot_json`)
