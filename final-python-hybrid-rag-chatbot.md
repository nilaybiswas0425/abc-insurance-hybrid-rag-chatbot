# ABC Insurance Hybrid RAG Chatbot

## Python Implementation and Code Walkthrough

**Project:** ABC Insurance Hybrid RAG Chatbot\
**Module:** 04 --- Python Hybrid RAG Chatbot\
**AWS Region:** `us-east-1`\
**Knowledge Base ID:** `E1RNVKEBQF`\
**Database:** Amazon RDS for PostgreSQL --- `abc_insurance`

------------------------------------------------------------------------

## 1. Purpose

This module combines two kinds of information to answer insurance
questions:

1.  **Structured data** from Amazon RDS for PostgreSQL --- customer,
    policy, claim and payment records.
2.  **Unstructured policy information** from Amazon Bedrock Knowledge
    Bases --- policy PDF content stored in Amazon S3 and indexed using
    Amazon S3 Vectors.

Python coordinates retrieval from both sources and sends the retrieved
evidence to Amazon Nova Lite to generate a response.

This is a retrieval-augmented generation (RAG) application. The model is
not expected to know private insurance records or policy wording. The
application retrieves relevant information and supplies it as context.

## 2. Architecture

``` text
User question
     |
     v
Python chatbot.py
     |
     +------------------------------+
     |                              |
     v                              v
Amazon RDS PostgreSQL        Amazon Bedrock Knowledge Base
Structured records           Policy PDF knowledge
     |                              |
     | SQL queries                  | Semantic retrieval
     |                              |
     +---------------+--------------+
                     |
                     v
             Retrieved evidence
                     |
                     v
             Amazon Nova Lite
             Answer generation
                     |
                     v
             Answer + source references
```

  -----------------------------------------------------------------------
  Component                           Responsibility
  ----------------------------------- -----------------------------------
  Python `chatbot.py`                 Orchestrates question handling,
                                      retrieval, prompting and response

  Amazon RDS PostgreSQL               Stores customer, policy, claim and
                                      payment records

  Amazon S3                           Stores the insurance policy PDF

  Amazon Bedrock Knowledge Base       Retrieves relevant passages from
                                      the policy document

  Amazon S3 Vectors                   Stores vector embeddings used for
                                      semantic search

  Amazon Nova Lite                    Generates a natural-language answer
                                      from supplied evidence

  AWS CloudShell VPC                  Runs Python where it can reach
                                      private RDS
  -----------------------------------------------------------------------

## 3. Why hybrid RAG?

Different questions need different retrieval methods.

-   **Structured question:** "What is the status of claim CLM-9001?" ---
    query PostgreSQL with SQL.
-   **Document question:** "What is the collision coverage deductible
    under policy ABC-AUTO-SAMPLE-1001?" --- retrieve policy wording from
    the Bedrock Knowledge Base.
-   **Combined question:** "Who owns claim CLM-9001 and what is the
    collision deductible?" --- retrieve from both sources.

Vector search does not replace SQL, and SQL is not a replacement for
searching long policy documents.

## 4. Python dependencies

  Package / library   Purpose
  ------------------- ---------------------------------------------------
  `boto3`             AWS SDK for Python; calls Bedrock services
  `psycopg2-binary`   PostgreSQL database driver
  `os`                Reads configuration from environment variables
  `re`                Identifies claim IDs and policy IDs in a question
  `botocore`          AWS SDK dependency installed with boto3

`os` and `re` are part of Python's standard library.

Example `requirements.txt`:

``` text
boto3
psycopg2-binary
```

Record the versions actually tested in the target environment for
reproducible deployments. A Mac and CloudShell have separate Python
environments.

## 5. Configuration and credentials

The application reads configuration from environment variables rather
than hardcoding passwords in source code.

  Variable          Purpose
  ----------------- ------------------------------------
  `AWS_REGION`      AWS Region, `us-east-1`
  `BEDROCK_KB_ID`   Knowledge Base ID, `E1RNVKEBQF`
  `RDS_HOST`        RDS PostgreSQL endpoint
  `RDS_PORT`        PostgreSQL port, `5432`
  `RDS_DB_NAME`     Database name, `abc_insurance`
  `RDS_USER`        Database username, `abc_insurance`
  `RDS_PASSWORD`    Database password

