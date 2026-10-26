variable "aws_region" {
  description = "AWS region in which Amazon Bedrock will be used."
  type        = string
  default     = "us-east-1"
}

variable "model_id" {
  description = "ID of an active Amazon Bedrock foundation model."
  type        = string
  default     = "amazon.nova-lite-v1:0"
}

variable "embedding_model_id" {
  description = "ID of the embedding model used by the knowledge base."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "embedding_dimensions" {
  description = "Vector dimensions emitted by the embedding model."
  type        = number
  default     = 1024
}

variable "name_prefix" {
  description = "Prefix used for knowledge base resources."
  type        = string
  default     = "custom-bedrock-kb"
}

variable "force_destroy" {
  description = "Allow Terraform to delete non-empty test storage during destroy. Disable for production."
  type        = bool
  default     = true
}

variable "create_invocation_role" {
  description = "Whether to create an IAM role allowed to invoke the selected model."
  type        = bool
  default     = true
}

variable "invocation_role_name" {
  description = "Name of the IAM role used to invoke the selected Bedrock model."
  type        = string
  default     = "bedrock-model-invocation-role"
}

variable "trusted_principal_arns" {
  description = "AWS principal ARNs allowed to assume the invocation role. The current account root is used when this is empty."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to resources managed by this configuration."
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Project     = "Bedrock"
    Environment = "dev"
  }
}
