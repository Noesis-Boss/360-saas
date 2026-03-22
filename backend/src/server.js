require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const { pool } = require('./db');

const app = express();
app.use(cors());
app.use(express.json());

// Tenant context middleware
function tenantContext(req, res, next) {
  const tenantId = req.header('x-tenant-id');
  if (!tenantId) {
    return res.status(400).json({ error: 'x-tenant-id header required' });
  }
  req.tenantId = tenantId;
  pool.query('SET app.current_tenant = $1', [tenantId])
    .then(() => next())
    .catch((err) => {
      console.error('Error setting tenant context', err);
      res.status(500).json({ error: 'Failed to set tenant context' });
    });
}

// Public: Create a new tenant (sign-up)
app.post('/tenants', async (req, res) => {
  const { name, slug, ownerEmail, ownerName } = req.body;
  if (!name || !slug || !ownerEmail || !ownerName) {
    return res.status(400).json({ error: 'name, slug, ownerEmail, ownerName required' });
  }
  try {
    const { rows: tenantRows } = await pool.query(
      'INSERT INTO tenants (name, slug) VALUES ($1, $2) RETURNING *',
      [name, slug]
    );
    const tenant = tenantRows[0];
    const { rows: userRows } = await pool.query(
      'INSERT INTO users (tenant_id, email, name, role) VALUES ($1, $2, $3, $4) RETURNING *',
      [tenant.id, ownerEmail, ownerName, 'owner']
    );
    const owner = userRows[0];
    const token = jwt.sign(
      { sub: owner.id, tenant_id: tenant.id, role: owner.role, email: owner.email },
      process.env.JWT_SECRET,
      { expiresIn: '1d' }
    );
    res.json({ tenant, owner, token });
  } catch (err) {
    console.error('Error creating tenant', err);
    res.status(500).json({ error: 'Failed to create tenant' });
  }
});

// Apply tenant middleware to all routes below
app.use(tenantContext);

// Health check
app.get('/health', async (req, res) => {
  try {
    const { rows } = await pool.query('SELECT NOW() AS now');
    res.json({ status: 'ok', tenant_id: req.tenantId, now: rows[0].now });
  } catch (err) {
    console.error('Health error', err);
    res.status(500).json({ error: 'Health check failed' });
  }
});

// Get current user (first user in tenant for demo)
app.get('/me', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, email, name, role, created_at FROM users WHERE tenant_id = $1 ORDER BY created_at LIMIT 1',
      [req.tenantId]
    );
    res.json({ user: rows[0] || null });
  } catch (err) {
    console.error('Me error', err);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// Invite a user to the tenant
app.post('/users/invite', async (req, res) => {
  const { email, name, role } = req.body;
  if (!email || !name) return res.status(400).json({ error: 'email and name required' });
  try {
    const { rows } = await pool.query(
      'INSERT INTO users (tenant_id, email, name, role) VALUES ($1, $2, $3, $4) RETURNING *',
      [req.tenantId, email, name, role || 'employee']
    );
    res.json({ user: rows[0] });
  } catch (err) {
    console.error('Invite error', err);
    res.status(500).json({ error: 'Failed to invite user' });
  }
});

// List all users in tenant
app.get('/users', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, email, name, role, created_at FROM users WHERE tenant_id = $1 ORDER BY created_at',
      [req.tenantId]
    );
    res.json({ users: rows });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// Create a review cycle
app.post('/review-cycles', async (req, res) => {
  const { name, start_date, end_date } = req.body;
  if (!name) return res.status(400).json({ error: 'name required' });
  try {
    const { rows } = await pool.query(
      'INSERT INTO review_cycles (tenant_id, name, start_date, end_date) VALUES ($1, $2, $3, $4) RETURNING *',
      [req.tenantId, name, start_date || null, end_date || null]
    );
    res.json({ cycle: rows[0] });
  } catch (err) {
    res.status(500).json({ error: 'Failed to create review cycle' });
  }
});

// List review cycles
app.get('/review-cycles', async (req, res) => {
  try {
    const { rows } = await pool.query(
      'SELECT * FROM review_cycles WHERE tenant_id = $1 ORDER BY created_at DESC',
      [req.tenantId]
    );
    res.json({ cycles: rows });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch review cycles' });
  }
});

// Get anonymized report for a reviewee in a cycle
app.get('/reports/:revieweeId/:cycleId', async (req, res) => {
  const { revieweeId, cycleId } = req.params;
  const minRaters = 3;
  try {
    const { rows } = await pool.query(
      `SELECT q.competency_id, rr.relationship_type,
        COUNT(r.id) as count, AVG(r.rating)::numeric(10,2) as avg_rating
       FROM responses r
       JOIN questions q ON q.id = r.question_id
       JOIN review_relationships rr
         ON rr.reviewee_id = r.reviewee_id AND rr.rater_id = r.rater_id
       WHERE r.reviewee_id = $1 AND r.review_cycle_id = $2
         AND r.tenant_id = $3 AND r.rating IS NOT NULL
       GROUP BY q.competency_id, rr.relationship_type`,
      [revieweeId, cycleId, req.tenantId]
    );
    const filtered = rows.filter(
      (row) => row.relationship_type === 'self' || Number(row.count) >= minRaters
    );
    res.json({ data: filtered });
  } catch (err) {
    res.status(500).json({ error: 'Failed to generate report' });
  }
});

const port = process.env.PORT || 4000;
app.listen(port, () => {
  console.log(`360 SaaS backend running on port ${port}`);
});
