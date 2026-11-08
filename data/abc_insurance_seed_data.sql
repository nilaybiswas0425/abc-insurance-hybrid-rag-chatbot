-- ABC Insurance synthetic seed data for standard Amazon RDS PostgreSQL
-- Connect to database abc_insurance before running this script.
-- All records are fictional training data; no real customer information.

CREATE TABLE IF NOT EXISTS customers (
  customer_id VARCHAR(20) PRIMARY KEY,
  full_name VARCHAR(100) NOT NULL,
  email VARCHAR(150) NOT NULL,
  province VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS policies (
  policy_id VARCHAR(30) PRIMARY KEY,
  customer_id VARCHAR(20) NOT NULL REFERENCES customers(customer_id),
  policy_type VARCHAR(40) NOT NULL,
  policy_status VARCHAR(20) NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  deductible NUMERIC(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS claims (
  claim_id VARCHAR(30) PRIMARY KEY,
  policy_id VARCHAR(30) NOT NULL REFERENCES policies(policy_id),
  loss_date DATE NOT NULL,
  loss_type VARCHAR(60) NOT NULL,
  claim_description TEXT NOT NULL,
  claim_amount NUMERIC(12,2) NOT NULL,
  claim_status VARCHAR(30) NOT NULL
);

CREATE TABLE IF NOT EXISTS payments (
  payment_id VARCHAR(30) PRIMARY KEY,
  claim_id VARCHAR(30) NOT NULL REFERENCES claims(claim_id),
  payment_date DATE NOT NULL,
  payment_amount NUMERIC(12,2) NOT NULL,
  payment_status VARCHAR(30) NOT NULL
);

INSERT INTO customers VALUES
('C1001', 'Jordan Lee', 'jordan.lee@example.test', 'Ontario'),
('C1002', 'Taylor Morgan', 'taylor.morgan@example.test', 'Ontario')
ON CONFLICT (customer_id) DO NOTHING;

INSERT INTO policies VALUES
('ABC-AUTO-SAMPLE-1001', 'C1001', 'Personal Auto', 'Active', '2026-01-01', '2026-12-31', 1000.00),
('ABC-AUTO-SAMPLE-1002', 'C1002', 'Personal Auto', 'Active', '2026-03-01', '2027-02-28', 1000.00)
ON CONFLICT (policy_id) DO NOTHING;

INSERT INTO claims VALUES
('CLM-9001', 'ABC-AUTO-SAMPLE-1001', '2026-10-12', 'Collision', 'Fictional two-vehicle collision; repair estimate submitted.', 6000.00, 'Under Review'),
('CLM-9002', 'ABC-AUTO-SAMPLE-1002', '2026-09-18', 'Comprehensive - Hail', 'Fictional hail damage to vehicle body panels.', 2400.00, 'Approved')
ON CONFLICT (claim_id) DO NOTHING;

INSERT INTO payments VALUES
('PAY-7001', 'CLM-9001', '2026-10-20', 2000.00, 'Paid'),
('PAY-7002', 'CLM-9002', '2026-10-02', 1900.00, 'Paid')
ON CONFLICT (payment_id) DO NOTHING;

-- Validation queries
SELECT * FROM customers ORDER BY customer_id;
SELECT * FROM policies ORDER BY policy_id;
SELECT * FROM claims ORDER BY claim_id;
SELECT * FROM payments ORDER BY payment_id;
