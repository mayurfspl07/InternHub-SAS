"""Multi-tenant SaaS migration.

Creates organizations, organization_settings, and organization_memberships.
Adds organization_id columns and backfills existing workspace records into a default organization.
"""
from datetime import datetime, timezone
from sqlalchemy import inspect, text
from sqlalchemy.engine import Engine

TENANT_TABLES = (
    "attendance",
    "projects",
    "tasks",
    "leave_requests",
    "standup_logs",
    "announcements",
    "cohorts",
    "performance_reviews",
    "intern_invite_links",
    "notifications",
    "audit_logs",
    "bin_items",
)


def _add_column_if_missing(connection, table: str, column: str, ddl: str) -> None:
    connection.execute(text(f"ALTER TABLE `{table}` ADD COLUMN `{column}` {ddl}"))


def upgrade(engine: Engine) -> None:
    inspector = inspect(engine)
    is_sqlite = engine.dialect.name == "sqlite"

    # 1. Create organizations table if missing
    if not inspector.has_table("organizations"):
        with engine.begin() as conn:
            if is_sqlite:
                conn.execute(
                    text(
                        """
                        CREATE TABLE `organizations` (
                            `id` INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                            `slug` VARCHAR(64) NOT NULL UNIQUE,
                            `name` VARCHAR(160) NOT NULL,
                            `type` VARCHAR(40) NOT NULL DEFAULT 'business',
                            `status` VARCHAR(20) NOT NULL DEFAULT 'active',
                            `timezone` VARCHAR(64) NOT NULL DEFAULT 'Asia/Kolkata',
                            `logo_url` VARCHAR(300) NULL,
                            `created_at` DATETIME NOT NULL,
                            `is_deleted` BOOL NOT NULL DEFAULT 0,
                            `deleted_at` DATETIME NULL
                        )
                        """
                    )
                )
            else:
                conn.execute(
                    text(
                        """
                        CREATE TABLE `organizations` (
                            `id` INTEGER NOT NULL AUTO_INCREMENT,
                            `slug` VARCHAR(64) NOT NULL,
                            `name` VARCHAR(160) NOT NULL,
                            `type` VARCHAR(40) NOT NULL DEFAULT 'business',
                            `status` VARCHAR(20) NOT NULL DEFAULT 'active',
                            `timezone` VARCHAR(64) NOT NULL DEFAULT 'Asia/Kolkata',
                            `logo_url` VARCHAR(300) NULL,
                            `created_at` DATETIME NOT NULL,
                            `is_deleted` BOOL NOT NULL DEFAULT 0,
                            `deleted_at` DATETIME NULL,
                            PRIMARY KEY (`id`),
                            UNIQUE KEY `uq_organizations_slug` (`slug`),
                            INDEX `ix_organizations_slug` (`slug`)
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """
                    )
                )

    # 2. Create organization_settings table if missing
    if not inspector.has_table("organization_settings"):
        with engine.begin() as conn:
            if is_sqlite:
                conn.execute(
                    text(
                        """
                        CREATE TABLE `organization_settings` (
                            `organization_id` INTEGER NOT NULL PRIMARY KEY,
                            `shift_start` VARCHAR(10) NOT NULL DEFAULT '10:00:00',
                            `shift_end` VARCHAR(10) NOT NULL DEFAULT '19:00:00',
                            `late_cutoff` VARCHAR(10) NOT NULL DEFAULT '10:30:00',
                            `noon_cutoff` VARCHAR(10) NOT NULL DEFAULT '12:00:00',
                            `checkin_block` VARCHAR(10) NOT NULL DEFAULT '20:00:00',
                            `full_day_hours` FLOAT NOT NULL DEFAULT 7.0,
                            `half_day_hours` FLOAT NOT NULL DEFAULT 5.0,
                            `leave_quota_days` INTEGER NOT NULL DEFAULT 15,
                            `advance_leave_days` INTEGER NOT NULL DEFAULT 1,
                            `require_attendance_selfie` BOOL NOT NULL DEFAULT 1,
                            `require_attendance_gps` BOOL NOT NULL DEFAULT 1,
                            `auto_checkout_enabled` BOOL NOT NULL DEFAULT 1,
                            `updated_at` DATETIME NOT NULL
                        )
                        """
                    )
                )
            else:
                conn.execute(
                    text(
                        """
                        CREATE TABLE `organization_settings` (
                            `organization_id` INTEGER NOT NULL,
                            `shift_start` VARCHAR(10) NOT NULL DEFAULT '10:00:00',
                            `shift_end` VARCHAR(10) NOT NULL DEFAULT '19:00:00',
                            `late_cutoff` VARCHAR(10) NOT NULL DEFAULT '10:30:00',
                            `noon_cutoff` VARCHAR(10) NOT NULL DEFAULT '12:00:00',
                            `checkin_block` VARCHAR(10) NOT NULL DEFAULT '20:00:00',
                            `full_day_hours` FLOAT NOT NULL DEFAULT 7.0,
                            `half_day_hours` FLOAT NOT NULL DEFAULT 5.0,
                            `leave_quota_days` INTEGER NOT NULL DEFAULT 15,
                            `advance_leave_days` INTEGER NOT NULL DEFAULT 1,
                            `require_attendance_selfie` BOOL NOT NULL DEFAULT 1,
                            `require_attendance_gps` BOOL NOT NULL DEFAULT 1,
                            `auto_checkout_enabled` BOOL NOT NULL DEFAULT 1,
                            `updated_at` DATETIME NOT NULL,
                            PRIMARY KEY (`organization_id`),
                            CONSTRAINT `fk_org_settings_organization_id`
                                FOREIGN KEY (`organization_id`) REFERENCES `organizations` (`id`)
                                ON DELETE CASCADE
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """
                    )
                )

    # 3. Create organization_memberships table if missing
    if not inspector.has_table("organization_memberships"):
        with engine.begin() as conn:
            if is_sqlite:
                conn.execute(
                    text(
                        """
                        CREATE TABLE `organization_memberships` (
                            `id` INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                            `organization_id` INTEGER NOT NULL,
                            `user_id` INTEGER NOT NULL,
                            `role` VARCHAR(40) NOT NULL DEFAULT 'intern',
                            `department` VARCHAR(120) NULL,
                            `job_title` VARCHAR(120) NULL,
                            `joining_date` DATE NULL,
                            `mentor_membership_id` INTEGER NULL,
                            `is_active` BOOL NOT NULL DEFAULT 1,
                            `activated_at` DATETIME NULL,
                            `created_at` DATETIME NOT NULL,
                            `is_deleted` BOOL NOT NULL DEFAULT 0,
                            `deleted_at` DATETIME NULL,
                            UNIQUE (`organization_id`, `user_id`)
                        )
                        """
                    )
                )
            else:
                conn.execute(
                    text(
                        """
                        CREATE TABLE `organization_memberships` (
                            `id` INTEGER NOT NULL AUTO_INCREMENT,
                            `organization_id` INTEGER NOT NULL,
                            `user_id` INTEGER NOT NULL,
                            `role` VARCHAR(40) NOT NULL DEFAULT 'intern',
                            `department` VARCHAR(120) NULL,
                            `job_title` VARCHAR(120) NULL,
                            `joining_date` DATE NULL,
                            `mentor_membership_id` INTEGER NULL,
                            `is_active` BOOL NOT NULL DEFAULT 1,
                            `activated_at` DATETIME NULL,
                            `created_at` DATETIME NOT NULL,
                            `is_deleted` BOOL NOT NULL DEFAULT 0,
                            `deleted_at` DATETIME NULL,
                            PRIMARY KEY (`id`),
                            UNIQUE KEY `uq_org_user` (`organization_id`, `user_id`),
                            INDEX `ix_org_memberships_org_id` (`organization_id`),
                            INDEX `ix_org_memberships_user_id` (`user_id`),
                            CONSTRAINT `fk_org_memberships_org_id`
                                FOREIGN KEY (`organization_id`) REFERENCES `organizations` (`id`)
                                ON DELETE CASCADE,
                            CONSTRAINT `fk_org_memberships_user_id`
                                FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
                                ON DELETE CASCADE
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                        """
                    )
                )

    # 4. Add is_platform_admin to users if missing
    if inspector.has_table("users"):
        user_cols = {c["name"] for c in inspector.get_columns("users")}
        if "is_platform_admin" not in user_cols:
            with engine.begin() as conn:
                _add_column_if_missing(conn, "users", "is_platform_admin", "BOOL NOT NULL DEFAULT 0")

    # 5. Add organization_id to all tenant tables if missing
    for table_name in TENANT_TABLES:
        if not inspector.has_table(table_name):
            continue
        cols = {c["name"] for c in inspector.get_columns(table_name)}
        if "organization_id" not in cols:
            with engine.begin() as conn:
                _add_column_if_missing(conn, table_name, "organization_id", "INTEGER NULL DEFAULT 1")
                try:
                    conn.execute(text(f"CREATE INDEX `ix_{table_name}_organization_id` ON `{table_name}` (`organization_id`)"))
                except Exception:
                    pass

    # 6. Ensure default organization (id=1, slug='default') exists
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    with engine.begin() as conn:
        res = conn.execute(text("SELECT id FROM organizations WHERE id = 1")).fetchone()
        if not res:
            conn.execute(
                text(
                    """
                    INSERT INTO organizations (id, slug, name, type, status, timezone, created_at, is_deleted)
                    VALUES (1, 'default', 'Default Organization', 'business', 'active', 'Asia/Kolkata', :now, 0)
                    """
                ),
                {"now": now_utc},
            )
            conn.execute(
                text(
                    """
                    INSERT INTO organization_settings (
                        organization_id, shift_start, shift_end, late_cutoff, noon_cutoff,
                        checkin_block, full_day_hours, half_day_hours, leave_quota_days,
                        advance_leave_days, require_attendance_selfie, require_attendance_gps,
                        auto_checkout_enabled, updated_at
                    )
                    VALUES (1, '10:00:00', '19:00:00', '10:30:00', '12:00:00', '20:00:00', 7.0, 5.0, 15, 1, 1, 1, 1, :now)
                    """
                ),
                {"now": now_utc},
            )

        # Backfill organization_id = 1 on any orphaned tenant rows
        for table_name in TENANT_TABLES:
            if inspector.has_table(table_name):
                conn.execute(text(f"UPDATE `{table_name}` SET organization_id = 1 WHERE organization_id IS NULL"))

        # Backfill organization_memberships for existing users
        if inspector.has_table("users") and inspector.has_table("organization_memberships"):
            insert_kw = "INSERT OR IGNORE" if engine.dialect.name == "sqlite" else "INSERT IGNORE"
            conn.execute(
                text(
                    f"""
                    {insert_kw} INTO organization_memberships (
                        organization_id, user_id, role, department, job_title, joining_date,
                        is_active, activated_at, created_at, is_deleted
                    )
                    SELECT 1, id, role, department, job_title, joining_date,
                           is_active, activated_at, created_at, is_deleted
                    FROM users
                    """
                )
            )
