"""Start-up membership migrations must never pull other tenants' users into the default org."""
import importlib
from datetime import datetime, timedelta

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from database import Base
from models import Organization, OrganizationMembership, OrganizationType, User, UserRole

multi_tenant = importlib.import_module("migrations.20260815_multi_tenant_saas")
invite_fix = importlib.import_module("migrations.20260927_invite_signup_memberships")
spurious_fix = importlib.import_module("migrations.20260927_remove_spurious_default_org_memberships")

OLD_BUGGY_BACKFILL = """
    INSERT OR IGNORE INTO organization_memberships (
        organization_id, user_id, role, department, job_title, joining_date,
        is_active, activated_at, created_at, is_deleted
    )
    SELECT 1, id, role, department, job_title, joining_date, is_active, activated_at, created_at, is_deleted
    FROM users
"""


@pytest.fixture()
def world(tmp_path):
    engine = create_engine(f"sqlite:///{tmp_path / 'm.db'}")
    Base.metadata.create_all(bind=engine)
    db = sessionmaker(bind=engine)()
    db.add_all([Organization(id=1, slug="default", name="Default", type=OrganizationType.BUSINESS),
                Organization(id=2, slug="beta", name="Beta", type=OrganizationType.BUSINESS)])
    db.flush()
    born = datetime(2026, 9, 1, 10, 0, 0)

    def user(email, role, created, mentor=None):
        u = User(name=email, email=email, role=role, is_active=True, created_at=created, mentor_id=mentor)
        u.set_password("Password123!")
        db.add(u)
        db.flush()
        return u

    legacy = user("legacy@x.test", UserRole.INTERN, born)                  # pre-multi-tenant, org 1 only
    db.add(OrganizationMembership(organization_id=1, user_id=legacy.id, role="intern", created_at=born))
    beta_admin = user("admin.beta@x.test", UserRole.ADMIN, born + timedelta(days=1))
    db.add(OrganizationMembership(organization_id=2, user_id=beta_admin.id, role="admin",
                                  created_at=born + timedelta(days=1, seconds=1)))
    beta_mentor = user("mentor.beta@x.test", UserRole.MENTOR, born + timedelta(days=2))
    db.add(OrganizationMembership(organization_id=2, user_id=beta_mentor.id, role="mentor",
                                  created_at=born + timedelta(days=2, seconds=1)))
    invitee = user("invitee.beta@x.test", UserRole.INTERN, born + timedelta(days=3), mentor=beta_mentor.id)
    db.commit()
    ids = {"legacy": legacy.id, "beta_admin": beta_admin.id, "beta_mentor": beta_mentor.id, "invitee": invitee.id}
    # Reproduce what every previous deploy did.
    with engine.begin() as conn:
        conn.execute(text(OLD_BUGGY_BACKFILL))
    yield engine, db, ids
    db.close()
    engine.dispose()


def live_orgs(db, user_id):
    db.expire_all()
    return sorted(m.organization_id for m in db.query(OrganizationMembership)
                  .filter_by(user_id=user_id, is_deleted=False, is_active=True))


def test_repair_removes_backfilled_default_memberships(world):
    engine, db, ids = world
    assert live_orgs(db, ids["beta_admin"]) == [1, 2]   # the bug: Beta's admin is also a default-org admin
    assert live_orgs(db, ids["invitee"]) == [1]

    invite_fix.upgrade(engine)
    spurious_fix.upgrade(engine)

    assert live_orgs(db, ids["legacy"]) == [1]
    assert live_orgs(db, ids["beta_admin"]) == [2]
    assert live_orgs(db, ids["beta_mentor"]) == [2]
    assert live_orgs(db, ids["invitee"]) == [2]


def test_fixed_startup_backfill_leaves_tenants_alone(world):
    engine, db, ids = world
    invite_fix.upgrade(engine)
    spurious_fix.upgrade(engine)
    multi_tenant.upgrade(engine)          # runs on every boot
    invite_fix.upgrade(engine)
    spurious_fix.upgrade(engine)          # idempotent

    assert live_orgs(db, ids["beta_admin"]) == [2]
    assert live_orgs(db, ids["invitee"]) == [2]
    assert live_orgs(db, ids["legacy"]) == [1]


self_registered_fix = importlib.import_module("migrations.20260927_self_registered_accounts")


def test_post_cutover_self_signups_are_flagged_and_detached(world):
    from models import AuditLog

    engine, db, ids = world
    org1 = db.get(Organization, 1)
    org1.created_at = datetime(2026, 8, 15, 0, 0, 0)
    public = User(name="Public", email="public@x.test", role=UserRole.INTERN, is_active=True,
                  created_at=datetime(2026, 9, 20, 9, 0, 0))
    public.set_password("Password123!")
    db.add(public)
    db.flush()
    db.add(AuditLog(actor_id=public.id, actor_name="Public", action="user.register", verb="registered account",
                    target="Public"))
    legacy_signup = db.get(User, ids["legacy"])
    db.add(AuditLog(actor_id=legacy_signup.id, actor_name="legacy", action="user.register",
                    verb="registered account", target="legacy"))
    legacy_signup.created_at = datetime(2026, 7, 1)          # signed up before multi-tenancy: genuine org-1 user
    for m in db.query(OrganizationMembership).filter_by(user_id=legacy_signup.id):
        m.created_at = legacy_signup.created_at
    db.commit()
    with engine.begin() as conn:
        conn.execute(text(OLD_BUGGY_BACKFILL))
    assert live_orgs(db, public.id) == [1]

    self_registered_fix.upgrade(engine)
    multi_tenant.upgrade(engine)           # the next boot must not re-add it
    self_registered_fix.upgrade(engine)

    db.expire_all()
    assert db.get(User, public.id).self_registered is True
    assert live_orgs(db, public.id) == []
    assert not db.get(User, ids["legacy"]).self_registered
    assert live_orgs(db, ids["legacy"]) == [1]


audit_attendance_fix = importlib.import_module("migrations.20260927_audit_attendance_org_backfill")


def test_audit_and_attendance_rows_move_to_their_tenant(world):
    from datetime import date as _date

    from models import Attendance, AuditLog

    engine, db, ids = world
    spurious_fix.upgrade(engine)
    db.add_all([
        AuditLog(organization_id=1, actor_id=ids["beta_admin"], actor_name="b", action="x", verb="v", target="t"),
        AuditLog(organization_id=1, actor_id=ids["legacy"], actor_name="l", action="x", verb="v", target="t"),
        Attendance(organization_id=1, user_id=ids["beta_mentor"], date=_date(2026, 9, 1),
                   check_in=datetime(2026, 9, 1, 9, 30)),
        Attendance(organization_id=1, user_id=ids["legacy"], date=_date(2026, 9, 1),
                   check_in=datetime(2026, 9, 1, 9, 30)),
    ])
    db.commit()
    audit_attendance_fix.upgrade(engine)
    audit_attendance_fix.upgrade(engine)
    db.expire_all()
    assert sorted((a.actor_id, a.organization_id) for a in db.query(AuditLog)) == sorted(
        [(ids["beta_admin"], 2), (ids["legacy"], 1)])
    assert sorted((a.user_id, a.organization_id) for a in db.query(Attendance)) == sorted(
        [(ids["beta_mentor"], 2), (ids["legacy"], 1)])
