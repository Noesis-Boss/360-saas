# 360 SaaS

A multi-tenant 360-degree performance review SaaS built with **Node.js/Express**, **MySQL**, and **React/Vite**.

## Features

- Multi-tenant architecture with application-layer tenant isolation
- Create and manage review cycles (e.g., "Q2 2026 Engineering 360")
- Invite team members per tenant
- Anonymous aggregated 360 responses (min 3 raters rule)
- REST API with JWT auth and tenant isolation
- React frontend with review cycle and user management UI

## Project Structure

```
360-saas/
  backend/
    src/
      db.js           # MySQL connection pool (mysql2)
      migrations.sql  # Full MySQL schema
      server.js       # Express API server
    package.json
    .env.example
  frontend/
    src/
      App.jsx         # Main React UI
    .env.example
```

## Quick Start (WSL / Linux)

### Prerequisites

- Node.js 18+
- MySQL 8.0+ running locally or remotely

### 1. Database Setup

```bash
mysql -u root -p
CREATE DATABASE saas360 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'saas360user'@'localhost' IDENTIFIED BY 'yourpassword';
GRANT ALL PRIVILEGES ON saas360.* TO 'saas360user'@'localhost';
FLUSH PRIVILEGES;
EXIT;

# Run migrations
mysql -u saas360user -p saas360 < backend/src/migrations.sql
```

### 2. Backend

```bash
cd backend
npm install
cp .env.example .env
# Edit .env with your MySQL credentials
npm run dev
```

### 3. Frontend

```bash
cd frontend
npm install
cp .env.example .env
# Edit .env - paste your tenant.id as VITE_TENANT_ID
npm run dev
```

## Environment Variables (backend/.env)

```
DB_HOST=localhost
DB_PORT=3306
DB_USER=saas360user
DB_PASSWORD=yourpassword
DB_NAME=saas360
JWT_SECRET=your_super_secret_jwt_key
PORT=3000
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /tenants | Create a new tenant (sign-up) |
| GET | /health | Health check (tenant-scoped) |
| GET | /me | Get current user |
| GET | /users | List all users in tenant |
| POST | /users/invite | Invite a user to the tenant |
| POST | /review-cycles | Create a review cycle |
| GET | /review-cycles | List all review cycles |
| GET | /reports/:revieweeId/:cycleId | Get anonymized report |

All endpoints except `POST /tenants` require an `x-tenant-id` header or Bearer JWT token.

## Tech Stack

- **Backend**: Node.js, Express, MySQL (mysql2), JWT
- **Frontend**: React, Vite
- **Security**: Application-layer tenant isolation via `WHERE tenant_id = ?` in all queries
- **Deployment**: Deploy backend to Render/Fly.io, frontend to Vercel/Netlify

## MySQL vs PostgreSQL Notes

- MySQL does not support Row-Level Security (RLS) — tenant isolation is enforced at the application layer
- UUIDs use `VARCHAR(36)` with `UUID()` default instead of PostgreSQL's `uuid` type
- Timestamps use `DATETIME` instead of `timestamptz`
- Query placeholders use `?` instead of `$1, $2`
- Uses `mysql2` npm package instead of `pg`

## Next Steps

- Add full JWT auth (login/logout)
- Survey forms with Likert-scale questions
- Rater assignment and email invites
- Competency management UI
- Dashboard with aggregated reports
