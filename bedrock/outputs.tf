output "aws_account_id" {
  description = "AWS account in which this configuration is evaluated."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region configured for Bedrock."
  value       = var.aws_region
}

output "foundation_model_id" {
  description = "Selected Bedrock foundation model ID."
  value       = data.aws_bedrock_foundation_model.selected.model_id
}

output "foundation_model_arn" {
  description = "ARN of the selected Bedrock foundation model."
  value       = data.aws_bedrock_foundation_model.selected.model_arn
}

output "invocation_role_arn" {
  description = "ARN of the IAM role allowed to invoke the model, if created."
  value       = try(aws_iam_role.bedrock_invocation[0].arn, null)
}

output "knowledge_base_id" {
  description = "ID of the Bedrock Knowledge Base."
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "data_source_id" {
  description = "ID of the S3 data source."
  value       = aws_bedrockagent_data_source.documents.data_source_id
}

output "document_bucket_name" {
  description = "S3 bucket where source documents should be uploaded."
  value       = aws_s3_bucket.documents.id
}

output "vector_bucket_name" {
  description = "S3 vector bucket backing the knowledge base."
  value       = aws_s3vectors_vector_bucket.knowledge_base.vector_bucket_name
}

output "vector_index_arn" {
  description = "ARN of the S3 vector index."
  value       = aws_s3vectors_index.knowledge_base.index_arn
}
