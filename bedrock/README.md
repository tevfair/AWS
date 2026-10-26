# Amazon Bedrock Knowledge Base

Terraform configuration for a low-idle-cost retrieval-augmented generation (RAG) environment on AWS.

## Architecture

![Amazon Bedrock Knowledge Base architecture](./bedrock-knowledge-base-architecture.png)

Documents are uploaded to a private S3 bucket and ingested by Amazon Bedrock. Titan Text Embeddings V2 converts document chunks into vectors stored in S3 Vectors. At query time, the Knowledge Base retrieves relevant chunks and Nova Lite generates a grounded answer.

### Components and Terraform resources

#### Amazon Bedrock Knowledge Base

```hcl main.tf
resource "aws_bedrockagent_knowledge_base" "this" {
  name     = "${local.name_prefix}-kb"
  role_arn = aws_iam_role.knowledge_base.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = data.aws_bedrock_foundation_model.embedding.model_arn
    }
  }

  storage_configuration {
    type = "S3_VECTORS"
    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.knowledge_base.index_arn
    }
  }
}
```

#### S3 document data source

```hcl main.tf
resource "aws_bedrockagent_data_source" "documents" {
  knowledge_base_id    = aws_bedrockagent_knowledge_base.this.id
  name                 = "${local.name_prefix}-documents"
  data_deletion_policy = "DELETE"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.documents.arn
    }
  }
}
```

#### Private document bucket

```hcl main.tf
resource "aws_s3_bucket" "documents" {
  bucket        = "${local.name_prefix}-documents"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
```

`aws_s3_bucket_policy.documents` denies non-HTTPS requests. Versioning is managed by `aws_s3_bucket_versioning.documents`.

#### S3 Vectors storage

```hcl main.tf
resource "aws_s3vectors_vector_bucket" "knowledge_base" {
  vector_bucket_name = "${local.name_prefix}-vectors"
  force_destroy      = var.force_destroy

  encryption_configuration {
    sse_type = "AES256"
  }
}

resource "aws_s3vectors_index" "knowledge_base" {
  vector_bucket_name = aws_s3vectors_vector_bucket.knowledge_base.vector_bucket_name
  index_name         = "knowledge-base-index"
  data_type          = "float32"
  dimension          = var.embedding_dimensions
  distance_metric    = "cosine"
}
```

`aws_s3vectors_vector_bucket_policy.knowledge_base` denies non-HTTPS requests to vector storage.

#### Bedrock models

```hcl main.tf
data "aws_bedrock_foundation_model" "selected" {
  model_id = var.model_id
}

data "aws_bedrock_foundation_model" "embedding" {
  model_id = var.embedding_model_id
}
```

The defaults select Nova Lite for on-demand answer generation and Titan Text Embeddings V2 for document embeddings.

#### IAM roles and policies

```hcl main.tf
resource "aws_iam_role" "knowledge_base" {
  name               = "${local.name_prefix}-kb-role"
  assume_role_policy = data.aws_iam_policy_document.knowledge_base_assume_role.json
}

resource "aws_iam_role_policy" "knowledge_base" {
  name   = "bedrock-knowledge-base"
  role   = aws_iam_role.knowledge_base.id
  policy = data.aws_iam_policy_document.knowledge_base.json
}
```

The project also optionally creates `aws_iam_role.bedrock_invocation` and `aws_iam_role_policy.bedrock_invoke` for Nova Lite invocation. See [`main.tf`](./main.tf) for the complete least-privilege policy statements.

## No-additional-charge security controls

The configuration uses native controls that do not have a separate security-service charge:

- S3-managed `AES256` encryption for documents and vectors; no customer-managed KMS key
- S3 Block Public Access
- Bucket-owner-enforced object ownership, which disables ACL-based access
- Bucket policies that deny requests without TLS/HTTPS
- Least-privilege IAM permissions scoped to the selected models, document bucket, and vector index
- Bedrock service-role trust restricted by source account and Knowledge Base ARN

Normal S3 storage/request, S3 Vectors, embedding, and model-inference charges still apply. S3 versioning can increase storage charges when files are replaced or deleted because older versions remain stored. This project does not enable separately billed services such as GuardDuty, Macie, Security Hub, customer-managed KMS keys, or CloudTrail data events.

## Prerequisites

- Terraform 1.5 or newer
- AWS CLI v2
- An AWS identity with permission to manage the configured resources
- Access to the selected Bedrock models in `us-east-1`

## Authentication

```shell Terminal
aws sso login --profile Terraformmm-local
```

## Deploy

From this directory:

```shell Terminal
AWS_PROFILE=Terraformmm-local terraform init
AWS_PROFILE=Terraformmm-local terraform validate
AWS_PROFILE=Terraformmm-local terraform plan
AWS_PROFILE=Terraformmm-local terraform apply
```

After deployment, upload documents to the generated S3 document bucket and sync the Knowledge Base data source.

## Configuration

Copy `terraform.tfvars.example` to `terraform.tfvars` to change the region, models, trusted principals, or tags. Do not store AWS credentials in Terraform files.

The defaults use:

- Generation model: `amazon.nova-lite-v1:0`
- Embedding model: `amazon.titan-embed-text-v2:0`
- Region: `us-east-1`

## Destroy

```shell Terminal
AWS_PROFILE=Terraformmm-local terraform destroy
```

> The test configuration enables `force_destroy`, so destroying the environment also deletes documents and vectors stored in its managed buckets.