Do not commit passwords, AWS credentials, private keys, `.env` files or
sensitive endpoints to GitHub. For a longer-lived deployment, use AWS
Secrets Manager or another approved secrets-management approach instead
of manually exported shell variables.

### Network placement

RDS is private (`Publicly accessible = No`). The Mac cannot connect
directly to it over the public internet. The chatbot was intended to run
in the CloudShell VPC environment, which must be able to reach the RDS
security group on TCP port `5432`.

CloudShell VPC connectivity to RDS and outbound internet access are
separate concerns. A private environment can reach RDS while still being
unable to reach public package repositories such as PyPI.

## 6. Code walkthrough

The shared `chatbot.py` implementation follows the sections below.
Function names are described according to the implementation shared
during the project; compare them with the final file before treating
this as a line-by-line reference.

### 6.1 Imports

``` python
import os
import re
import boto3
import psycopg2
from psycopg2.extras import RealDictCursor
```

-   `os` reads environment variables.
-   `re` searches the question for known identifier patterns.
-   `boto3` creates AWS service clients.
-   `psycopg2` connects Python to PostgreSQL.
-   `RealDictCursor` returns rows in dictionary-like form, making column
    names available when preparing model context.

### 6.2 AWS session and Bedrock clients

The application creates a Boto3 session in `us-east-1`, then creates two
clients:

-   `bedrock-agent-runtime` --- retrieves relevant passages from the
    Knowledge Base.
-   `bedrock-runtime` --- invokes the foundation model through the
    Converse API.

These are separate responsibilities: the Knowledge Base retrieves
evidence; the model generates the answer.

The AWS identity used by CloudShell needs permission to retrieve from
the Knowledge Base and invoke the selected model. The Knowledge Base
service role and the CloudShell execution identity are not automatically
the same role.

### 6.3 `get_db_connection()`

This function reads RDS connection settings from environment variables
and opens a PostgreSQL connection.

The connection uses the RDS endpoint, port `5432`, database
`abc_insurance`, configured username and password, `sslmode="require"`
to require encryption, and a connection timeout.

The function returns a live database connection. Cursors and connections
should be closed after use, including when a query raises an exception.

### 6.4 `retrieve_rds_data(question)`

This function retrieves structured insurance records.

The shared implementation looks for recognizable identifiers in the
question, including:

-   Claim IDs such as `CLM-9001`.
-   Policy IDs such as `ABC-AUTO-SAMPLE-1001`.
-   The sample customer names Jordan Lee and Taylor Morgan.

When it finds a supported identifier, it runs a parameterized SQL query
joining:

-   `customers`
-   `policies`
-   `claims`
-   `payments`

Parameterized SQL uses placeholders and passes values separately. This
is safer than inserting user-provided text directly into a SQL
statement.

The returned rows can contain facts such as customer name, policy ID,
claim amount, claim status and payment totals. The application prepares
these results as context for answer generation.

**Implementation limitation:** The initial code uses pattern matching
for a small set of known identifiers. It is not a general
natural-language-to-SQL system. Questions without a recognized claim ID,
policy ID or supported customer name may return no RDS results. Broader
question support requires deliberate query-routing logic and carefully
designed, read-only SQL.

### 6.5 `retrieve_policy_documents(question)`

This function calls the Bedrock Agent Runtime `retrieve()` API with:

-   Knowledge Base ID `E1RNVKEBQF`.
-   The user's question as the retrieval query.
-   A vector-search configuration requesting up to five results.

The Knowledge Base searches the indexed policy PDF and returns relevant
text passages with source metadata, such as the S3 document location
when available.

This function finds evidence; it does not itself generate the final
natural-language answer.

### 6.6 `generate_answer(question, rds_context, policy_context)`

