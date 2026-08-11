"""
One-time script: Add attendance for Prakash Jagannath Kale (id=5)
from 04 May 2026 to 28 July 2026 (Mon–Sat, skip Sunday).
Check-in : random 9:50 AM – 10:20 AM
Check-out: random 6:45 PM – 7:15 PM
Leave period 29 Jun – 03 Jul 2026 → marked as ABSENT (no check-in/out).
Skips dates that already have a record.
Does NOT touch any other user's data.
"""
import random
import os
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

host = os.getenv("MYSQL_HOST", "localhost")
port = os.getenv("MYSQL_PORT", "3306")
db_name = os.getenv("MYSQL_DATABASE", "internhub")

# Use root so we have full write access
ROOT_URL = f"mysql+pymysql://root:Mayur2157@{host}:{port}/{db_name}?charset=utf8mb4"
engine = create_engine(ROOT_URL)
db = sessionmaker(bind=engine)()

TARGET_USER_ID = 5
START_DATE  = date(2026, 5, 4)
END_DATE    = date(2026, 7, 28)
LEAVE_START = date(2026, 6, 29)
LEAVE_END   = date(2026, 7, 3)

try:
    from models import Attendance, AttendanceStatus, User
    from utils import determine_status

    # Safety check
    user = db.get(User, TARGET_USER_ID)
    assert user is not None and "prakash" in user.name.lower(), \
        f"Safety check failed: got '{user.name if user else None}'"
    print(f"[OK] Target user confirmed: {user.name} (id={user.id})")
    print(f"[INFO] Range : {START_DATE} → {END_DATE}  (Mon–Sat, no Sunday)")
    print(f"[INFO] Leave : {LEAVE_START} → {LEAVE_END}  → ABSENT\n")

    # Collect all Mon–Sat days in range
    all_days = []
    d = START_DATE
    while d <= END_DATE:
        if d.weekday() != 6:   # skip Sunday (6)
            all_days.append(d)
        d += timedelta(days=1)

    added_present = 0
    added_absent  = 0
    skipped       = 0

    for day in all_days:
        existing = db.query(Attendance).filter_by(user_id=TARGET_USER_ID, date=day).first()
        if existing:
            print(f"  [SKIP] {day} ({day.strftime('%a')}) — already exists (status={existing.status})")
            skipped += 1
            continue

        is_leave = LEAVE_START <= day <= LEAVE_END

        if is_leave:
            # Absent — no check-in / check-out
            att = Attendance(
                user_id=TARGET_USER_ID,
                date=day,
                check_in=datetime.combine(day, time(10, 0)),
                check_out=None,
                status=AttendanceStatus.ABSENT,
                hours_worked=0.0,
                notes="Leave",
            )
            db.add(att)
            print(f"  [ABSENT] {day} ({day.strftime('%a')}) — leave period")
            added_absent += 1
        else:
            # Normal working day — random times around 10 AM / 7 PM
            ci_offset = random.randint(-10, 20)
            if ci_offset < 0:
                check_in = datetime.combine(day, time(9, 60 + ci_offset, random.randint(0, 59)))
            else:
                check_in = datetime.combine(day, time(10, ci_offset, random.randint(0, 59)))

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
            print(f"  [ADD]    {day} ({day.strftime('%a')}) — in={check_in.strftime('%H:%M')}  out={check_out.strftime('%H:%M')}  hrs={hours_worked}  {status}")
            added_present += 1

    db.commit()
    print(f"\n[DONE] Present={added_present}  Absent(leave)={added_absent}  Skipped={skipped}")
    print("[INFO] No other user's data was touched.")

except Exception as e:
    db.rollback()
    print(f"[ERROR] Rolled back. Reason: {e}")
    raise
finally:
    db.close()
