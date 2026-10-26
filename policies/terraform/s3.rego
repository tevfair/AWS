package terraform.security

# Require all four S3 Block Public Access settings.
deny contains message if {
	resource := resources_by_type("aws_s3_bucket_public_access_block")[_]
	config := after(resource)
	setting := [
		"block_public_acls",
		"block_public_policy",
		"ignore_public_acls",
		"restrict_public_buckets",
	][_]
	object.get(config, setting, false) != true
	message := sprintf("%s must set %s to true", [resource.address, setting])
}

ownership_is_enforced(resource) if {
	rule := object.get(after(resource), "rule", [])[_]
	rule.object_ownership == "BucketOwnerEnforced"
}

# Require bucket-owner-enforced ownership so ACLs cannot grant access.
deny contains message if {
	resource := resources_by_type("aws_s3_bucket_ownership_controls")[_]
	not ownership_is_enforced(resource)
	message := sprintf("%s must use BucketOwnerEnforced object ownership", [resource.address])
}

uses_sse_s3(resource) if {
	rule := object.get(after(resource), "rule", [])[_]
	encryption := object.get(rule, "apply_server_side_encryption_by_default", [])[_]
	encryption.sse_algorithm == "AES256"
}

# Require free S3-managed AES-256 encryption and reject KMS-based defaults.
deny contains message if {
	resource := resources_by_type("aws_s3_bucket_server_side_encryption_configuration")[_]
	not uses_sse_s3(resource)
	message := sprintf("%s must use SSE-S3 AES256 encryption", [resource.address])
}

# Require an explicit HTTPS-only bucket policy.
deny contains message if {
	resource := resources_by_type("aws_s3_bucket_policy")[_]
	document := policy_document(resource)
	not has_https_deny(document, "s3:*")
	message := sprintf("%s must deny S3 requests when aws:SecureTransport is false", [resource.address])
}

# Ensure the project includes each required S3 security resource.
deny contains "A managed aws_s3_bucket_public_access_block resource is required" if {
	count(resources_by_type("aws_s3_bucket_public_access_block")) == 0
}

deny contains "A managed aws_s3_bucket_ownership_controls resource is required" if {
	count(resources_by_type("aws_s3_bucket_ownership_controls")) == 0
}

deny contains "A managed aws_s3_bucket_server_side_encryption_configuration resource is required" if {
	count(resources_by_type("aws_s3_bucket_server_side_encryption_configuration")) == 0
}

deny contains "A managed aws_s3_bucket_policy resource enforcing HTTPS is required" if {
	count(resources_by_type("aws_s3_bucket_policy")) == 0
}
