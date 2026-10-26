package terraform.security

trust_is_scoped(resource) if {
	raw := object.get(after(resource), "assume_role_policy", "")
	document := json.unmarshal(raw)
	statement := statements(document)[_]
	has_condition(statement, "StringEquals", "aws:SourceAccount")
	has_condition(statement, "ArnLike", "aws:SourceArn")
}

# Require the Bedrock service-role trust policy to mitigate confused-deputy risk.
deny contains message if {
	resource := resources_by_type("aws_iam_role")[_]
	endswith(resource.address, "aws_iam_role.knowledge_base")
	not trust_is_scoped(resource)
	message := sprintf("%s trust policy must restrict aws:SourceAccount and aws:SourceArn", [resource.address])
}

# Reject wildcard resources in inline policies used by this project.
deny contains message if {
	resource := resources_by_type("aws_iam_role_policy")[_]
	document := policy_document(resource)
	statement := statements(document)[_]
	wildcard_resource(statement)
	message := sprintf("%s must not grant permissions to Resource '*'", [resource.address])
}

has_knowledge_base_role if {
	resource := resources_by_type("aws_iam_role")[_]
	endswith(resource.address, "aws_iam_role.knowledge_base")
}

has_knowledge_base_policy if {
	resource := resources_by_type("aws_iam_role_policy")[_]
	endswith(resource.address, "aws_iam_role_policy.knowledge_base")
}

# Require the Knowledge Base role and its scoped inline policy.
deny contains "The Bedrock Knowledge Base IAM role is required" if {
	not has_knowledge_base_role
}

deny contains "The Bedrock Knowledge Base inline IAM policy is required" if {
	not has_knowledge_base_policy
}