This function calls Amazon Nova Lite through the Bedrock Runtime
Converse API.

It supplies the original question, structured facts retrieved from RDS,
policy passages retrieved from the Knowledge Base, and instructions
describing how to use the sources.

The prompt establishes source boundaries:

-   Use RDS for customer, claim, payment and stored policy-record facts.
-   Use the policy document for coverage wording, deductibles and
    exclusions.
-   Do not invent policy terms when the document does not support them.
-   Do not confuse a database deductible field with a coverage-specific
    deductible in policy wording.
-   Distinguish a payment that has been made from a claim that has
    merely been approved.
-   State when the available evidence is insufficient.

Nova Lite generates the answer from the supplied context. The model is
not the system of record; the database and policy document remain the
evidence sources.

### 6.7 Main conversation loop

The main loop:

1.  Displays a prompt and reads a question from the user.
2.  Checks for an exit command.
3.  Calls `retrieve_rds_data()` for structured facts.
4.  Calls `retrieve_policy_documents()` for policy passages.
5.  Passes both results to `generate_answer()`.
6.  Prints the answer.
7.  Prints source references when available.
8.  Repeats for the next question.

This makes the application interactive in the terminal.

## 7. End-to-end examples

### Example A --- Structured claim question

**User:** "What is the status of claim CLM-9001?"

1.  The question contains `CLM-9001`.
2.  The application recognizes the claim identifier.
3.  Python queries PostgreSQL.
4.  PostgreSQL returns the matching claim and related customer, policy
    and payment facts.
5.  The application supplies those facts to Nova Lite.
6.  Nova Lite writes an answer based on the retrieved record.

The claim status comes from RDS, not from the PDF or the model's general
knowledge.

### Example B --- Policy wording question

**User:** "What is the collision coverage deductible under policy
ABC-AUTO-SAMPLE-1001?"

1.  The application sends the question to the Knowledge Base.
2.  The Knowledge Base performs semantic retrieval against the indexed
    policy PDF.
3.  It returns relevant policy text.
4.  The application supplies the passage to Nova Lite.
5.  Nova Lite answers using that passage and the application prints the
    source reference.

The deductible must be supported by the retrieved policy wording. Do not
infer coverage terms for a different policy merely because it is in the
same database.

### Example C --- Hybrid question

**User:** "Who owns claim CLM-9001 and what is the collision
deductible?"

1.  RDS retrieval finds the claim and customer.
2.  Knowledge Base retrieval searches for the collision deductible in
    the policy document.
3.  Both evidence sets are passed to Nova Lite.
4.  The answer combines customer/claim facts with policy wording.
5.  If either source lacks sufficient evidence, the answer should say so
    rather than guess.

## 8. Sample data and previous validation

The PostgreSQL database contains four sample tables:

  Table         Purpose
  ------------- -----------------------
  `customers`   Customer records
  `policies`    Policy records
  `claims`      Claim records
  `payments`    Claim payment records

The sample dataset included:

-   Customer C1001: Jordan Lee.
-   Customer C1002: Taylor Morgan.
-   Claim CLM-9001: collision claim, amount `$6,000`, status
    `Under Review`, with a recorded payment of `$2,000`.
-   Claim CLM-9002: hail/comprehensive claim, amount `$2,400`, status
    `Approved`, with a recorded payment of `$1,900`.

These are illustrative lab records, not real customer data. A payment
total is not necessarily the insurer's final liability or the remaining
amount payable.

Previous Knowledge Base retrieval tests confirmed:

-   Collision coverage deductible for policy `ABC-AUTO-SAMPLE-1001`:
    `$1,000` per covered occurrence.
-   Comprehensive coverage deductible for that policy: `$500` per
    covered occurrence.

Do not apply these terms to policy `ABC-AUTO-SAMPLE-1002` unless its own
policy wording is retrieved and supports the answer.

## 9. Running and testing the application

Before running the chatbot:

1.  Activate the intended Python virtual environment.
2.  Confirm `boto3` and `psycopg2-binary` are installed in that same
    environment.
