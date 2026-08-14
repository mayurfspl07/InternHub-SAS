# Deploy InternHub backend on Railway

This folder is a self-contained FastAPI service. Deploy it as its own Railway
service with **Root Directory** set to `internhub backend` (if your Git repo
also contains the frontend).

## 1. Create services

1. New Railway project → **GitHub Repo** (or empty project + CLI).
2. Add a **MySQL** database service (Railway → **New** → **Database** → **MySQL**).
3. Add / select the **web** service that builds this backend folder.

You need **two services in the same project**: the web app **and** MySQL.
MySQL variables live on the MySQL service — they are **not** copied to the web
service until you add a reference.

## 2. Wire MySQL into the web service (required)

This is the step that fixes:

`Can't connect to MySQL server on 'localhost'`

### Option A — one URL (recommended)

1. Open the **web** service → **Variables** → **New Variable**.
2. Name: `DATABASE_URL`
3. Value (Variable Reference):

```text
${{MySQL.MYSQL_URL}}
```

Replace `MySQL` with the **exact** name of your MySQL service in Railway
(e.g. `mysql`, `MySQL-abc123`). You can pick it from the reference UI instead
of typing.

Private networking (preferred when available):

```text
${{MySQL.MYSQL_PRIVATE_URL}}
```

### Option B — share individual MySQL fields

On the web service Variables tab, **Add Reference** for each of:

- `MYSQLHOST`
- `MYSQLPORT`
- `MYSQLUSER`
- `MYSQLPASSWORD`
- `MYSQLDATABASE`

(or the older `MYSQL_HOST` / `MYSQL_USER` names — both work).

## 3. Other required variables (web service)

| Variable | Value |
|----------|--------|
| `SECRET_KEY` | Long random string (`openssl rand -hex 32`) |
| `DATABASE_URL` | `${{MySQL.MYSQL_URL}}` (see above) |
| `PUBLIC_SITE_URL` | Your public HTTPS URL, e.g. `https://….up.railway.app` |
| `BOOTSTRAP_ADMIN_EMAIL` | Admin email for first boot |
| `BOOTSTRAP_ADMIN_PASSWORD` | Strong password (do not keep the code default) |
| `APP_TIMEZONE` | `Asia/Kolkata` (optional; this is the default) |
| `ATTENDANCE_PHOTOS_DIR` | `/data/attendance_photos` if you attach a volume |

`PORT` is injected by Railway — do not hard-code it.

After saving variables, **Redeploy** the web service.

The app accepts `mysql://…` URLs from Railway and rewrites them to
`mysql+pymysql://…` for SQLAlchemy.

## 4. Networking

- Enable **Public Networking** on the web service.
- Health check path is `/api/health` (configured in `railway.toml`).
- After the first successful deploy, set `PUBLIC_SITE_URL` to the generated
  domain (or your custom domain) and redeploy if invite links / CORS need it.

## 5. Persistent attendance photos (recommended)

Railway's filesystem is ephemeral. To keep check-in selfies:

1. Web service → **Volumes** → mount at `/data`.
2. Set `ATTENDANCE_PHOTOS_DIR=/data/attendance_photos`.

## 6. Frontend

- **API-only:** this deploy works without a SPA build; open `/api/docs`.
- **Same-origin SPA:** build the React app, copy `internhub frontend/dist` into
  the image (or set `FRONTEND_DIST_DIR`), then the backend serves UI + API together.

Schema tables are created/updated automatically on startup (`migrate_db.sync_schema`).
You do **not** need to run `init_db.py` on Railway (the MySQL plugin already
provides a database).

## 7. Verify

Logs should show something like:

```text
Database target: mysql.railway.internal:3306/railway
```

Not `localhost`.

```text
GET https://your-service.up.railway.app/api/health
→ {"status":"ok","service":"internhub"}
```

Sign in with the bootstrap admin, then change the password.

## Troubleshooting

| Log message | Meaning |
|-------------|---------|
| `Can't connect … 'localhost'` / `MySQL is not configured` | `DATABASE_URL` (or `MYSQLHOST`) is missing on the **web** service — add the variable reference and redeploy |
| `SECRET_KEY env var is not set` | Set `SECRET_KEY` on the web service |
| Connection refused to `*.railway.internal` | MySQL service still starting, or web/MySQL not in the same project — wait and redeploy, or use `MYSQL_URL` |
| Auth / access denied | Wrong password reference — re-add `${{MySQL.MYSQL_URL}}` from the MySQL service |
