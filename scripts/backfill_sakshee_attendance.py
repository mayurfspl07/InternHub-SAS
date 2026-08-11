"""
One-time script: Add attendance for Sakshee Dhormale (id=6)
from July 9 to July 27, 2025 (weekdays only).
Check-in: random between 9:50 AM - 10:20 AM
Check-out: random between 6:45 PM - 7:15 PM
Skips dates that already have an attendance record.
Does NOT touch any other user's data.
"""
import random
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from database import SessionLocal
from models import Attendance, AttendanceStatus, User
from utils import determine_status

TARGET_USER_ID = 6
START_DATE = date(2025, 7, 9)
END_DATE   = date(2025, 7, 27)

db = SessionLocal()
try:
    # Safety: confirm the user
    user = db.get(User, TARGET_USER_ID)
    assert user is not None, "User not found!"
    assert "sakshee" in user.name.lower(), f"Safety check failed: got user '{user.name}' instead of Sakshee"
    print(f"[OK] Target user confirmed: {user.name} (id={user.id})")

    # Collect all weekdays in range
    all_days = []
    d = START_DATE
    while d <= END_DATE:
        if d.weekday() < 5:   # Mon–Fri only
            all_days.append(d)
        d += timedelta(days=1)

    added = 0
    skipped = 0
    for day in all_days:
        # Check if record already exists for this date
        existing = db.query(Attendance).filter_by(user_id=TARGET_USER_ID, date=day).first()
        if existing:
            print(f"  [SKIP] {day} — record already exists (status={existing.status})")
            skipped += 1
            continue

        # Random check-in: 9:50 AM to 10:20 AM
        ci_hour = 10
        ci_minute = random.randint(-10, 20)   # -10 = 9:50, +20 = 10:20
        if ci_minute < 0:
            ci_hour = 9
            ci_minute = 60 + ci_minute
        check_in = datetime.combine(day, time(ci_hour, ci_minute, random.randint(0, 59)))

        # Random check-out: 6:45 PM to 7:15 PM
        co_hour = 19
        co_minute = random.randint(-15, 15)   # -15 = 6:45, +15 = 7:15
        if co_minute < 0:
            co_hour = 18
            co_minute = 60 + co_minute
        check_out = datetime.combine(day, time(co_hour, co_minute, random.randint(0, 59)))

        hours_worked = round((check_out - check_in).total_seconds() / 3600.0, 2)
        status = determine_status(check_in.time(), Decimal(str(hours_worked)), False)

        att = Attendance(
            user_id=TARGET_USER_ID,
            date=day,
            check_in=check_in,
            check_out=check_out,
            status=status,
            hours_worked=hours_worked,
        )
        db.add(att)
        print(f"  [ADD]  {day} ({day.strftime('%A')}) — in={check_in.strftime('%H:%M')}  out={check_out.strftime('%H:%M')}  hours={hours_worked}  status={status}")
        added += 1

    db.commit()
    print(f"\n[DONE] Added {added} records, skipped {skipped} existing records.")
    print("[INFO] No other user's data was touched.")

except Exception as e:
    db.rollback()
    print(f"[ERROR] Rolled back. Reason: {e}")
    raise
finally:
    db.close()
