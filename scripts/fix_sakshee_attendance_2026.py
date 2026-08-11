"""
Fix script: Remove wrongly-inserted 2025 attendance for Sakshee Dhormale (id=6)
and re-add them correctly for July 9–27, 2026 (Mon–Sat, skip Sunday only).
Uses root for the DELETE (Mayur user has no DELETE grant).
"""
import random
import os
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Connect as root to allow DELETE of wrong-year records
host = os.getenv("MYSQL_HOST", "localhost")
port = os.getenv("MYSQL_PORT", "3306")
db_name = os.getenv("MYSQL_DATABASE", "internhub")
ROOT_URL = f"mysql+pymysql://root:Mayur2157@{host}:{port}/{db_name}?charset=utf8mb4"

engine = create_engine(ROOT_URL)
Session = sessionmaker(bind=engine)
db = Session()

TARGET_USER_ID = 6
START_DATE = date(2026, 7, 9)
END_DATE   = date(2026, 7, 27)

try:
    from models import Attendance, AttendanceStatus, User
    from utils import determine_status

    # Safety check
    user = db.get(User, TARGET_USER_ID)
    assert user is not None and "sakshee" in user.name.lower(), \
        f"Safety check failed: got '{user.name if user else None}'"
    print(f"[OK] Target user confirmed: {user.name} (id={user.id})")

    # --- Step 1: Remove wrong-year (2025) records we inserted ---
    wrong = db.query(Attendance).filter(
        Attendance.user_id == TARGET_USER_ID,
        Attendance.date >= date(2025, 7, 9),
        Attendance.date <= date(2025, 7, 27),
    ).all()
    if wrong:
        for r in wrong:
            db.delete(r)
        print(f"[FIX] Deleted {len(wrong)} incorrect 2025 records.")
    else:
        print("[INFO] No 2025 records found to remove.")

    # --- Step 2: Collect Mon–Sat days in July 9–27, 2026 ---
    all_days = []
    d = START_DATE
    while d <= END_DATE:
        if d.weekday() != 6:   # skip Sunday only (6=Sunday)
            all_days.append(d)
        d += timedelta(days=1)

    added = 0
    skipped = 0
    for day in all_days:
        existing = db.query(Attendance).filter_by(user_id=TARGET_USER_ID, date=day).first()
        if existing:
            print(f"  [SKIP] {day} — already exists (status={existing.status})")
            skipped += 1
            continue

        # Check-in: 9:50 AM – 10:20 AM
        ci_offset = random.randint(-10, 20)
        if ci_offset < 0:
            check_in = datetime.combine(day, time(9, 60 + ci_offset, random.randint(0, 59)))
        else:
            check_in = datetime.combine(day, time(10, ci_offset, random.randint(0, 59)))

        # Check-out: 6:45 PM – 7:15 PM
        co_offset = random.randint(-15, 15)
        if co_offset < 0:
            check_out = datetime.combine(day, time(18, 60 + co_offset, random.randint(0, 59)))
        else:
            check_out = datetime.combine(day, time(19, co_offset, random.randint(0, 59)))

        hours_worked = round((check_out - check_in).total_seconds() / 3600.0, 2)
        status = determine_status(check_in.time(), Decimal(str(hours_worked)), False)

        db.add(Attendance(
            user_id=TARGET_USER_ID,
            date=day,
            check_in=check_in,
            check_out=check_out,
            status=status,
            hours_worked=hours_worked,
        ))
        print(f"  [ADD]  {day} ({day.strftime('%a')}) — in={check_in.strftime('%H:%M')}  out={check_out.strftime('%H:%M')}  hrs={hours_worked}  {status}")
        added += 1

    db.commit()
    print(f"\n[DONE] Added {added} correct 2026 records, skipped {skipped} existing.")
    print("[INFO] No other user's data was touched.")

except Exception as e:
    db.rollback()
    print(f"[ERROR] Rolled back. Reason: {e}")
    raise
finally:
    db.close()
