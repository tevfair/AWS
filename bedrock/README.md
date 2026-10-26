# Amazon Bedrock Terraform

This configuration validates an existing AWS-managed Bedrock foundation model and optionally creates a least-privilege IAM role that can invoke it.

Amazon Bedrock is a managed regional service. The foundation model is supplied by AWS rather than created by Terraform.

## Prerequisites

- Terraform 1.5 or newer
- An AWS identity with permission to read Bedrock models and manage the configured IAM role
- Access to the selected model in the configured region

The defaults use `amazon.nova-lite-v1:0` in `us-east-1`.

## Authentication

This project uses the standard AWS credential chain. On this Mac, use the configured SSO profile:

    aws sso login --profile Terraformmm-local

## Preview only

    AWS_PROFILE=Terraformmm-local terraform init
    AWS_PROFILE=Terraformmm-local terraform validate
    AWS_PROFILE=Terraformmm-local terraform plan

These commands do not deploy resources. Only `terraform apply` changes AWS resources.

## Configuration

Copy `terraform.tfvars.example` to `terraform.tfvars` if you need to change the model, region, trusted principals, or tags. Do not place AWS credentials in Terraform files.
