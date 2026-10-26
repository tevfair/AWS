package terraform.security

# This policy evaluates JSON produced by: terraform show -json <plan-file>
# It enforces security controls that do not require separately billed services.

managed_resources contains resource if {
	resource := input.resource_changes[_]
	resource.mode == "managed"
	resource.change.actions != ["delete"]
}

resources_by_type(resource_type) := {resource |
	resource := managed_resources[_]
	resource.type == resource_type
}

after(resource) := object.get(resource.change, "after", {})

policy_document(resource) := document if {
	raw := object.get(after(resource), "policy", "")
	is_string(raw)
	raw != ""
	document := json.unmarshal(raw)
}

statements(document) := {statement |
	raw := object.get(document, "Statement", [])
	is_array(raw)
	statement := raw[_]
} if {
	is_array(object.get(document, "Statement", []))
}

statements(document) := {object.get(document, "Statement", {})} if {
	is_object(object.get(document, "Statement", {}))
}

values(value) := {item | item := value[_]} if {
	is_array(value)
}

values(value) := {value} if {
	not is_array(value)
}

has_action(statement, expected) if {
	action := values(object.get(statement, "Action", []))[_]
	lower(action) == lower(expected)
}

has_resource(statement, expected) if {
	resource := values(object.get(statement, "Resource", []))[_]
	resource == expected
}

has_principal_wildcard(statement) if {
	principal := object.get(statement, "Principal", {})
	principal == "*"
}

has_principal_wildcard(statement) if {
	principal := object.get(statement, "Principal", {})
	is_object(principal)
	aws := object.get(principal, "AWS", [])
	values(aws)[_] == "*"
}

has_secure_transport_false(statement) if {
	condition := object.get(statement, "Condition", {})
	bool_conditions := object.get(condition, "Bool", {})
	value := object.get(bool_conditions, "aws:SecureTransport", null)
	lower(sprintf("%v", [value])) == "false"
}

has_https_deny(document, action) if {
	statement := statements(document)[_]
	lower(object.get(statement, "Effect", "")) == "deny"
	has_action(statement, action)
	has_principal_wildcard(statement)
	has_secure_transport_false(statement)
}

has_condition(statement, operator, key) if {
	condition := object.get(statement, "Condition", {})
	operator_values := object.get(condition, operator, {})
	object.get(operator_values, key, "") != ""
}

wildcard_resource(statement) if {
	resource := values(object.get(statement, "Resource", []))[_]
	resource == "*"
}
