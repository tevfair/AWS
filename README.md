# AWS Terraform Projects

Terraform projects for deploying AWS infrastructure.

## Amazon Bedrock Knowledge Base

The [`bedrock`](./bedrock) project deploys a retrieval-augmented generation (RAG) environment using:

- Amazon Bedrock Knowledge Bases
- Amazon S3 for source documents
- Amazon S3 Vectors for vector storage
- Amazon Titan Text Embeddings V2
- Amazon Nova Lite for on-demand answer generation
- AWS IAM roles and policies

## Architecture

![Amazon Bedrock Knowledge Base architecture](./bedrock/bedrock-knowledge-base-architecture.png)

Documents are uploaded to a private S3 bucket and ingested by Bedrock. Titan Text Embeddings V2 converts document chunks into vectors stored in S3 Vectors. At query time, the Knowledge Base retrieves relevant chunks and Nova Lite generates a grounded answer.

## Deploy

From the repository root:

```shell
cd bedrock
AWS_PROFILE=Terraformmm-local terraform init
AWS_PROFILE=Terraformmm-local terraform plan
AWS_PROFILE=Terraformmm-local terraform apply
```

After deployment, upload documents to the generated S3 document bucket and sync the Knowledge Base data source.

## Destroy

```shell
cd bedrock
AWS_PROFILE=Terraformmm-local terraform destroy
```

> The test configuration enables `force_destroy`, so destroying the environment also deletes documents and vectors stored in its managed buckets.

See [`bedrock/README.md`](./bedrock/README.md) for project details and configuration options.
