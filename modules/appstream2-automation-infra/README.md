# appstream2-automation-infra

Terraform module provisioning AWS infrastructure for **CC-PAM AppStream 2.0** multi-tenant image builds.

One module call = **one tenant stack** (platform, apc, …). Platform conventionally sets `create_shared_resources = true` to own the shared DynamoDB lock table, S3 artifact bucket, KMS key, and lock doctor.

---

## Resources created

### Per tenant (every stack)

- `aws_sfn_state_machine.appstream_automation` — build orchestrator (ASL passed via `stepfn_definition_file`)
- `aws_iam_role.step_function_role` + policy (AppStream, DynamoDB, S3, DescribeExecution)
- `aws_iam_role.appstream_instance_role` + policy + instance profile
- `aws_ssm_document.appstream_setup` — tenant SSM automation document
- `aws_ssm_parameter.banner_message`
- `aws_cloudwatch_log_group.sfn_logs` + KMS-encrypted SFN logging policy

### Platform stack only (`create_shared_resources = true`)

- `aws_dynamodb_table.build_locks` — `AppStreamBuildLocks`
- `aws_s3_bucket.artifacts` — versioned, KMS-encrypted, access-logged
- `aws_kms_key.sfn_logs` — encrypts lock table, bucket, SFN logs
- `aws_sfn_state_machine.lock_doctor` — scheduled stale lock recovery (when `lock_doctor_definition_file` set)
- `aws_cloudwatch_event_rule.lock_doctor` — EventBridge schedule

### Tenant stacks (`create_shared_resources = false`)

- `data.aws_dynamodb_table.build_locks` — read existing lock table
- `data.aws_s3_bucket.artifacts` — read existing bucket
- Requires `build_lock_table_kms_key_arn` from platform outputs for IAM/KMS grants

---

## Example

```hcl
module "appstream2_automation" {
  source = "git::https://github.com/Home-Office-Digital/core-cloud-appstream2-image-builder-terraform.git//modules/appstream2-automation-infra?ref=2.3.0"

  aws_region   = "eu-west-2"
  account_id   = "979566283533"
  project_name = "cc-pam"
  tenant_key   = "platform"

  base_image_name    = "CCPAM-AppStream-RockyLinux8-Base-2026-06-v3"
  banner_message     = "..."
  live_account_id    = "579976740007"
  prelive_account_id = "800511960003"

  vpc_id            = "vpc-..."
  subnet_id         = "subnet-..."
  security_group_id = "sg-..."

  ssm_document_source    = "./ssm/automation.json"
  stepfn_definition_file = "./appstream-build-orchestrator.asl.json"

  create_shared_resources         = true
  build_lock_table_name           = "AppStreamBuildLocks"
  artifact_bucket_name            = "appstream-artifacts-979566283533-eu-west-2"
  lock_doctor_definition_file     = "./appstream-lock-doctor.asl.json"
  lock_doctor_schedule_expression = "rate(1 hour)"
}
```

---

## Inputs

See [`variables.tf`](variables.tf) for full definitions and validation rules.

| Input | Purpose |
|-------|---------|
| `tenant_key` | Lock row key, SSM doc suffix, builder naming |
| `create_shared_resources` | Platform=true creates shared infra; tenants=false read via data sources |
| `stepfn_definition_file` | Path to orchestrator ASL (v1.7.6 in terragrunt repo) |
| `lock_doctor_definition_file` | Lock doctor ASL (platform only) |
| `artifact_bucket_name` | Shared S3 bucket for scripts + job state |
| `build_lock_table_kms_key_arn` | Required on tenant stacks for KMS decrypt on shared resources |

---

## Outputs

| Output | Description |
|--------|-------------|
| `state_machine_arn` | Build orchestrator ARN |
| `lock_doctor_state_machine_arn` | Lock doctor ARN (platform only) |
| `build_lock_table_kms_key_arn` | Shared KMS key (platform only) |
| `artifact_bucket_name` | Artifact bucket name |
| `appstream_instance_role_arn` | Image Builder instance role |

See [`outputs.tf`](outputs.tf).

---

## Design notes

- **No `appstream:CreateImage` on SFN role** — image creation runs on the builder via `AppStreamImageAssistant` CLI (`create_image.sh`), not a Step Functions SDK call.
- **S3 deny on `latest/`** — instance role cannot read unpinned script prefixes; CI resolves SHA before `StartExecution`.
- **Single-tenant API** — replaces earlier `for_each` over `ssm_document_sources`; each tenant is an independent Terragrunt apply.
- **Lock doctor** — complements orchestrator stale-lock takeover; scans hourly for orphaned `BUILDING` rows.

---

## Tests

```bash
terraform test
./tests/stepfunctions/run_tests.sh
```
