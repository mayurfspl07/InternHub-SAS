import os
import shutil
import tempfile
import unittest
from datetime import date, datetime

from attendance_photos import photo_abs_path, save_attendance_photo
from config import Config
from models import Attendance, AttendanceStatus, User, UserRole
from routes.api.attendance import _att_dict
from routes.api.student_attendance import _att_dict as _student_att_dict


class TestAttendancePhotosPersistence(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.orig_photo_dir = Config.ATTENDANCE_PHOTOS_DIR
        Config.ATTENDANCE_PHOTOS_DIR = self.temp_dir

        self.dummy_user = User(
            id=42,
            name="John Doe",
            email="john@example.com",
            role=UserRole.INTERN,
        )

    def tearDown(self):
        Config.ATTENDANCE_PHOTOS_DIR = self.orig_photo_dir
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_save_and_resolve_historical_photo(self):
        day = date(2026, 8, 30)
        img_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01" + b"A" * 100

        rel_path = save_attendance_photo(
            user_id=42,
            user_name="John Doe",
            day=day,
            kind="checkin",
            content=img_bytes,
        )

        self.assertIn("2026-08-30", rel_path)
        self.assertIn("42_john_doe", rel_path)

        # Resolves cleanly today and on subsequent days
        resolved_path = photo_abs_path(rel_path)
        self.assertIsNotNone(resolved_path)
        self.assertTrue(os.path.isfile(resolved_path))

        # Resolves with leading slash or backslashes
        self.assertIsNotNone(photo_abs_path("/" + rel_path))
        self.assertIsNotNone(photo_abs_path(rel_path.replace("/", "\\")))

    def test_checkout_photo_url_preserved_even_when_checkout_missed(self):
        # When midnight auto-checkout runs, checkout_missed becomes True
        att = Attendance(
            id=101,
            user_id=42,
            date=date(2026, 8, 30),
            check_in=datetime(2026, 8, 30, 9, 30),
            check_out=None,
            checkout_missed=True,
            status=AttendanceStatus.PRESENT,
            check_in_photo="2026-08-30/42_john_doe/checkin/093000.jpg",
            check_out_photo="2026-08-30/42_john_doe/checkout/183000.jpg",
        )
        att.user = self.dummy_user

        # Check in _att_dict (admin/mentor attendance view)
        d1 = _att_dict(att)
        self.assertEqual(d1["check_in_photo_url"], "/api/attendance/101/photo/checkin")
        self.assertEqual(d1["check_out_photo_url"], "/api/attendance/101/photo/checkout")

        # Check in _student_att_dict (student attendance view)
        d2 = _student_att_dict(att)
        self.assertEqual(d2["check_in_photo_url"], "/api/attendance/101/photo/checkin")
        self.assertEqual(d2["check_out_photo_url"], "/api/attendance/101/photo/checkout")
