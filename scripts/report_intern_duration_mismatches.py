"""Read-only report: interns the 20260929_intern_duration_backfill migration would change.

Lists every intern whose internship duration matches none of their organization's
active duration tiers (so their leave quota currently falls back to the
organization's leave setting), with the tier the migration would give them.

Nothing is written: the session is rolled back and never committed, and tiers are
read directly instead of through helpers that seed defaults.

Usage (uses the same DATABASE_URL / MYSQL_* settings as the app):
    python scripts/report_intern_duration_mismatches.py
    python scripts/report_intern_duration_mismatches.py --csv mismatches.csv
"""
import argparse
import csv
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy.orm import Session  # noqa: E402

from database import engine  # noqa: E402
from models import (  # noqa: E402
    InternshipDurationMaster,
    Organization,
    OrganizationMembership,
    User,
    UserRole,
)


def collect(db: Session) -> list[dict]:
    tiers_by_org: dict[int, list[InternshipDurationMaster]] = {}
    for tier in db.query(InternshipDurationMaster).filter_by(is_active=True).all():
        tiers_by_org.setdefault(tier.organization_id, []).append(tier)
    org_names = {o.id: o.name for o in db.query(Organization).all()}

    rows = (
        db.query(User, OrganizationMembership)
        .join(OrganizationMembership, OrganizationMembership.user_id == User.id)
        .filter(
            User.role == UserRole.INTERN,
            User.is_deleted == False,  # noqa: E712
            OrganizationMembership.is_deleted == False,  # noqa: E712
        )
        .order_by(OrganizationMembership.organization_id, User.name)
        .all()
    )

    report = []
    for user, membership in rows:
        org_id = membership.organization_id
        tiers = sorted(tiers_by_org.get(org_id, []), key=lambda t: (t.order_index, t.id))
        months = user.internship_duration_months
        if months and any(t.duration_months == months for t in tiers):
            continue
        # Same choice as the migration: default active tier, else the first active tier.
        # An org with no tiers yet gets the seeded defaults (3 Months / 5 leaves) on first use.
        target = next((t for t in tiers if t.is_default), tiers[0] if tiers else None)
        report.append({
            "organization": org_names.get(org_id, f"#{org_id}"),
            "intern": user.name,
            "email": user.email,
            "active": "yes" if user.is_active else "no",
            "current_months": months if months is not None else "",
            "current_leave_quota": "org leave setting",
            "new_tier": target.title if target else "3 Months (seeded default)",
            "new_months": target.duration_months if target else 3,
            "new_leaves": target.leaves if target else 5,
        })
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--csv", help="Also write the rows to this CSV file")
    args = parser.parse_args()

    db = Session(bind=engine)
    try:
        report = collect(db)
    finally:
        db.rollback()
        db.close()

    if not report:
        print("No interns to change: every intern is on one of their organization's active durations.")
        return

    cols = list(report[0].keys())
    widths = {c: max(len(c), *(len(str(r[c])) for r in report)) for c in cols}
    print("  ".join(c.ljust(widths[c]) for c in cols))
    print("  ".join("-" * widths[c] for c in cols))
    for r in report:
        print("  ".join(str(r[c]).ljust(widths[c]) for c in cols))
    print(f"\n{len(report)} intern(s) would be moved to their organization's default duration.")

    if args.csv:
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=cols)
            writer.writeheader()
            writer.writerows(report)
        print(f"Wrote {args.csv}")


if __name__ == "__main__":
    main()
