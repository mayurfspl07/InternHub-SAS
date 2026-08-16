"""Object storage service supporting AWS S3, Cloudflare R2, and local disk.

Provides presigned upload URLs for direct client selfie uploads at 500k scale.
"""
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

STORAGE_BACKEND = os.environ.get("STORAGE_BACKEND", "local")  # 'local', 's3', 'r2'
S3_BUCKET = os.environ.get("S3_BUCKET", "internhub-uploads")
S3_REGION = os.environ.get("S3_REGION", "us-east-1")
S3_ENDPOINT_URL = os.environ.get("S3_ENDPOINT_URL")  # e.g. for Cloudflare R2
S3_ACCESS_KEY_ID = os.environ.get("S3_ACCESS_KEY_ID")
S3_SECRET_ACCESS_KEY = os.environ.get("S3_SECRET_ACCESS_KEY")

LOCAL_STORAGE_DIR = Path(os.environ.get("ATTENDANCE_PHOTOS_DIR", "attendance_photos")).resolve()


class StorageService:
    @staticmethod
    def generate_presigned_upload_url(
        object_key: str,
        content_type: str = "image/jpeg",
        expires_in: int = 300,
    ) -> dict:
        """Generate a presigned PUT URL allowing clients to upload directly to S3/R2."""
        if STORAGE_BACKEND in ("s3", "r2") and S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY:
            try:
                import boto3
                from botocore.config import Config

                s3_client = boto3.client(
                    "s3",
                    endpoint_url=S3_ENDPOINT_URL,
                    region_name=S3_REGION,
                    aws_access_key_id=S3_ACCESS_KEY_ID,
                    aws_secret_access_key=S3_SECRET_ACCESS_KEY,
                    config=Config(signature_version="s3v4"),
                )
                url = s3_client.generate_presigned_url(
                    ClientMethod="put_object",
                    Params={
                        "Bucket": S3_BUCKET,
                        "Key": object_key,
                        "ContentType": content_type,
                    },
                    ExpiresIn=expires_in,
                )
                return {
                    "upload_url": url,
                    "object_key": object_key,
                    "method": "PUT",
                    "expires_in": expires_in,
                }
            except Exception as exc:
                print(f"[WARNING] S3 presigned URL generation failed: {exc}")

        # Local fallback simulation:
        return {
            "upload_url": f"/api/attendance/direct-upload?key={object_key}",
            "object_key": object_key,
            "method": "POST",
            "expires_in": expires_in,
        }

    @staticmethod
    def save_file_locally(file_data: bytes, relative_path: str) -> str:
        target = LOCAL_STORAGE_DIR / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        with open(target, "wb") as f:
            f.write(file_data)
        return relative_path

    @staticmethod
    def get_file_path(relative_path: str) -> Path | None:
        target = LOCAL_STORAGE_DIR / relative_path
        if target.exists() and target.is_file():
            return target
        return None
