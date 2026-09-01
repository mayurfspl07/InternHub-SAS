"""Test suite for Cloudinary image integration and fallback mechanisms."""
import io
import unittest
from datetime import date
from unittest.mock import MagicMock, patch

from fastapi import HTTPException
from fastapi.datastructures import Headers
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from starlette.requests import Request

from config import Config
from database import Base, get_db
from dependencies import generate_token
from main import app
from models import Organization, OrganizationMembership, User, UserRole
from cloudinary_service import is_cloudinary_configured, upload_image, delete_image
from attendance_photos import save_attendance_photo
from routes.api.uploads import _validate_image_file, MAX_IMAGE_SIZE


def _make_dummy_request(user: User, method: str = "GET", payload: dict | None = None, org_id: int | None = None) -> Request:
    headers_dict = {
        "host": "testserver",
        "authorization": f"Bearer {generate_token(user.id)}",
    }
    if org_id:
        headers_dict["x-organization-id"] = str(org_id)

    scope = {
        "type": "http",
        "method": method,
        "path": "/api/upload",
        "headers": Headers(headers_dict).raw,
        "query_string": b"",
        "app": app,
    }
    req = Request(scope)
    req.state.current_user = user
    return req


class TestCloudinaryIntegration(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine(
            "sqlite:///:memory:",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(bind=self.engine)
        self.Session = sessionmaker(autocommit=False, autoflush=False, bind=self.engine)
        self.db = self.Session()

        self.org = Organization(name="TechCorp", slug="techcorp")
        self.db.add(self.org)
        self.db.commit()
        self.db.refresh(self.org)

        self.admin = User(
            name="Admin User",
            email="admin@techcorp.com",
            role=UserRole.ADMIN,
            password_hash="test-hash",
            is_active=True,
        )
        self.db.add(self.admin)
        self.db.commit()
        self.db.refresh(self.admin)
        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.admin.id, role=UserRole.ADMIN, is_active=True))

        self.intern = User(
            name="Intern Bob",
            email="bob@techcorp.com",
            role=UserRole.INTERN,
            password_hash="test-hash",
            is_active=True,
        )
        self.db.add(self.intern)
        self.db.commit()
        self.db.refresh(self.intern)
        self.db.add(OrganizationMembership(organization_id=self.org.id, user_id=self.intern.id, role=UserRole.INTERN, is_active=True))
        self.db.commit()

        app.dependency_overrides[get_db] = lambda: self.db
        self.client = TestClient(app)

    def tearDown(self):
        self.db.close()
        app.dependency_overrides.clear()

    def test_cloudinary_config_detection(self):
        with patch.object(Config, "CLOUDINARY_URL", "cloudinary://123:abc@testcloud"):
            self.assertTrue(is_cloudinary_configured())

        with patch.object(Config, "CLOUDINARY_URL", ""), \
             patch.object(Config, "CLOUDINARY_CLOUD_NAME", "mycloud"), \
             patch.object(Config, "CLOUDINARY_API_KEY", "12345"), \
             patch.object(Config, "CLOUDINARY_API_SECRET", "secret"):
            self.assertTrue(is_cloudinary_configured())

        with patch.object(Config, "CLOUDINARY_URL", ""), \
             patch.object(Config, "CLOUDINARY_CLOUD_NAME", ""):
            self.assertFalse(is_cloudinary_configured())

    @patch("cloudinary.uploader.upload")
    def test_upload_image_to_cloudinary(self, mock_upload):
        mock_upload.return_value = {
            "secure_url": "https://res.cloudinary.com/testcloud/image/upload/v12345/internhub/sample.jpg",
            "public_id": "internhub/sample",
            "format": "jpg",
            "width": 800,
            "height": 600,
            "bytes": 54321,
            "resource_type": "image",
        }

        with patch.object(Config, "CLOUDINARY_URL", "cloudinary://123:abc@testcloud"):
            res = upload_image(
                content=b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00",
                folder="internhub/attendance",
                public_id="sample",
            )
            self.assertEqual(res["secure_url"], "https://res.cloudinary.com/testcloud/image/upload/v12345/internhub/sample.jpg")
            self.assertEqual(res["public_id"], "internhub/sample")
            self.assertEqual(res["width"], 800)

    @patch("cloudinary.uploader.upload")
    def test_save_attendance_photo_uses_cloudinary_when_configured(self, mock_upload):
        mock_upload.return_value = {
            "secure_url": "https://res.cloudinary.com/demo/image/upload/v1/internhub/attendance/2026-09-01/101_bob/checkin_090000.jpg",
            "public_id": "checkin_090000",
        }

        fake_photo_bytes = b"\xff\xd8\xff\xe0" + b"A" * 100
        with patch.object(Config, "CLOUDINARY_URL", "cloudinary://123:abc@demo"):
            url = save_attendance_photo(
                user_id=self.intern.id,
                user_name=self.intern.name,
                day=date(2026, 9, 1),
                kind="checkin",
                content=fake_photo_bytes,
            )
            self.assertTrue(url.startswith("https://res.cloudinary.com/"))
            self.assertIn("attendance/2026-09-01", url)

    @patch("cloudinary.uploader.upload")
    def test_save_attendance_photo_base64_support(self, mock_upload):
        mock_upload.return_value = {
            "secure_url": "https://res.cloudinary.com/demo/image/upload/v1/internhub/attendance/2026-09-01/101_bob/checkin_090000.jpg",
            "public_id": "checkin_090000",
        }

        import base64
        b64_str = "data:image/jpeg;base64," + base64.b64encode(b"\xff\xd8\xff\xe0" + b"B" * 50).decode()
        with patch.object(Config, "CLOUDINARY_URL", "cloudinary://123:abc@demo"):
            url = save_attendance_photo(
                user_id=self.intern.id,
                user_name=self.intern.name,
                day=date(2026, 9, 1),
                kind="checkin",
                content=b64_str,
            )
            self.assertTrue(url.startswith("https://res.cloudinary.com/"))

    def test_save_attendance_photo_local_fallback_when_unconfigured(self):
        fake_photo_bytes = b"\xff\xd8\xff\xe0" + b"A" * 100
        with patch.object(Config, "CLOUDINARY_URL", ""), \
             patch.object(Config, "CLOUDINARY_CLOUD_NAME", ""):
            rel_path = save_attendance_photo(
                user_id=self.intern.id,
                user_name=self.intern.name,
                day=date(2026, 9, 1),
                kind="checkout",
                content=fake_photo_bytes,
            )
            self.assertTrue(rel_path.startswith("2026-09-01/"))
            self.assertIn("checkout", rel_path)

    def test_upload_status_endpoint(self):
        headers = {"Authorization": f"Bearer {generate_token(self.admin.id, self.admin.session_version)}"}
        resp = self.client.get("/api/upload/status", headers=headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn("provider", data)
        self.assertIn("max_size_mb", data)
        self.assertIn("allowed_formats", data)

    @patch("cloudinary.uploader.upload")
    def test_generic_image_upload_endpoint(self, mock_upload):
        mock_upload.return_value = {
            "secure_url": "https://res.cloudinary.com/demo/image/upload/v1/internhub/general/test.png",
            "public_id": "internhub/general/test",
            "format": "png",
            "width": 400,
            "height": 400,
            "bytes": 1024,
        }

        headers = {"Authorization": f"Bearer {generate_token(self.admin.id, self.admin.session_version)}"}
        fake_file = io.BytesIO(b"\x89PNG\r\n\x1a\n" + b"B" * 50)
        with patch.object(Config, "CLOUDINARY_URL", "cloudinary://123:abc@demo"):
            resp = self.client.post(
                "/api/upload/image",
                files={"file": ("test.png", fake_file, "image/png")},
                data={"folder": "blogs"},
                headers=headers,
            )
            self.assertEqual(resp.status_code, 200)
            data = resp.json()
            self.assertTrue(data["success"])
            self.assertEqual(data["provider"], "cloudinary")
            self.assertTrue(data["secure_url"].startswith("https://res.cloudinary.com/"))

    @patch("cloudinary.uploader.upload")
    def test_avatar_and_org_logo_upload(self, mock_upload):
        mock_upload.return_value = {
            "secure_url": "https://res.cloudinary.com/demo/image/upload/v1/internhub/avatars/user_avatar.jpg",
            "public_id": "internhub/avatars/user_avatar",
        }

        headers = {"Authorization": f"Bearer {generate_token(self.admin.id, self.admin.session_version)}"}
        fake_file = io.BytesIO(b"\xff\xd8\xff\xe0" + b"C" * 50)
        with patch.object(Config, "CLOUDINARY_URL", "cloudinary://123:abc@demo"):
            resp = self.client.post(
                "/api/upload/avatar",
                files={"file": ("my_avatar.jpg", fake_file, "image/jpeg")},
                headers=headers,
            )
            self.assertEqual(resp.status_code, 200)
            self.assertTrue(resp.json()["success"])
            self.assertTrue(resp.json()["avatar_url"].startswith("https://res.cloudinary.com/"))
