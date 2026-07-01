# core-cloud-appstream2-image-builder-terraform

Terraform module for **CC-PAM AppStream 2.0** multi-tenant image automation — provisioning IAM, KMS, shared lock/artifact storage, Step Functions orchestrators, and per-tenant SSM documents.

**Current module version:** `2.3.0`  
**Live account:** `979566283533` (CCPamAppStreamImageBuilderLive) · **Region:** `eu-west-2`

Terragrunt stacks, ASL definitions, poller scripts, and CI workflows live in the companion repo: [core-cloud-appstream2-image-builder-terragrunt](https://github.com/Home-Office-Digital/core-cloud-appstream2-image-builder-terragrunt).

---

## What this module provisions

| Resource | Scope | Notes |
|----------|-------|-------|
| **Step Functions** | Per tenant | Build orchestrator (`appstream-build-orchestrator.asl.json` v1.7.6) |
| **Lock doctor SFN** | Platform stack only | Scheduled stale `BUILDING` lock recovery |
| **DynamoDB lock table** | Shared (platform creates) | `AppStreamBuildLocks` — one row per tenant |
| **S3 artifact bucket** | Shared (platform creates) | KMS-encrypted; versioned script artifacts + job state |
| **KMS key** | Shared (platform creates) | Encrypts lock table, SFN logs, S3 |
| **IAM roles** | Per tenant | Step Function role, Image Builder instance role |
| **SSM document** | Per tenant | Slim automation doc (legacy path; poller is primary) |
| **SSM parameter** | Per tenant | Banner message for session start |
| **CloudWatch log groups** | Per tenant + lock doctor | SFN execution logging |

Image builds are driven by an **on-instance ENI poller** (not SSM push). The Step Function writes worker context to S3; the poller pulls scripts, runs `init.sh`, and uploads `result.json`. See the terragrunt repo README for the full end-to-end flow.

---

## Repository layout

```
modules/appstream2-automation-infra/
├── main.tf              IAM, KMS, DynamoDB, S3, SFN, lock doctor, SSM
├── variables.tf         Single-tenant module interface
├── outputs.tf
└── tests/
    ├── main.tftest.hcl  Terraform native tests
    ├── fixtures/
    └── stepfunctions/   ASL validation scripts
```

---

## Usage

Each tenant gets **one module invocation** (one Terragrunt stack). Platform owns shared resources; other tenants reference them.

### Platform stack (creates shared resources + lock doctor)

```hcl
module "appstream2_automation" {
  source = "git::https://github.com/Home-Office-Digital/core-cloud-appstream2-image-builder-terraform.git//modules/appstream2-automation-infra?ref=2.3.0"

  aws_region   = "eu-west-2"
  account_id   = "979566283533"
  project_name = "cc-pam"
  tenant_key   = "platform"

  base_image_name  = "CCPAM-AppStream-RockyLinux8-Base-2026-06-v3"
  banner_message   = "..."
  live_account_id  = "579976740007"
  prelive_account_id = "800511960003"

  vpc_id            = "vpc-..."
  subnet_id         = "subnet-..."
  security_group_id = "sg-..."

  ssm_document_source    = "${path.module}/ssm/automation.json"
  stepfn_definition_file = "${path.module}/../shared/stepfunctions/appstream-build-orchestrator.asl.json"

  create_shared_resources         = true
  build_lock_table_name           = "AppStreamBuildLocks"
  artifact_bucket_name            = "appstream-artifacts-979566283533-eu-west-2"
  lock_doctor_definition_file     = "${path.module}/../shared/stepfunctions/appstream-lock-doctor.asl.json"
  lock_doctor_schedule_expression = "rate(1 hour)"
}
```

### Tenant stack (e.g. APC — reads shared resources)

```hcl
module "appstream2_automation" {
  source = "git::https://github.com/Home-Office-Digital/core-cloud-appstream2-image-builder-terraform.git//modules/appstream2-automation-infra?ref=2.3.0"

  aws_region   = "eu-west-2"
  account_id   = "979566283533"
  project_name = "cc-pam-apc"
  tenant_key   = "apc"

  # ... same networking / banner / share targets ...

  ssm_document_source    = "${path.module}/ssm/automation.json"
  stepfn_definition_file = "${path.module}/../shared/stepfunctions/appstream-build-orchestrator.asl.json"

  create_shared_resources      = false
  build_lock_table_name        = "AppStreamBuildLocks"
  artifact_bucket_name         = "appstream-artifacts-979566283533-eu-west-2"
  build_lock_table_kms_key_arn = "<platform stack KMS key ARN>"
}
```

**Bootstrap order:** apply platform first, then tenant stacks.

---

## Key inputs

| Name | Description | Required |
|------|-------------|:--------:|
| `tenant_key` | Tenant identifier (`platform`, `apc`, …) | yes |
| `project_name` | Prefix for IAM/SFN naming (`cc-pam`, `cc-pam-apc`) | yes |
| `account_id` | AWS account ID | yes |
| `aws_region` | AWS region | yes |
| `ssm_document_source` | Path to tenant SSM JSON (single string, not a map) | yes |
| `stepfn_definition_file` | Path to orchestrator ASL JSON | yes |
| `create_shared_resources` | Create lock table + artifact bucket + KMS | yes |
| `artifact_bucket_name` | Shared artifact bucket name | yes |
| `build_lock_table_name` | Shared DynamoDB lock table name | yes |
| `build_lock_table_kms_key_arn` | KMS key ARN (required when `create_shared_resources = false`) | conditional |
| `lock_doctor_definition_file` | Lock doctor ASL (platform stack only) | no |
| `lock_doctor_schedule_expression` | EventBridge schedule (default `rate(5 minutes)`) | no |
| `base_image_name` | AppStream base image for Image Builder | yes |
| `banner_message` | Session banner text (stored in SSM Parameter Store) | yes |
| `live_account_id` / `prelive_account_id` | Downstream share targets | yes |
| `vpc_id` / `subnet_id` / `security_group_id` | Image Builder networking | yes |

Full variable definitions and validations: [`modules/appstream2-automation-infra/variables.tf`](modules/appstream2-automation-infra/variables.tf).

---

## Outputs

| Name | Description |
|------|-------------|
| `state_machine_arn` | Build orchestrator Step Function ARN |
| `ssm_document_name` | Tenant SSM document name |
| `appstream_instance_role_arn` | Image Builder instance role ARN |
| `build_lock_table_name` | DynamoDB lock table name |
| `artifact_bucket_name` | S3 artifact bucket name |
| `build_lock_table_kms_key_arn` | KMS key ARN (platform stack only) |
| `lock_doctor_state_machine_arn` | Lock doctor SFN ARN (platform stack only) |
| `base_image_name` | Echo of input |

---

## IAM highlights

**Step Function role** can:

- Manage AppStream Image Builders and images (describe, create builder, start/stop, share)
- Read/write DynamoDB lock rows and S3 job artifacts
- Call `states:DescribeExecution` for stale-lock takeover
- Pass the AppStream instance role to Image Builder APIs

**Instance role** can:

- Read versioned scripts from the artifact bucket (with explicit deny on `*/latest/*` direct reads)
- Write `state.json`, `result.json`, `result.log` under `jobs/`
- Invoke `AppStreamImageAssistant` (via on-instance CLI)

**Lock doctor role** can:

- Scan DynamoDB for `BUILDING` locks
- Describe Step Function executions
- Conditionally update lock rows to `FAILED`

Account-baseline OIDC roles for CI (`cc-appstream2-terragrunt-*`, `cc-appstream2-artifact-publish-role`) are **not** created by this module.

---

## Testing

```bash
cd modules/appstream2-automation-infra
terraform test

# Step Functions ASL validation (DescribeExecution catch patterns, etc.)
./tests/stepfunctions/run_tests.sh
```

Tests cover shared-resource gating, IAM deny rules, input validation, lock doctor deployment, and ASL fixture checks.

---

## Versioning

This repo uses semver tags consumed by Terragrunt via `APPSTREAM_MODULE_REF` (default **`2.3.0`** in `ccpamappstream/globals.hcl`).

Breaking changes from v1.x:

- `ssm_document_sources` (map) → `ssm_document_source` (single string) — one stack per tenant
- Shared lock table + artifact bucket owned by platform stack (`create_shared_resources`)
- Lock doctor SFN + EventBridge schedule (platform stack)
- KMS permissions required on tenant stacks for shared encrypted resources

---

## Related repositories

| Repo | Role |
|------|------|
| [core-cloud-appstream2-image-builder-terragrunt](https://github.com/Home-Office-Digital/core-cloud-appstream2-image-builder-terragrunt) | Terragrunt stacks, ASL, poller, CI workflows |
| core-cloud-account-baseline | OIDC IAM roles (#757–760) |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT License](LICENSE.md)
