"""Domain service orchestrating attendance check-in, check-out, and corrections."""
from datetime import date, datetime, timezone
from sqlalchemy.orm import Session

from app.modules.attendance.calculator import calculate_attendance_status, calculate_hours_worked
from app.modules.attendance.repository import AttendanceRepository
from app.modules.attendance.schemas import CheckInRequest, CheckOutRequest
from geocoding import reverse_geocode
from models import Attendance, AttendanceAuditLog, OrganizationSettings, User


class AttendanceService:
    def __init__(self, db: Session, org_id: int, settings: OrganizationSettings):
        self.db = db
        self.org_id = org_id
        self.settings = settings
        self.repo = AttendanceRepository(db, org_id)

    async def check_in(self, user: User, request: CheckInRequest) -> Attendance:
        today = datetime.now(timezone.utc).date()
        existing = self.repo.get_for_user_date(user.id, today)
        if existing and existing.check_in:
            return existing

        now = datetime.now(timezone.utc).replace(tzinfo=None)
        status = calculate_attendance_status(now.time(), self.settings)

        address = None
        if request.latitude is not None and request.longitude is not None:
            address = await reverse_geocode(request.latitude, request.longitude)

        if not existing:
            attendance = Attendance(
                user_id=user.id,
                organization_id=self.org_id,
                date=today,
                check_in=now,
                status=status,
                check_in_lat=request.latitude,
                check_in_lng=request.longitude,
                check_in_address=address,
                check_in_photo=request.selfie_url or request.selfie_key,
            )
            return self.repo.create(attendance)
        else:
            existing.check_in = now
            existing.status = status
            existing.check_in_lat = request.latitude
            existing.check_in_lng = request.longitude
            existing.check_in_address = address
            existing.check_in_photo = request.selfie_url or request.selfie_key
            return self.repo.update(existing)

    async def check_out(self, user: User, request: CheckOutRequest) -> Attendance:
        today = datetime.now(timezone.utc).date()
        attendance = self.repo.get_for_user_date(user.id, today)
        if not attendance or not attendance.check_in:
            raise ValueError("Must check in before checking out.")

        now = datetime.now(timezone.utc).replace(tzinfo=None)
        attendance.check_out = now
        attendance.hours_worked = calculate_hours_worked(attendance.check_in, now)
        attendance.checkout_missed = False

        if request.latitude is not None and request.longitude is not None:
            attendance.check_out_lat = request.latitude
            attendance.check_out_lng = request.longitude
            attendance.check_out_address = await reverse_geocode(request.latitude, request.longitude)

        return self.repo.update(attendance)
