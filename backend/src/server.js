require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const { pool } = require('./db');

const app = express();
app.use(cors());
app.use(express.json());

// Tenant context middleware
// MySQL does not support RLS; tenant isolation is enforced via WHERE tenant_id = ? in all queries.
function tenantContext(req, res, next) {
  const tenantId = req.header('x-tenant-id');
  if (!tenantId) {
    return res.status(400).json({ error: 'x-tenant-id header required' });
  }
  req.tenantId = tenantId;
  next();
}

// Public: Create a new tenant (sign-up)
app.post('/tenants', async (req, res) => {
  const { name, slug, ownerEmail, ownerName } = req.body;
  if (!name || !slug || !ownerEmail || !ownerName) {
    return res.status(400).json({ error: 'name, slug, ownerEmail, ownerName required' });
  }
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const tenantId = require('crypto').randomUUID();
    await conn.execute(
      'INSERT INTO tenants (id, name, slug) VALUES (?, ?, ?)',
      [tenantId, name, slug]
    );
    const userId = require('crypto').randomUUID();
    await conn.execute(
      'INSERT INTO users (id, tenant_id, email, name, role) VALUES (?, ?, ?, ?, ?)',
      [userId, tenantId, ownerEmail, ownerName, 'admin']
    );
    await conn.commit();
    const token = jwt.sign({ userId, tenantId, role: 'admin' }, process.env.JWT_SECRET, { expiresIn: '7d' });
    res.status(201).json({ tenantId, userId, token });
  } catch (err) {
    await conn.rollback();
    console.error('Error creating tenant:', err);
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: 'Slug already taken' });
    }
    res.status(500).json({ error: 'Failed to create tenant' });
  } finally {
    conn.release();
  }
});

// Public: Health check (tenant-scoped)
app.get('/health', tenantContext, async (req, res) => {
  try {
    const [rows] = await pool.execute('SELECT id, name, slug, plan FROM tenants WHERE id = ?', [req.tenantId]);
    if (!rows.length) return res.status(404).json({ error: 'Tenant not found' });
    res.json({ status: 'ok', tenant: rows[0] });
  } catch (err) {
    res.status(500).json({ error: 'Health check failed' });
  }
});

// Auth middleware
function authMiddleware(req, res, next) {
  const auth = req.header('Authorization');
  if (!auth) return res.status(401).json({ error: 'No token provided' });
  try {
    const token = auth.replace('Bearer ', '');
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    req.tenantId = decoded.tenantId;
    next();
  } catch (err) {
    res.status(401).json({ error: 'Invalid token' });
  }
}

// GET /me - current user
app.get('/me', authMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      'SELECT id, email, name, role, created_at FROM users WHERE id = ? AND tenant_id = ?',
      [req.user.userId, req.tenantId]
    );
    if (!rows.length) return res.status(404).json({ error: 'User not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to get user' });
  }
});

// GET /users - list all users in tenant
app.get('/users', authMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      'SELECT id, email, name, role, created_at FROM users WHERE tenant_id = ?',
      [req.tenantId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to list users' });
  }
});

// POST /users/invite - invite a user
app.post('/users/invite', authMiddleware, async (req, res) => {
  const { email, name, role } = req.body;
  if (!email || !name) return res.status(400).json({ error: 'email and name required' });
  try {
    const userId = require('crypto').randomUUID();
    await pool.execute(
      'INSERT INTO users (id, tenant_id, email, name, role) VALUES (?, ?, ?, ?, ?)',
      [userId, req.tenantId, email, name, role || 'employee']
    );
    res.status(201).json({ userId, email, name });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: 'User already exists in this tenant' });
    }
    res.status(500).json({ error: 'Failed to invite user' });
  }
});

// POST /review-cycles - create a review cycle
app.post('/review-cycles', authMiddleware, async (req, res) => {
  const { name, startDate, endDate } = req.body;
  if (!name) return res.status(400).json({ error: 'name required' });
  try {
    const cycleId = require('crypto').randomUUID();
    await pool.execute(
      'INSERT INTO review_cycles (id, tenant_id, name, start_date, end_date) VALUES (?, ?, ?, ?, ?)',
      [cycleId, req.tenantId, name, startDate || null, endDate || null]
    );
    res.status(201).json({ cycleId, name });
  } catch (err) {
    res.status(500).json({ error: 'Failed to create review cycle' });
  }
});

// GET /review-cycles - list all review cycles for tenant
app.get('/review-cycles', authMiddleware, async (req, res) => {
  try {
    const [rows] = await pool.execute(
      'SELECT id, name, start_date, end_date, status, created_at FROM review_cycles WHERE tenant_id = ? ORDER BY created_at DESC',
      [req.tenantId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to list review cycles' });
  }
});

// GET /reports/:revieweeId/:cycleId - anonymized report (min 3 raters)
app.get('/reports/:revieweeId/:cycleId', authMiddleware, async (req, res) => {
  const { revieweeId, cycleId } = req.params;
  try {
    const [rows] = await pool.execute(
      `SELECT c.name AS competency, AVG(sr.score) AS avg_score, COUNT(sr.id) AS rater_count
       FROM survey_responses sr
       JOIN competencies c ON sr.competency_id = c.id
       JOIN review_cycles rc ON sr.cycle_id = rc.id
       WHERE sr.reviewee_id = ? AND sr.cycle_id = ? AND rc.tenant_id = ?
       GROUP BY sr.competency_id, c.name
       HAVING COUNT(sr.id) >= 3`,
      [revieweeId, cycleId, req.tenantId]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to generate report' });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => console.log(`360 SaaS API running on port ${PORT}`));
