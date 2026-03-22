# 360 SaaS

A multi-tenant 360-degree performance review SaaS built with **Node.js/Express**, **PostgreSQL**, and **React/Vite**.

## Features

- Multi-tenant architecture with Postgres Row-Level Security (RLS)
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
      db.js           # PostgreSQL pool
      migrations.sql  # Full schema + RLS policies
      server.js       # Express API server
    package.json
    .env.example
  frontend/
    src/
      App.jsx         # Main React UI
    .env.example
```

## Quick Start (WSL / Linux)

### 1. Backend

```bash
cd backend
npm install
cp .env.example .env
# Edit .env with your Postgres credentials
createdb -U postgres saas360
psql "$DATABASE_URL" -f src/migrations.sql
npm run dev
```

### 2. Create your first tenant

```bash
curl -X POST http://localhost:4000/tenants \
  -H "Content-Type: application/json" \
  -d '{"name": "My Company", "slug": "my-company", "ownerEmail": "you@example.com", "ownerName": "Your Name"}'
```

Copy the `tenant.id` from the response.

### 3. Frontend

```bash
cd frontend
npm create vite@latest . -- --template react
npm install
cp .env.example .env
# Edit .env — paste your tenant.id as VITE_TENANT_ID
# Copy src/App.jsx from this repo into your frontend/src/
npm run dev
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

All endpoints except `POST /tenants` require an `x-tenant-id` header.

## Tech Stack

- **Backend**: Node.js, Express, PostgreSQL, JWT
- **Frontend**: React, Vite
- **Security**: Postgres RLS per-tenant isolation
- **Deployment**: Deploy backend to Render/Fly.io, frontend to Vercel/Netlify

## Next Steps

- Add full JWT auth (login/logout)
- Survey forms with Likert-scale questions
- Rater assignment and email invites
- Report dashboards with charts
- Stripe billing integration
- SSO / Auth0 integration
