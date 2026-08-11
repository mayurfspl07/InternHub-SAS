# Deploy InternHub backend on Railway

This folder is a self-contained FastAPI service. Deploy it as its own Railway
service with **Root Directory** set to `internhub backend` (if your Git repo
also contains the frontend).

## 1. Create services

1. New Railway project → **GitHub Repo** (or empty project + CLI).
2. Add a **MySQL** database service (Railway → New → Database → MySQL).
3. Add / select the **web** service that builds this backend folder.

## 2. Configure variables (web service)

| Variable | Value |
|----------|--------|
| `SECRET_KEY` | Long random string (`openssl rand -hex 32`) |
| `DATABASE_URL` | Reference → MySQL service `MYSQL_URL` or `DATABASE_URL` |
| `PUBLIC_SITE_URL` | Your public HTTPS URL, e.g. `https://….up.railway.app` |
| `CORS_ORIGINS` | Same public URL (+ local Vite origins if needed) |
| `BOOTSTRAP_ADMIN_EMAIL` | Admin email for first boot |
| `BOOTSTRAP_ADMIN_PASSWORD` | Strong password (do not keep the code default) |
| `APP_TIMEZONE` | `Asia/Kolkata` (optional; this is the default) |
| `ATTENDANCE_PHOTOS_DIR` | `/data/attendance_photos` if you attach a volume |

`PORT` is injected by Railway — do not hard-code it.

### Variable reference example

In the web service Variables tab:

```text
DATABASE_URL=${{MySQL.MYSQL_URL}}
```

(Use the exact MySQL service name Railway shows.)

The app accepts `mysql://…` URLs from Railway and rewrites them to
`mysql+pymysql://…` for SQLAlchemy.

## 3. Networking

- Enable **Public Networking** on the web service.
- Health check path is `/api/health` (configured in `railway.toml`).
- After the first deploy, set `PUBLIC_SITE_URL` to the generated domain (or your custom domain) and redeploy if invite links / CORS need it.

## 4. Persistent attendance photos (recommended)

Railway's filesystem is ephemeral. To keep check-in selfies:

1. Web service → **Volumes** → mount at `/data`.
2. Set `ATTENDANCE_PHOTOS_DIR=/data/attendance_photos`.

## 5. Frontend

- **API-only:** this deploy works without a SPA build; open `/api/docs`.
- **Same-origin SPA:** build the React app, copy `internhub frontend/dist` into the image (or set `FRONTEND_DIST_DIR`), then the backend serves UI + API together.

Schema tables are created/updated automatically on startup (`migrate_db.sync_schema`). You do **not** need to run `init_db.py` on Railway (the MySQL plugin already provides a database).

## 6. Verify

```text
GET https://your-service.up.railway.app/api/health
→ {"status":"ok","service":"internhub"}
```

Sign in with the bootstrap admin, then change the password.
