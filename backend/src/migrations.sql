-- MySQL Migration for 360 SaaS
-- Multi-tenant 360-degree performance review platform
-- Note: MySQL does not support Row-Level Security (RLS).
-- Tenant isolation is enforced at the application layer via x-tenant-id header.

CREATE TABLE IF NOT EXISTS tenants (
  id VARCHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  slug VARCHAR(255) NOT NULL UNIQUE,
  plan VARCHAR(50) NOT NULL DEFAULT 'free',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS users (
  id VARCHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  tenant_id VARCHAR(36) NOT NULL,
  email VARCHAR(255) NOT NULL,
  name VARCHAR(255) NOT NULL,
  role VARCHAR(50) NOT NULL DEFAULT 'employee',
  password_hash TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_tenant_email (tenant_id, email),
  CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS review_cycles (
  id VARCHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  tenant_id VARCHAR(36) NOT NULL,
  name VARCHAR(255) NOT NULL,
  start_date DATE,
  end_date DATE,
  status VARCHAR(50) NOT NULL DEFAULT 'draft',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_cycles_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS competencies (
  id VARCHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  tenant_id VARCHAR(36) NOT NULL,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_competencies_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS rater_assignments (
  id VARCHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  cycle_id VARCHAR(36) NOT NULL,
  reviewee_id VARCHAR(36) NOT NULL,
  rater_id VARCHAR(36) NOT NULL,
  relationship VARCHAR(50) NOT NULL DEFAULT 'peer',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_assignment (cycle_id, reviewee_id, rater_id),
  CONSTRAINT fk_assignments_cycle FOREIGN KEY (cycle_id) REFERENCES review_cycles(id) ON DELETE CASCADE,
  CONSTRAINT fk_assignments_reviewee FOREIGN KEY (reviewee_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_assignments_rater FOREIGN KEY (rater_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS survey_responses (
  id VARCHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
  cycle_id VARCHAR(36) NOT NULL,
  reviewee_id VARCHAR(36) NOT NULL,
  rater_id VARCHAR(36) NOT NULL,
  competency_id VARCHAR(36) NOT NULL,
  score TINYINT NOT NULL CHECK (score BETWEEN 1 AND 5),
  comment TEXT,
  submitted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_response (cycle_id, reviewee_id, rater_id, competency_id),
  CONSTRAINT fk_responses_cycle FOREIGN KEY (cycle_id) REFERENCES review_cycles(id) ON DELETE CASCADE,
  CONSTRAINT fk_responses_reviewee FOREIGN KEY (reviewee_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_responses_rater FOREIGN KEY (rater_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_responses_competency FOREIGN KEY (competency_id) REFERENCES competencies(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Indexes for common tenant-scoped queries
CREATE INDEX idx_users_tenant ON users(tenant_id);
CREATE INDEX idx_cycles_tenant ON review_cycles(tenant_id);
CREATE INDEX idx_competencies_tenant ON competencies(tenant_id);
CREATE INDEX idx_assignments_cycle ON rater_assignments(cycle_id);
CREATE INDEX idx_responses_cycle_reviewee ON survey_responses(cycle_id, reviewee_id);
