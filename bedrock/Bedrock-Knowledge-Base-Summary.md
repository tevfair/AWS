# AWS Bedrock Knowledge Base

## Overview

This design creates a custom document question-answering system using retrieval-augmented generation (RAG). It was deployed as a test and then fully destroyed. The Terraform files remain available for reuse.

## Architecture

![AWS Bedrock Knowledge Base architecture](bedrock-knowledge-base-architecture.svg)

### How it works

1. Documents are uploaded to a private S3 bucket.
2. Bedrock splits them into manageable chunks.
3. Titan Text Embeddings converts each chunk into numbers representing its meaning.
4. S3 Vectors stores those embeddings for semantic search.
5. When someone asks a question, the Knowledge Base finds relevant passages.
6. Nova Lite uses those passages to write a grounded answer.

## Why use this approach?

A general AI model does not automatically know private or current documents. RAG gives it relevant information at question time without retraining the model.

Benefits:

- Answers questions using private documents.
- Reduces hallucinations by supplying relevant source material.
- Lets information be updated by replacing and re-ingesting documents.
- Uses semantic search, so wording does not need to match exactly.
- Avoids always-on OpenSearch compute by using S3 Vectors.
- Incurs most costs only when documents are processed or questions are asked.

## Resources and exact Terraform

The snippets below are the exact resource blocks used in the deployment.

### Unique naming

Generates a stable suffix for globally unique bucket names.

```hcl
resource "random_id" "suffix" {
  byte_length = 4
}
```

### Document storage

The source bucket is private, encrypted, versioned, and removable with its contents in this test environment.

```hcl
resource "aws_s3_bucket" "documents" {
  bucket        = "${local.name_prefix}-documents"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = "Enabled"
  }
}
```

### Vector storage and search

S3 Vectors stores 1,024-dimensional Titan embeddings and compares them with cosine similarity. It avoids always-on OpenSearch Serverless OCU costs.

```hcl
resource "aws_s3vectors_vector_bucket" "knowledge_base" {
  vector_bucket_name = "${local.name_prefix}-vectors"
  force_destroy      = var.force_destroy
}

resource "aws_s3vectors_index" "knowledge_base" {
  vector_bucket_name = aws_s3vectors_vector_bucket.knowledge_base.vector_bucket_name
  index_name         = "knowledge-base-index"
  data_type          = "float32"
  dimension          = var.embedding_dimensions
  distance_metric    = "cosine"

  metadata_configuration {
    non_filterable_metadata_keys = [
      "AMAZON_BEDROCK_TEXT",
      "AMAZON_BEDROCK_METADATA"
    ]
  }
}
```

### Knowledge Base permissions

This service role lets Bedrock invoke Titan, read the source bucket, and use only the configured vector index.

```hcl
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

The exact permissions supplied to that policy resource were:

```hcl
data "aws_iam_policy_document" "knowledge_base" {
  statement {
    sid       = "InvokeEmbeddingModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = [data.aws_bedrock_foundation_model.embedding.model_arn]
  }

  statement {
    sid     = "ReadSourceDocuments"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.documents.arn,
      "${aws_s3_bucket.documents.arn}/*"
    ]
  }

  statement {
    sid    = "UseS3VectorIndex"
    effect = "Allow"
    actions = [
      "s3vectors:GetIndex",
      "s3vectors:QueryVectors",
      "s3vectors:PutVectors",
      "s3vectors:GetVectors",
      "s3vectors:DeleteVectors"
    ]
    resources = [aws_s3vectors_index.knowledge_base.index_arn]
  }
}
```

### Bedrock Knowledge Base

Connects Titan Text Embeddings V2 to the S3 vector index and exposes managed retrieval.

```hcl
resource "aws_bedrockagent_knowledge_base" "this" {
  name     = "${local.name_prefix}-kb"
  role_arn = aws_iam_role.knowledge_base.arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = data.aws_bedrock_foundation_model.embedding.model_arn

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions          = var.embedding_dimensions
          embedding_data_type = "FLOAT32"
        }
      }
    }
  }

  storage_configuration {
    type = "S3_VECTORS"

    s3_vectors_configuration {
      index_arn = aws_s3vectors_index.knowledge_base.index_arn
    }
  }

  depends_on = [aws_iam_role_policy.knowledge_base]
}
```

### Bedrock data source and chunking

Points the Knowledge Base at the S3 documents and splits them into 300-token chunks with 20% overlap.

```hcl
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

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"

      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}
```

### Nova Lite invocation role

A separate role lets an authorized workload invoke Nova Lite without receiving ingestion or storage permissions.

```hcl
resource "aws_iam_role" "bedrock_invocation" {
  count = var.create_invocation_role ? 1 : 0

  name               = var.invocation_role_name
  assume_role_policy = data.aws_iam_policy_document.bedrock_assume_role[0].json
}

resource "aws_iam_role_policy" "bedrock_invoke" {
  count = var.create_invocation_role ? 1 : 0

  name   = "bedrock-model-invocation"
  role   = aws_iam_role.bedrock_invocation[0].id
  policy = data.aws_iam_policy_document.bedrock_invoke[0].json
}
```

Its policy is restricted to the configured generation model:

```hcl
data "aws_iam_policy_document" "bedrock_invoke" {
  count = var.create_invocation_role ? 1 : 0

  statement {
    sid    = "InvokeSelectedBedrockModel"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = [data.aws_bedrock_foundation_model.selected.model_arn]
  }
}
```

## Workflows

**When documents change:**

`Document → S3 → Bedrock ingestion → Titan embeddings → S3 Vectors`

**When a user asks a question:**

`Question → Knowledge Base → S3 Vectors → relevant passages → Nova Lite → answer`

## Cost behavior

There is no continuously running server in this design. An empty, unused deployment should cost almost nothing. Charges mainly occur when:

- Documents are stored and ingested
- Titan creates embeddings
- Vectors are stored or searched
- Nova Lite generates answers

This makes S3 Vectors a better small-workload option than OpenSearch Serverless, which can have meaningful always-on capacity costs.

## Deployment status

Terraform successfully created 13 resources in `us-east-1`, including the Knowledge Base, S3 storage, S3 vector index, and IAM roles. All 13 resources were later destroyed successfully, and the Terraform state is empty.

Terraform project:

`/Users/tevin/ResilioSync/Development (1)/AWS/bedrock`
