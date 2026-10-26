package terraform.security_test

import data.terraform.security
import data.testdata as plans

test_compliant_plan_has_no_denials if {
	denials := security.deny with input as plans.compliant_plan
	count(denials) == 0
}

test_insecure_plan_is_denied if {
	denials := security.deny with input as plans.insecure_plan
	count(denials) == 11
}

test_public_access_settings_are_checked if {
	denials := security.deny with input as plans.insecure_plan
	"aws_s3_bucket_public_access_block.documents must set block_public_acls to true" in denials
	"aws_s3_bucket_public_access_block.documents must set block_public_policy to true" in denials
	"aws_s3_bucket_public_access_block.documents must set ignore_public_acls to true" in denials
	"aws_s3_bucket_public_access_block.documents must set restrict_public_buckets to true" in denials
}

test_s3_ownership_and_encryption_are_checked if {
	denials := security.deny with input as plans.insecure_plan
	"aws_s3_bucket_ownership_controls.documents must use BucketOwnerEnforced object ownership" in denials
	"aws_s3_bucket_server_side_encryption_configuration.documents must use SSE-S3 AES256 encryption" in denials
}

test_transport_security_is_checked if {
	denials := security.deny with input as plans.insecure_plan
	"aws_s3_bucket_policy.documents must deny S3 requests when aws:SecureTransport is false" in denials
	"aws_s3vectors_vector_bucket_policy.knowledge_base must deny S3 Vectors requests when aws:SecureTransport is false" in denials
}

test_vector_encryption_is_checked if {
	denials := security.deny with input as plans.insecure_plan
	"aws_s3vectors_vector_bucket.knowledge_base must use AES256 vector-bucket encryption" in denials
}

test_bedrock_iam_is_checked if {
	denials := security.deny with input as plans.insecure_plan
	"aws_iam_role.knowledge_base trust policy must restrict aws:SourceAccount and aws:SourceArn" in denials
	"aws_iam_role_policy.knowledge_base must not grant permissions to Resource '*'" in denials
}
