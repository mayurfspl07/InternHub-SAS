"""Pure calculation functions for leave balance, business day counts, and overlapping periods."""
from datetime import date, timedelta


def count_business_days(start: date, end: date) -> int:
    """Calculate the number of Monday-Friday business days in an inclusive date range."""
    if start > end:
        return 0
    days = 0
    curr = start
    while curr <= end:
        if curr.weekday() < 5:  # Monday through Friday
            days += 1
        curr += timedelta(days=1)
    return max(1, days)


def calculate_leave_balance(
    total_quota_days: int,
    approved_leave_days: int,
    pending_leave_days: int = 0,
) -> dict:
    """Calculate leave usage and remaining balance."""
    remaining = max(0, total_quota_days - approved_leave_days)
    return {
        "quota": total_quota_days,
        "approved": approved_leave_days,
        "pending": pending_leave_days,
        "remaining": remaining,
    }
