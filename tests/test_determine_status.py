import unittest
from datetime import time
from decimal import Decimal

from utils import determine_status


class DetermineStatusTests(unittest.TestCase):
    """determine_status() is the single source of truth for attendance status —
    see utils.py's own docstring for the priority order this locks in."""

    def test_missed_checkout_is_absent_regardless_of_hours(self):
        self.assertEqual(determine_status(time(9, 0), Decimal("8"), True), "absent")

    def test_under_half_day_hours_is_absent(self):
        self.assertEqual(determine_status(time(9, 0), Decimal("4.9"), False), "absent")

    def test_late_checkin_overrides_full_day_hours(self):
        # Checked in at noon but stayed 8 hours — still "late", not "present".
        self.assertEqual(determine_status(time(12, 0), Decimal("8"), False), "late")

    def test_checkin_after_noon_is_late(self):
        self.assertEqual(determine_status(time(14, 30), Decimal("7.5"), False), "late")

    def test_full_day_hours_before_noon_is_present(self):
        self.assertEqual(determine_status(time(10, 0), Decimal("7"), False), "present")

    def test_between_half_and_full_day_before_noon_is_half_day(self):
        self.assertEqual(determine_status(time(10, 0), Decimal("6"), False), "half_day")

    def test_boundary_exactly_half_day_hours_counts(self):
        self.assertEqual(determine_status(time(10, 0), Decimal("5"), False), "half_day")

    def test_boundary_exactly_full_day_hours_counts_as_present(self):
        self.assertEqual(determine_status(time(10, 0), Decimal("7"), False), "present")

    def test_boundary_checkin_exactly_at_noon_is_late(self):
        self.assertEqual(determine_status(time(12, 0), Decimal("7"), False), "late")

    def test_checkin_one_minute_before_noon_with_full_hours_is_present(self):
        self.assertEqual(determine_status(time(11, 59), Decimal("7"), False), "present")

    def test_accepts_float_hours_worked_not_just_decimal(self):
        self.assertEqual(determine_status(time(10, 0), 7.0, False), "present")


if __name__ == "__main__":
    unittest.main()
