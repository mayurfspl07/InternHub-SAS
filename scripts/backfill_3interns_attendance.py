"""
One-time script: Add attendance for 3 interns only:
  - Atharva Amit Karale  (id=3)
  - Tanmay Vijay Ekatpure (id=8)
  - Aishwarya Biradar    (id=4)

Range  : 26 Jun 2026 – 28 Jul 2026
Days   : Mon–Sat (Sunday skipped)
Check-in : random 9:50 AM – 10:20 AM
Check-out: random 6:45 PM – 7:15 PM
No absent dates specified — all days are present.
Skips dates that already have a record.
Does NOT touch any other user's data.
"""
import random
import os
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

host    = os.getenv("MYSQL_HOST",     "localhost")
port    = os.getenv("MYSQL_PORT",     "3306")
db_name = os.getenv("MYSQL_DATABASE", "internhub")

ROOT_URL = f"mysql+pymysql://root:Mayur2157@{host}:{port}/{db_name}?charset=utf8mb4"
engine = create_engine(ROOT_URL)
db = sessionmaker(bind=engine)()

TARGETS = [
    (3, "atharva",    "Atharva Amit Karale"),
    (8, "tanmay",     "Tanmay Vijay Ekatpure"),
    (4, "aishwarya",  "Aishwarya Biradar"),
]
START_DATE = date(2026, 6, 26)
END_DATE   = date(2026, 7, 28)

# Collect all Mon–Sat days in range
all_days = []
d = START_DATE
while d <= END_DATE:
    if d.weekday() != 6:   # skip Sunday
        all_days.append(d)
    d += timedelta(days=1)

try:
    from models import Attendance, AttendanceStatus, User
    from utils import determine_status

    for (uid, keyword, expected_name) in TARGETS:
        user = db.get(User, uid)
        assert user is not None and keyword in user.name.lower(), \
            f"Safety check failed for id={uid}: got '{user.name if user else None}'"
        print(f"\n{'='*60}")
        print(f"[OK] {user.name} (id={user.id})")
        print(f"{'='*60}")

        added = 0
        skipped = 0

        for day in all_days:
            existing = db.query(Attendance).filter_by(user_id=uid, date=day).first()
            if existing:
                print(f"  [SKIP]  {day} ({day.strftime('%a')}) — already exists ({existing.status})")
                skipped += 1
                continue

            # Random check-in: 9:50 AM – 10:20 AM
            ci_offset = random.randint(-10, 20)
            if ci_offset < 0:
                check_in = datetime.combine(day, time(9, 60 + ci_offset, random.randint(0, 59)))
            else:
                check_in = datetime.combine(day, time(10, ci_offset, random.randint(0, 59)))

            # Random check-out: 6:45 PM – 7:15 PM
            co_offset = random.randint(-15, 15)
            if co_offset < 0:
                check_out = datetime.combine(day, time(18, 60 + co_offset, random.randint(0, 59)))
            else:
                check_out = datetime.combine(day, time(19, co_offset, random.randint(0, 59)))

            hours_worked = round((check_out - check_in).total_seconds() / 3600.0, 2)
            status = determine_status(check_in.time(), Decimal(str(hours_worked)), False)

            db.add(Attendance(
                user_id=uid,
                date=day,
                check_in=check_in,
                check_out=check_out,
                status=status,
                hours_worked=hours_worked,
            ))
            print(f"  [ADD]   {day} ({day.strftime('%a')}) — in={check_in.strftime('%H:%M')}  out={check_out.strftime('%H:%M')}  hrs={hours_worked}  {status}")
            added += 1

        print(f"  → Added={added}  Skipped={skipped}")

    db.commit()
    print(f"\n[DONE] All 3 interns processed successfully.")
    print("[INFO] No other user's data was touched.")

except Exception as e:
    db.rollback()
    print(f"\n[ERROR] Rolled back everything. Reason: {e}")
    raise
finally:
    db.close()
