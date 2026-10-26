data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_bedrock_foundation_model" "selected" {
  model_id = var.model_id
}

data "aws_bedrock_foundation_model" "embedding" {
  model_id = var.embedding_model_id
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.name_prefix}-${random_id.suffix.hex}"
  trusted_principal_arns = length(var.trusted_principal_arns) > 0 ? var.trusted_principal_arns : [
    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
  ]
}

data "aws_iam_policy_document" "bedrock_assume_role" {
  count = var.create_invocation_role ? 1 : 0

  statement {
    sid     = "AllowTrustedPrincipals"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = local.trusted_principal_arns
    }
  }
}

resource "aws_iam_role" "bedrock_invocation" {
  count = var.create_invocation_role ? 1 : 0

  name               = var.invocation_role_name
  assume_role_policy = data.aws_iam_policy_document.bedrock_assume_role[0].json
}

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

resource "aws_iam_role_policy" "bedrock_invoke" {
  count = var.create_invocation_role ? 1 : 0

  name   = "bedrock-model-invocation"
  role   = aws_iam_role.bedrock_invocation[0].id
  policy = data.aws_iam_policy_document.bedrock_invoke[0].json
}

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

data "aws_iam_policy_document" "knowledge_base_assume_role" {
  statement {
    sid     = "BedrockKnowledgeBaseAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "knowledge_base" {
  name               = "${local.name_prefix}-kb-role"
  assume_role_policy = data.aws_iam_policy_document.knowledge_base_assume_role.json
}

data "aws_iam_policy_document" "knowledge_base" {
  statement {
    sid       = "InvokeEmbeddingModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = [data.aws_bedrock_foundation_model.embedding.model_arn]
  }

  statement {
    sid    = "ReadSourceDocuments"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
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

resource "aws_iam_role_policy" "knowledge_base" {
  name   = "bedrock-knowledge-base"
  role   = aws_iam_role.knowledge_base.id
  policy = data.aws_iam_policy_document.knowledge_base.json
}

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
