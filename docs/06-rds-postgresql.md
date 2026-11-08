# Module 02 – Amazon RDS for PostgreSQL

**Project:** ABC Insurance  
**AWS Region:** `us-east-1`  
**Status:** RDS configured, private connectivity verified, tables created, sample data loaded and validated  
**Date:** November 6–7, 2026

## 1. Objective

This module explores how Amazon RDS for PostgreSQL supplies structured operational data to an insurance application and, later, to a Generative AI application.

The focus is AWS configuration, private connectivity, security, operations, and application access—not deep PostgreSQL development.

In the ABC Insurance Hybrid RAG chatbot:

- **Amazon RDS for PostgreSQL** stores structured operational records such as customers, policies, claims, and payments.
- **Amazon S3 and Amazon Bedrock Knowledge Bases** provide retrieval from unstructured insurance policy documents, coverage terms, and exclusions.
- **A Python application/orchestration layer** retrieves information from both sources and supplies relevant context to an Amazon Bedrock model.

RDS does not automatically connect to a Bedrock Knowledge Base. The Python application coordinates the two retrieval paths.

## 2. Network architecture

The RDS database is deployed in the dedicated VPC created in Module 01.

| Resource | Configuration |
|---|---|
| VPC | `abc-insurance-vpc` |
| VPC ID | `vpc-05dcc05b6e590fbf1` |
| VPC CIDR | `10.0.0.0/16` |
| DB subnet group | `abc-insurance-db-subnet-group` |
| Private DB subnet A | `10.0.20.0/24` – `us-east-1a` |
| Private DB subnet B | `10.0.21.0/24` – `us-east-1b` |
| RDS security group | `abc-insurance-rds-sg` |
| Application security group | `abc-insurance-app-sg` |

The DB subnet group contains two private subnets in separate Availability Zones. A DB subnet group defines the subnets and Availability Zones where RDS can place a database. It does not, by itself, make the database Multi-AZ.

The RDS console confirmed **Publicly accessible: No**. Applications should use the RDS DNS endpoint rather than a hard-coded IP address.

## 3. RDS instance configuration

The following settings were selected or observed during creation. Items marked **Verify** should be checked in the live console before treating them as final inventory.

| Setting | Value |
|---|---|
| DB instance identifier | `abc-insurance-database` |
| Engine | Amazon RDS for PostgreSQL (standard RDS, not Aurora) |
| Engine version | PostgreSQL `17.7-R1` |
| Template | Sandbox |
| Master username | `abc_insurance` |
| Instance class | `db.t4g.micro` |
| vCPU / memory shown | 2 vCPU / 1 GiB |
| Allocated storage | 20 GiB |
| Storage type | Verify in RDS console |
| Network type | IPv4 |
| VPC | `abc-insurance-vpc` |
| DB subnet group | `abc-insurance-db-subnet-group` |
| Publicly accessible | No |
| Port | `5432` |
| Availability deployment | Verify whether Single-AZ or Multi-AZ |
| Encryption | Enabled; AWS-managed `aws/rds` KMS key selected |
| Parameter group | `default.postgres17` |
| Option group | `default:postgres-17` |
| Certificate authority | `rds-ca-rsa2048-g1` |
| Automated backups | Enabled; 1-day retention selected |
| Backup window | No preference |
| Copy tags to snapshots | Enabled |
| Backup replication | Disabled |
| Automatic minor version upgrade | Enabled |
| Deletion protection | Disabled |
| RDS Proxy | Not enabled |
| Extended Support | Checkbox left unchecked |
| Authentication | Password authentication |
| Credentials management | Self-managed |

## 4. Connectivity and security

The RDS console showed:

- VPC: `abc-insurance-vpc`
- DB subnet group: `abc-insurance-db-subnet-group`
- Port: `5432`
- Publicly accessible: `No`
- Security group: `abc-insurance-rds-sg`

This keeps the database off the public internet. A client needs a private network path into the VPC and permission from the relevant security groups.

### 4.1 Security group rule

The RDS security group initially had no inbound rules. After creating the CloudShell VPC environment, one inbound rule was added:

| Type | Protocol | Port | Source |
|---|---|---:|---|
| PostgreSQL | TCP | 5432 | `abc-insurance-app-sg` |

No `0.0.0.0/0` inbound rule was added.

The application security group was selected for the CloudShell VPC environment. The exact CloudShell subnet selection should be confirmed from the environment details and recorded in the final inventory.

Security groups are stateful. The RDS inbound rule permits PostgreSQL traffic from network interfaces associated with the application security group. The application's outbound rules must also permit the connection; its default allow-all outbound rule was retained.

## 5. CloudShell VPC connectivity test

A standard CloudShell session was inspected first. Its route output included:

```text
169.254.255.192/26 dev eth0 proto kernel scope link src 169.254.255.194
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown
```

These addresses did not establish that standard CloudShell was attached to the project VPC.

