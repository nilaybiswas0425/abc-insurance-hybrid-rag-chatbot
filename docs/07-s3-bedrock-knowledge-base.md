# Module 03 --- Amazon S3, S3 Vectors and Amazon Bedrock Knowledge Base

## 1. Objective

Build the document-retrieval side of the ABC Insurance Hybrid RAG
application. Insurance policy documents are stored in Amazon S3,
processed by an Amazon Bedrock Knowledge Base, converted into
embeddings, and indexed in Amazon S3 Vectors for semantic retrieval.

This module handles unstructured policy information. Customer, policy,
claim and payment records will be handled separately in Amazon RDS for
PostgreSQL.

## 2. Architecture

``` text
Insurance policy PDF
        |
        v
Amazon S3 general purpose bucket
        |
        v
Amazon Bedrock Knowledge Base
  - Default parser
  - Default chunking
  - Amazon Titan Text Embeddings V2
        |
        v
Amazon S3 Vectors
        |
        v
Semantic retrieval and answer generation
```

The later Python application will combine retrieved policy information
with structured operational data queried from PostgreSQL.

## 3. Amazon S3 document storage

  -----------------------------------------------------------------------------------
  Setting                             Configuration
  ----------------------------------- -----------------------------------------------
  Region                              `us-east-1`

  General purpose bucket              `abc-insurance-ai-documents-<AWS_ACCOUNT_ID>`

  Uploaded document                   `ABC_Insurance_Auto_Policy_Sample.pdf`

  Storage class                       S3 Standard

  Bucket versioning                   Disabled

  Default encryption                  SSE-S3

  Block Public Access                 Enabled
  -----------------------------------------------------------------------------------

The bucket name uses `<AWS_ACCOUNT_ID>` as a placeholder so the account
ID is not published. The uploaded PDF is synthetic training data, not a
real insurance contract. It describes sample policy
`ABC-AUTO-SAMPLE-1001`, including collision and comprehensive
deductibles, coverage information, exclusions and claim procedures.

## 4. Amazon S3 Vectors

### Vector bucket

  ---------------------------------------------------------------------------------------------
  Setting                             Configuration
  ----------------------------------- ---------------------------------------------------------
  Vector bucket                       `s3-vector-abc-insurance-ai-documents-<AWS_ACCOUNT_ID>`

  Region                              `us-east-1`

  Enhanced index mode                 Enabled

  Encryption                          SSE-S3
  ---------------------------------------------------------------------------------------------

### Vector index

  -----------------------------------------------------------------------
  Setting                             Configuration
  ----------------------------------- -----------------------------------
  Index name                          `abc-insurance-policy-index`

  Dimensions                          `1024`

  Distance metric                     Cosine

  Enhanced index mode                 Enabled

  Encryption                          SSE-S3

  Non-filterable metadata keys        `AMAZON_BEDROCK_TEXT`,
                                      `AMAZON_BEDROCK_METADATA`
  -----------------------------------------------------------------------

The index dimension must match the embedding model output dimension. The
selected Titan Text Embeddings V2 configuration produces
1024-dimensional vectors. Cosine distance was selected for semantic
similarity retrieval.

### Non-filterable metadata configuration

The first Knowledge Base synchronization failed with this error:

`Filterable metadata must have at most 2048 bytes`

The vector index was recreated with these two non-filterable metadata
keys:

-   `AMAZON_BEDROCK_TEXT`
-   `AMAZON_BEDROCK_METADATA`

These fields remain stored; marking them non-filterable prevents them
from being treated as filterable metadata. The subsequent
synchronization completed successfully.

## 5. Amazon Bedrock Knowledge Base

  Setting                Configuration
  ---------------------- ------------------------------------------
  Knowledge Base name    `abc-insurance-knowledge-base`
  Knowledge Base type    Self-managed / unstructured vector store
  Data source type       Amazon S3
  Data source name       `abc-insurance-policy-s3-data-source`
  Service role           `abc-insurance-knowledge-base_kb`
  Embedding model        Amazon Titan Text Embeddings V2
  Embedding dimensions   `1024`
  Vector store           Amazon S3 Vectors
  Vector index           `abc-insurance-policy-index`
  Parsing strategy       Amazon Bedrock default parser
  Chunking strategy      Default chunking
  Data deletion policy   `DELETE`

The service role was created by the Bedrock setup workflow to allow the
Knowledge Base to access the required resources.

### Parsing and chunking decisions

**Default parser:** Selected for the text-based sample PDF. It extracts
text for indexing; a specialized parser is not needed for this initial
document.

**Default chunking:** Selected for the initial implementation. Bedrock
automatically splits extracted text into chunks of approximately 300
tokens by default. A document already around that size or smaller is not
split further.

Alternative chunking approaches---fixed-size, hierarchical and
semantic---can be evaluated later. The selected chunking strategy cannot
be changed in place after the data source is created.

## 6. Ingestion and validation

The S3 data source synchronization history showed two attempts:

  --------------------------------------------------------------------------
  Attempt      Status                Scanned           Failed Outcome
  ------------ ------------ ---------------- ---------------- --------------
  Initial      Failed                      1                1 Filterable
  attempt                                                     metadata
                                                              exceeded the
                                                              S3 Vectors
                                                              limit

  Corrected    Complete                    1                0 Document
  attempt                                                     indexed
                                                              successfully
  --------------------------------------------------------------------------

The document list showed one document with status `INDEXED`.

### Retrieval tests

The Knowledge Base test interface used **Standard retrieval with answer
generation**, with **Amazon Nova Lite 1.0 (on-demand)** selected for
response generation.

  -----------------------------------------------------------------------
  Test question           Returned answer         Result
  ----------------------- ----------------------- -----------------------
  What is the collision   `$1,000` per covered    Passed
  coverage deductible     occurrence              
  under policy                                    
  ABC-AUTO-SAMPLE-1001?                           

  What is the             `$500` per covered      Passed
  comprehensive coverage  occurrence              
  deductible?                                     
  -----------------------------------------------------------------------

Both answers included a source citation marker. These tests confirm
retrieval of the expected deductible information from the indexed
policy.


## 7. Screenshots

Store module screenshots in `screenshots/03-s3-bedrock/`.

  ---------------------------------------------------------------------------------------
  Suggested filename                                  Evidence
  --------------------------------------------------- -----------------------------------
  `01-s3-policy-document-uploaded.png`                Sample PDF uploaded to S3

  `03-s3-vector-bucket-created.png`                   S3 Vector bucket

  `04-s3-vector-index-created.png`                    Vector index configuration

  `05-Knowledge-Base-(KB)-with-vector-store.png`      Knowledge Base overview\

  `06-Knowledge-Base-(KB)-with-vector-store.png`      Knowledge Base overview

  `07-Knowledge-Base-(KB)-with-vector-store.png`      Knowledge Base overview

  `08-bedrock-policy-document-sync-success.png`       Successful synchronization and
                                                      indexed document

  `09-01-bedrock-knowledge-base-retrieval-tests.png`     Retrieval test answers
  ---------------------------------------------------------------------------------------

Use the actual final screenshots and filenames in the repository. The
initial failed sync may be retained as troubleshooting evidence, but it
is not required for the main portfolio walkthrough.

## 9. Module outcome

The document-retrieval pipeline is operational:

1.  The sample policy PDF is stored in Amazon S3.
2.  Bedrock parses and chunks the document.
3.  Titan Text Embeddings V2 generates 1024-dimensional embeddings.
4.  Amazon S3 Vectors stores the indexed vectors and associated
    metadata.
5.  The Knowledge Base retrieves the correct collision and comprehensive
    deductible information in the validation tests.
