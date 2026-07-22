# wheels-infra

OpenTofu for the Wheels Contract Intelligence platform. **Infra owns everything durable** —
DNS/domains, certs, Cognito, DynamoDB, S3, SQS/SNS/EventBridge, the Lambda functions +
`live` alias + provisioned concurrency, API Gateway + custom domain, ECR, CloudFront. The
app repos never run OpenTofu:

- **wheels-middleware** → build image → push to ECR → `update-function-code` + repoint `live` alias.
- **wheels-ui** → `vite build` → S3 sync → CloudFront invalidation.

Region: **ap-south-2** (core). **ap-south-1** for SES + Textract (not in ap-south-2). UI/API
certs: API cert in ap-south-2, CloudFront cert in us-east-1. DNS on **Cloudflare** (logiforma.dev).

## Deploy identity (OIDC)

A shared GitHub Actions OIDC role already exists in the account and is used by all projects,
so this repo does **not** create the OIDC provider or the deploy role — it references the ARN
via `deploy_role_arn`. Add the wheels repos to that role's trust policy `sub` list:

```
repo:bacon-delight/wheels-infra:*
repo:bacon-delight/wheels-middleware:*
repo:bacon-delight/wheels-ui:*
```

The role's permission policy must allow the deploy actions (broad create/update for infra;
ECR+Lambda for middleware; S3+CloudFront for ui).

## First-time setup

```bash
# 1. State backend (local state, run once)
cd bootstrap && tofu init && tofu apply      # prints the `tofu init` backend-config hint

# 2. Root config
cd .. && cp dev.tfvars.example dev.tfvars     # fill cloudflare_zone_id + deploy_role_arn
export TF_VAR_cloudflare_api_token=...         # CLOUDFLARE_API_TOKEN
tofu init -backend-config="bucket=..." -backend-config="key=wheels/dev/terraform.tfstate" \
          -backend-config="region=ap-south-2" -backend-config="dynamodb_table=wheels-tflock" \
          -backend-config="encrypt=true"
tofu apply -var-file=dev.tfvars
```

## Bootstrap ordering (container Lambda)

A container-image Lambda needs an image to exist before the function is created. Order:
`bootstrap` → apply **ecr** module only → wheels-middleware CI pushes the first image →
apply the rest (the `lambda` module seeds the function from that image, then middleware CI
owns code updates). The lambda module uses a placeholder-tolerant image reference so the
first apply is seamless.

## Module build order

`ecr` ✅ → `dynamodb` → `s3` → `cognito` → `sqs-pipeline` → `lambda` (api + workers, alias +
provisioned concurrency) → `apigw` (HTTP API + JWT authorizer + custom domain) →
`cloudfront` (UI, us-east-1 cert) → `cloudflare-dns` → `ses-notify` (identity refs in ap-south-1).

## Cost

< $2/mo fixed **except** API provisioned concurrency: **1024 MB × 1 warm ≈ $10.80/mo** (on
the `live` alias). Async workers stay on-demand ($0 idle). Bedrock extraction is usage-based
(~$0.13/doc on Sonnet 4.6).