3.  Set the environment variables listed in Section 5.
4.  Confirm CloudShell can connect to the private RDS instance.
5.  Confirm the CloudShell AWS identity can retrieve from the Knowledge
    Base and invoke Nova Lite.
6.  Run the application from the directory containing `chatbot.py`.

Suggested tests:

  -----------------------------------------------------------------------
  Test                                Expected source
  ----------------------------------- -----------------------------------
  Status of `CLM-9001`                RDS

  Customer for `CLM-9002`             RDS

  Collision deductible for policy     Bedrock Knowledge Base
  `ABC-AUTO-SAMPLE-1001`              

  Comprehensive deductible for policy Bedrock Knowledge Base
  `ABC-AUTO-SAMPLE-1001`              

  Customer/claim details plus policy  Both
  deductible                          

  Terms of a policy not represented   Should state insufficient policy
  in the PDF                          evidence
  -----------------------------------------------------------------------

A basic database connectivity test is:

``` sql
SELECT current_database(), current_user;
```

A successful result confirms database connectivity and authentication,
but does not validate every application SQL statement.

## 10. Validation items before production use

The shared Python implementation was a development draft and was not
confirmed as fully executed end-to-end. Before calling it
production-ready, validate:

1.  **Database schema:** Check actual column names in all four tables.
    In particular, verify payment status, policy status/type, policy
    dates and deductible columns. The initial SQL draft must match the
    actual schema exactly.
2.  **SQL behavior:** Test each supported question and confirm joins do
    not duplicate payment totals.
3.  **Question routing:** Expand beyond the small set of hard-coded
    identifier patterns if broader natural-language questions are
    required.
4.  **Empty retrieval:** Handle no matching RDS rows or no Knowledge
    Base passages explicitly.
5.  **Model response parsing:** Handle all returned text content blocks
    safely.
6.  **Permissions:** Grant only required RDS network access and Bedrock
    actions to the CloudShell execution identity.
7.  **Secrets:** Do not store passwords, access keys or endpoints in
    source control. Prefer a managed secret store for persistent use.
8.  **Read-only access:** Use a database role with read-only permissions
    for chatbot queries.
9.  **Prompt injection:** Treat retrieved document text as untrusted
    data, not instructions that can override application rules.
10. **Grounding and citations:** Verify answers cite the correct
    retrieved source and do not claim unsupported policy coverage.
11. **Conversation state:** The initial hybrid draft does not provide
    durable multi-turn conversational memory. Add session handling
    deliberately if follow-up questions need prior context.
12. **Logging:** Avoid logging passwords, personal data or unnecessary
    full claim/customer records.

## 11. Security and cost notes

-   RDS remains private; do not make it publicly accessible just to run
    the chatbot.
-   CloudShell VPC networking to RDS does not automatically provide
    outbound internet access.
-   A NAT Gateway is not required for the application to reach RDS. It
    is one option for outbound internet access from a private subnet,
    but it has ongoing charges.
-   Bedrock Knowledge Base retrieval and model invocation can incur
    usage charges.
-   RDS storage and backup charges can continue even when an RDS
    instance is stopped. Review billing impact before leaving resources
    provisioned.
-   Retain final documentation and project evidence before deleting AWS
    resources.

## 12. Final learning outcome

This module demonstrates the core pattern behind a hybrid insurance RAG
application:

-   SQL retrieves exact, structured business facts.
-   Semantic retrieval finds relevant passages in unstructured policy
    documents.
-   Python coordinates both retrieval paths.
-   A foundation model synthesizes an answer from retrieved evidence.
-   Source-aware prompting and validation help reduce unsupported
    answers.

The key design principle is to use the right retrieval method for each
data type, then give the language model the evidence it needs to answer
rather than asking it to guess.

------------------------------------------------------------------------

**Documentation note:** This guide explains the Python implementation
shared during the project. The final `chatbot.py` file and live
PostgreSQL schema should be checked together before treating this as an
exact line-by-line record of the final implementation.
