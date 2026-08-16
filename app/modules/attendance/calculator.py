"""Pure calculation functions for attendance status, working hours, and streaks."""
from datetime import date, datetime, time, timedelta
from app.core.constants import AttendanceStatus


def parse_time_string(t_str: str | time | None, default_time: time) -> time:
    if isinstance(t_str, time):
        return t_str
    if isinstance(t_str, str) and t_str.strip():
        try:
            return time.fromisoformat(t_str.strip())
        except ValueError:
            pass
    return default_time


def calculate_attendance_status(
    check_in_time: datetime | None,
    check_out_time: datetime | None = None,
    settings: any = None,
) -> tuple[str, float]:
    """Calculate the attendance status (present/late/half_day/absent) and hours worked."""
    if not check_in_time:
        return AttendanceStatus.ABSENT, 0.0

    shift_start = parse_time_string(getattr(settings, "shift_start", None), time(9, 0))
    late_cutoff = parse_time_string(getattr(settings, "late_cutoff", None), time(10, 0))
    noon_cutoff = parse_time_string(getattr(settings, "noon_cutoff", None), time(12, 0))
    checkin_block = parse_time_string(getattr(settings, "checkin_block", None), time(15, 0))

    full_day_hours = float(getattr(settings, "full_day_hours", 8.0) or 8.0)
    half_day_hours = float(getattr(settings, "half_day_hours", 4.0) or 4.0)

    cin_t = check_in_time.time()
    hours_worked = 0.0

    if check_out_time and check_out_time > check_in_time:
        diff_secs = (check_out_time - check_in_time).total_seconds()
        hours_worked = round(diff_secs / 3600.0, 2)

    if hours_worked > 0:
        if hours_worked < half_day_hours:
            status = AttendanceStatus.HALF_DAY
        elif cin_t > late_cutoff:
            status = AttendanceStatus.LATE
        else:
            status = AttendanceStatus.PRESENT
        return status, hours_worked

    # Based on check-in time alone
    if cin_t <= late_cutoff:
        status = AttendanceStatus.PRESENT
    elif cin_t <= noon_cutoff:
        status = AttendanceStatus.LATE
    elif cin_t <= checkin_block:
        status = AttendanceStatus.HALF_DAY
    else:
        status = AttendanceStatus.ABSENT

    return status, hours_worked