A **CloudShell VPC environment** was then created and configured for the project VPC, using `abc-insurance-app-sg`.

The CloudShell environment already had the PostgreSQL command-line client:

```text
psql (PostgreSQL) 16.15
```

Using the RDS endpoint, port `5432`, username `abc_insurance`, and the interactive password prompt, the connection succeeded and displayed:

```text
postgres=>
```

This verified that the selected CloudShell VPC environment could reach the private RDS endpoint and authenticate.

### 5.1 PostgreSQL server version

The following query was executed:

```sql
SELECT version();
```

Observed result:

```text
PostgreSQL 17.7 on aarch64-unknown-linux-gnu,
compiled by aarch64-unknown-linux-gnu-gcc (GCC) 12.4.0, 64-bit
```

The CloudShell `psql` client reported version 16.15 while the RDS server reported version 17.7. The connection succeeded.

### 5.2 Database and user verification

```sql
SELECT current_database();
```

Initial result: `postgres`

```sql
SELECT current_user;
```

Result: `abc_insurance`

The connection was authenticated as `abc_insurance` and was initially connected to the default `postgres` database.

A direct SQL query was used to list databases:

```sql
SELECT datname FROM pg_database;
```

Observed application database:

```text
abc_insurance
```

The `abc_insurance` database was created inside the existing RDS instance. This is a logical PostgreSQL database, not a second RDS instance.

Important distinction:

- `abc-insurance-database` — the AWS RDS DB instance (managed PostgreSQL server).
- `abc_insurance` — a PostgreSQL database hosted inside that RDS instance.
- `abc_insurance` — also the PostgreSQL login username. A database and a user/role are separate objects even when they share a name.

The session was switched to the application database:

```text
\c abc_insurance
```

The prompt changed to:

```text
abc_insurance=>
```

## 6. Database structure and sample data

Four tables were created in the `abc_insurance` database to represent a simplified insurance operational system.

| Table | Purpose | Sample records |
|---|---|---:|
| `customers` | Customer details | 2 |
| `policies` | Insurance policy information | 2 |
| `claims` | Claims submitted against policies | 2 |
| `payments` | Payments recorded against claims | 2 |
| **Total** | | **8** |

### 6.1 Table relationships

The logical relationships are:

```text
customers
    |
    | customer_id
    |
    v
policies
    |
    | policy_id
    |
    v
claims
    |
    | claim_id
    |
    v
payments
```

- One customer can have multiple policies.
- One policy can have multiple claims.
- One claim can have multiple payments.

These relationships allow the application to retrieve customer, policy, claim, and payment information together.

### 6.2 Synthetic sample records

All records are fictional and created for this learning project.

**Customers**

| Customer ID | Name | Province |
|---|---|---|
| C1001 | Jordan Lee | Ontario |
| C1002 | Taylor Morgan | Ontario |

**Policies**

| Policy ID | Customer ID | Type | Status | Start date | End date | Deductible |
|---|---|---|---|---|---|---:|
| ABC-AUTO-SAMPLE-1001 | C1001 | Personal Auto | Active | 2026-01-01 | 2026-12-31 | $1,000 |
| ABC-AUTO-SAMPLE-1002 | C1002 | Personal Auto | Active | 2026-03-01 | 2027-02-28 | $1,000 |

**Claims**

| Claim ID | Policy ID | Loss type | Claim amount | Status |
|---|---|---|---:|---|
| CLM-9001 | ABC-AUTO-SAMPLE-1001 | Collision | $6,000 | Under Review |
| CLM-9002 | ABC-AUTO-SAMPLE-1002 | Comprehensive - Hail | $2,400 | Approved |

**Payments**

| Payment ID | Claim ID | Payment date | Amount | Status |
|---|---|---|---:|---|
| PAY-7001 | CLM-9001 | 2026-10-20 | $2,000 | Paid |
| PAY-7002 | CLM-9002 | 2026-10-02 | $1,900 | Paid |

The database seed script uses `CREATE TABLE IF NOT EXISTS` and `ON CONFLICT DO NOTHING` to make repeated execution safe for these sample records.

The sample policy PDF in S3 contains the coverage terms for `ABC-AUTO-SAMPLE-1001`. The second policy is included as operational sample data; its detailed policy terms are not represented in that PDF. The chatbot must not assume coverage terms for the second policy without supporting policy documentation.

## 7. SQL validation and multi-table query

After loading the sample data, each table was queried independently.

Examples:

```sql
SELECT * FROM customers ORDER BY customer_id;

SELECT * FROM policies ORDER BY policy_id;

SELECT * FROM claims ORDER BY claim_id;

SELECT * FROM payments ORDER BY payment_id;
```

Each query returned two records.

### 7.1 Multi-table join

A multi-table SQL query was then executed to retrieve claim details together with the customer name, policy ID, and total payments recorded against each claim.

