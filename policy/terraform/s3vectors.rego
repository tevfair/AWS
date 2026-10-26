package terraform.security

uses_vector_aes256(resource) if {
	configuration := object.get(after(resource), "encryption_configuration", [])[_]
	configuration.sse_type == "AES256"
}

# Require free S3-managed AES-256 encryption for vector storage.
deny contains message if {
	resource := resources_by_type("aws_s3vectors_vector_bucket")[_]
	not uses_vector_aes256(resource)
	message := sprintf("%s must use AES256 vector-bucket encryption", [resource.address])
}

# Require an explicit HTTPS-only vector-bucket policy.
deny contains message if {
	resource := resources_by_type("aws_s3vectors_vector_bucket_policy")[_]
	document := policy_document(resource)
	not has_https_deny(document, "s3vectors:*")
	message := sprintf("%s must deny S3 Vectors requests when aws:SecureTransport is false", [resource.address])
}

deny contains "A managed aws_s3vectors_vector_bucket resource is required" if {
	count(resources_by_type("aws_s3vectors_vector_bucket")) == 0
}

deny contains "A managed aws_s3vectors_vector_bucket_policy resource enforcing HTTPS is required" if {
	count(resources_by_type("aws_s3vectors_vector_bucket_policy")) == 0
}
