"""Best-effort reverse geocoding for attendance check-in/check-out coordinates.

Uses OpenStreetMap's Nominatim (no API key required). Nominatim's usage policy caps
public requests at ~1/sec and requires a descriptive User-Agent — fine for this app's
volume (a couple of lookups per intern per day). Callers must treat the result as
optional: any network failure, timeout, or unrecognized location returns None, and the
UI falls back to showing raw coordinates.
"""
import json
import urllib.parse
import urllib.request

NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse"
USER_AGENT = "InternHub-Attendance/1.0 (self-hosted intern management app)"
TIMEOUT_SECONDS = 5


def reverse_geocode(lat: float, lng: float) -> str | None:
    """Blocking network call — run via asyncio.to_thread from async route handlers."""
    try:
        params = urllib.parse.urlencode({
            "format": "jsonv2",
            "lat": lat,
            "lon": lng,
            "zoom": 18,
            "addressdetails": 0,
        })
        request = urllib.request.Request(
            f"{NOMINATIM_URL}?{params}",
            headers={"User-Agent": USER_AGENT},
        )
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            data = json.loads(response.read().decode("utf-8"))
        name = data.get("display_name")
        return name.strip() if isinstance(name, str) and name.strip() else None
    except Exception:
        return None
