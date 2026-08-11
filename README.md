# InternHub — Attendance & Project Management System

A full-stack intern operations platform for **attendance**, **projects/tasks**, **leave**, **standups**, **cohorts**, and **performance reviews**.

**Backend:** FastAPI, SQLAlchemy, MySQL  
**Frontend:** React 19, Vite, React Router, TanStack Query, Tailwind CSS, Recharts

## Features

- Login / Register / Logout with role-based access (admin / mentor / intern)
- Attendance — check-in / check-out, history, reports, Excel/CSV export
- Projects — create, assign interns & mentors, tasks with deadlines and priorities
- Leave requests — interns submit, mentors/admins approve or reject
- Dashboard — stats and charts (attendance, projects, tasks)
- Admin — user management, invite links, intern assignments, audit log
- Standups, announcements, cohorts, performance reviews

## Prerequisites

- Python 3.9+
- Node.js 18+ (for the React UI)
- MySQL 8.0+ (or MariaDB 10.4+)

## Quick Start

### 1. Backend dependencies

```powershell
cd "internhub backend"
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Configure environment

Create a `.env` file in the project root:

```
MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=your_password
MYSQL_DATABASE=internhub
SECRET_KEY=generate-a-long-random-string-here
```

Use a strong, unique `SECRET_KEY` for any shared or production deployment.

### 3. Create database and tables

```powershell
python init_db.py
```

This creates the `internhub` database (if missing) and all tables. Schema changes are also synced automatically on app startup.

### 4. Build the React UI

```powershell
cd "..\internhub frontend"
npm install
npm run build
cd "..\internhub backend"
```

### 5. Run the app

```powershell
python main.py
```

Open <http://127.0.0.1:3001>

FastAPI serves the JSON API on `/api/*` and serves the built Vite SPA from the
sibling `internhub frontend/dist` directory.

### 6. Sign in

Use accounts that already exist in your MySQL database. InternHub does not ship fixed login credentials — create users via the admin panel or your own data import.

> **Optional demo data:** `python seed.py` wipes **all** users and inserts demo accounts (`admin@demo.com`, etc.). Only run this on a fresh database if you want sample data.

## Development

**Backend/API:** from `internhub backend`, run `python main.py` (port 3001).

**Frontend dev server:** in another terminal, run
`cd "internhub frontend" && npm run dev`. Vite runs on port 5173 and proxies
`/api` to `http://127.0.0.1:3001`.

**API docs:** <http://127.0.0.1:3001/api/docs>

## Project Structure

```
Intern Hub/
├── internhub backend/
│   ├── main.py              # FastAPI entry + Vite SPA hosting + scheduler
│   ├── config.py            # MySQL + shift/session settings
│   ├── database.py          # SQLAlchemy engine & sessions
│   ├── models.py            # ORM models
│   ├── dependencies.py      # Bearer-token authentication
│   ├── utils.py             # Attendance logic, exports, notifications
│   ├── init_db.py           # Create MySQL database + tables
│   ├── migrate_db.py        # Idempotent schema sync
│   ├── seed.py              # Optional demo data (wipes existing users)
│   └── routes/api/          # JSON API routes
└── internhub frontend/
    ├── vite.config.ts       # Dev server and /api proxy
    └── src/
        ├── routes/          # React Router pages
        ├── components/      # UI components
        └── lib/api.ts       # Typed API client
```

## Notes

- Runs locally on `http://127.0.0.1:3001` via Uvicorn. For production, use Uvicorn/Gunicorn behind a reverse proxy.
- Times use `APP_TIMEZONE` (default `Asia/Kolkata`), not the host OS timezone.
- Set `DB_CLEAR_PASSWORD` in `.env` if you need the admin “clear database” panel.

## Deploy on Railway

See **[RAILWAY.md](RAILWAY.md)** for the full checklist (MySQL plugin, `DATABASE_URL`,
`PUBLIC_SITE_URL`, volume for attendance photos, health check).

Quick version: set the service Root Directory to this folder, add a Railway MySQL
service, wire `DATABASE_URL` + `SECRET_KEY` + `PUBLIC_SITE_URL`, and deploy.
Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`.
