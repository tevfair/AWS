# Terraform Security Policies

OPA/Rego policies for Terraform plan JSON in this AWS repository.

The policies verify the no-additional-charge controls used by the Bedrock project:

- S3 Block Public Access
- `BucketOwnerEnforced` object ownership
- Free S3-managed `AES256` encryption
- HTTPS-only S3 bucket policy
- Free `AES256` encryption for S3 Vectors
- HTTPS-only S3 Vectors bucket policy
- Bedrock service-role trust scoped by source account and Knowledge Base ARN
- No wildcard resources in project IAM role policies

## Run unit tests

From the repository root:

```shell Terminal
./policies/test.sh
```

The script uses an installed `opa` binary when available. Otherwise, it downloads a temporary OPA binary for the current macOS or Linux architecture and removes it when the test exits.

## Evaluate a Terraform plan

Create Terraform plan JSON:

```shell Terminal
cd bedrock
AWS_PROFILE=Terraformmm-local terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json
```

Evaluate it from the repository root:

```shell Terminal
opa eval \
  --data policies/terraform \
  --input bedrock/tfplan.json \
  'data.terraform.security.deny'
```

A secure plan returns an empty set. Any returned string describes a failed security requirement.

The plan and JSON output are local artifacts and should not be committed.
