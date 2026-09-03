# Marketing Page Demo Form Auto-Popup & Exit-Intent Design

## Goal
Automatically present the demo booking form modal when a user lands on the InternHub marketing website, provide exit-intent engagement before visitors leave, and seamlessly send lead details to the backend demo/leads capture API.

## Requirements
1. **Auto-Popup Trigger**:
   - On visitor initial landing, trigger `DemoModal` automatically after a smooth ~800ms delay.
   - Track session state (`sessionStorage.getItem('internhub_demo_seen')`) so internal routing/page navigation does not repeatedly flash the popup during the same session.
2. **Exit-Intent Trigger**:
   - On desktop viewport, detect `mouseleave` towards the top edge (`e.clientY <= 10`).
   - If the user previously closed the initial popup and has not submitted the form, offer one gentle re-engagement popup before exit.
3. **API Integration**:
   - Utilize existing `POST /api/leads` backend endpoint (`routes/api/leads.py`).
   - Handle network fallback, loading states, validation error notices, and anti-spam honeypot.
4. **Manual CTAs**:
   - Preserve all existing buttons across navbar, hero, and CTA sections so clicking opens the modal immediately.

## Data Flow
- User lands on `/` or any marketing route -> `App.tsx` checks `sessionStorage` -> schedules 800ms timeout to open modal -> sets `internhub_demo_seen`.
- User interacts with form in `DemoModal.tsx` -> submits payload to `/api/leads` endpoint -> shows success state and closes.