```sql
SELECT
    c.claim_id,
    p.policy_id,
    cu.full_name,
    c.claim_amount,
    c.claim_status,
    COALESCE(SUM(py.payment_amount), 0) AS total_paid
FROM claims c
JOIN policies p
    ON c.policy_id = p.policy_id
JOIN customers cu
    ON p.customer_id = cu.customer_id
LEFT JOIN payments py
    ON c.claim_id = py.claim_id
GROUP BY
    c.claim_id,
    p.policy_id,
    cu.full_name,
    c.claim_amount,
    c.claim_status
ORDER BY c.claim_id;
```

### 7.2 Query results

| Claim ID | Policy ID | Customer | Claim amount | Claim status | Total paid |
|---|---|---|---:|---|---:|
| CLM-9001 | ABC-AUTO-SAMPLE-1001 | Jordan Lee | $6,000 | Under Review | $2,000 |
| CLM-9002 | ABC-AUTO-SAMPLE-1002 | Taylor Morgan | $2,400 | Approved | $1,900 |

The query successfully returned both claims with their associated customer, policy, and payment information.

### 7.3 Business calculation

The remaining amount is calculated for this demonstration as:

```text
Remaining amount = Claim amount - Total paid
```

| Claim ID | Claim amount | Total paid | Remaining amount |
|---|---:|---:|---:|
| CLM-9001 | $6,000 | $2,000 | $4,000 |
| CLM-9002 | $2,400 | $1,900 | $500 |

This is an illustrative calculation, not a determination of final insurer liability or outstanding approved benefits.

### 7.4 SQL concepts exercised

The validation query demonstrated:

- `JOIN` — combines related records across tables.
- `LEFT JOIN` — retains claims even when no payment exists.
- `SUM()` — calculates total payments.
- `COALESCE()` — returns zero when no payment total is available.
- `GROUP BY` — aggregates payments at claim level.
- `ORDER BY` — sorts the final result.

The objective was to validate that the relational data can support application queries, rather than to conduct advanced PostgreSQL development.

## 8. Role of RDS in the Generative AI application

The intended Hybrid RAG retrieval flow is:

1. An employee asks the ABC Insurance AI assistant a question.
2. The Python application identifies the structured facts required.
3. The application queries RDS for operational records such as customer, claim, policy status, or payment information.
4. The application retrieves relevant policy-document passages from the Amazon Bedrock Knowledge Base backed by S3 and S3 Vectors.
5. The application combines the structured records and retrieved document evidence as context for the model.
6. Amazon Bedrock generates a response grounded in the available sources.

For example:

**Question:** What is the status of Jordan Lee's collision claim, and how much has been paid?

- RDS provides the claim status, claim amount, and recorded payment total.
- The Knowledge Base can provide relevant policy wording, such as collision coverage and deductible conditions.
- Python combines the retrieved information before invoking the model.

RDS is the source for structured operational facts. The Knowledge Base is the retrieval source for unstructured document content. The application/orchestration layer connects the two.

## 9. Security and operational considerations

- The RDS instance is not publicly accessible.
- Database access is restricted through the RDS security group.
- PostgreSQL traffic uses TCP port `5432`.
- Database credentials must not be committed to GitHub.
- Python should retrieve credentials securely, preferably through AWS Secrets Manager when implemented.
- The RDS endpoint should be read from configuration rather than hard-coded throughout the application.
- The database should be stopped when the learning environment is not needed, subject to RDS's automatic restart behavior and ongoing storage/backup charges.
- Before deleting the RDS instance, review whether a final snapshot is required.

## 10. Suggested screenshots

Store screenshots under:

```text
screenshots/
└── 02-rds/
    ├── 01-db-subnet-group-created.png
    ├── 02-rds-data-validation-joins.png
    └── 03-rds-data-validation-joins.png
```

| Screenshot | Evidence |
|---|---|
| `01-db-subnet-group-created.png` | RDS DB subnet group and its private subnets |
| `02-rds-data-validation-joins.png` | SQL output showing the customers, policies, claims, and payments records |
| `03-rds-data-validation-joins.png` | Multi-table SQL join and aggregated payment results |

## 11. Module completion summary

| Area | Result |
|---|---|
| RDS PostgreSQL instance | Created |
| Private DB subnet group | Configured |
| Public accessibility | Disabled |
| Security group access | Restricted to application security group |
| CloudShell VPC connectivity | Successfully tested |
| PostgreSQL authentication | Successful |
| Application database | `abc_insurance` created |
| Tables | 4 created |
| Synthetic records | 8 inserted and verified |
| Multi-table join | Successfully executed |
| Payment aggregation | Successfully validated |
| Hybrid RAG integration | Planned for Python module |

**Module 02 is complete.** The structured operational data is ready for the Python application integration phase.

The next module will connect the Python application to both Amazon RDS for PostgreSQL and the Amazon Bedrock Knowledge Base to implement the ABC Insurance Hybrid RAG chatbot.
