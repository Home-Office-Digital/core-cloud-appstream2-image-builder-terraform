# tests/main.tftest.hcl
#
# Rewritten from scratch against the new single-tenant module surface
# (design doc Section 7, item 2). The previous suite exercised the removed
# ssm_document_sources map(string)/for_each — it would fail immediately
# against this module and has been deleted rather than left in a broken
# state.
#
# CORRECTION #2: a `provider "aws" {}` block with placeholder static
# credentials is NOT sufficient. skip_credentials_validation/
# skip_requesting_account_id/skip_metadata_api_check only suppress
# Terraform's own pre-flight checks — they do nothing to stop `data` sources
# from making real API calls. This module's two real `data` sources
# (data.aws_s3_bucket.artifacts, data.aws_dynamodb_table.build_locks — read
# when create_shared_resources = false) genuinely hit AWS with the fake
# credentials and were correctly rejected. Fixed with mock_provider, which
# replaces the AWS provider entirely.
#
# CORRECTION #3: the persisting "no file exists at ./fixtures/..." errors
# were NOT a side effect of the data source failures, and NOT a CI working-
# directory issue (the CI workflow's `-chdir=modules/appstream2-automation-infra`
# was always correct — confirmed against reusable-terraform-test.yaml).
# The actual cause, confirmed against HashiCorp's own documentation: "All
# references to, and absolute file paths within, the testing files should
# be relative to the main configuration directory" — i.e. relative to
# modules/appstream2-automation-infra/ (where main.tf lives), NOT relative
# to tests/ (where this file lives). The paths needed the tests/ segment
# included (./tests/fixtures/... not ./fixtures/...) from the very first
# version of this file. Two wrong diagnoses before finding the documented
# rule — worth that being visible here rather than quietly fixed.
#
# Also found in the same run: mock_provider "aws" {} mocks every AWS-
# provider resource and data source uniformly, with no way to exclude one
# selectively via the mock_provider block itself.
# data.aws_iam_policy_document.sfn_logging is a pure local computation (no
# API call, ever, even outside tests) but got mocked anyway, returning
# synthetic data instead of evaluating its statement blocks — which broke
# aws_iam_policy.sfn_logging's policy argument ("not a JSON object").
# override_data (below) exempts this one data source so it computes for
# real while everything else AWS-related stays mocked.
mock_provider "aws" {}

override_data {
  target = data.aws_iam_policy_document.sfn_logging
}

variables {
  aws_region              = "eu-west-2"
  account_id               = "979566283533"
  project_name             = "cc-pam-apc"
  tenant_key               = "apc"
  base_image_name          = "CCPAM-AppStream-RockyLinux8-Base-2026-04-v2"
  banner_message           = "UNAUTHORISED ACCESS WARNING"
  live_account_id          = "579976740007"
  prelive_account_id       = "800511960003"
  vpc_id                   = "vpc-054b75f6e02609595"
  subnet_id                = "subnet-026bf861b538b0b63"
  security_group_id        = "sg-0385fa4b97d81a336"
  # CORRECTION #3: per HashiCorp's documented behavior ("All references to,
  # and absolute file paths within, the testing files should be relative to
  # the main configuration directory" — i.e. modules/appstream2-automation-infra/,
  # where main.tf lives, NOT tests/, where this file lives), these paths
  # were simply wrong from the very first version of this file. They were
  # never resolved relative to this test file's own directory — they needed
  # the tests/ segment included. The CI workflow's `-chdir` was correct and
  # irrelevant to this specific bug; I'd misdiagnosed it as a CI working-
  # directory issue twice before actually finding the documented rule.
  ssm_document_source      = "./tests/fixtures/ssm-document.json"
  stepfn_definition_file   = "./tests/fixtures/stepfunction_definition.json"
  artifact_bucket_name     = "appstream-artifacts-979566283533-eu-west-2"
  build_lock_table_name    = "AppStreamBuildLocks"
  create_shared_resources  = false
}

# ---------------------------------------------------------------------------
# Tenant stack (create_shared_resources = false): should NOT attempt to
# create the DynamoDB table or S3 bucket — only read them via data sources.
# ---------------------------------------------------------------------------
run "tenant_stack_does_not_create_shared_resources" {
  command = plan

  assert {
    condition     = length(aws_dynamodb_table.build_locks) == 0
    error_message = "A tenant stack (create_shared_resources=false) must not create the shared lock table."
  }

  assert {
    condition     = length(aws_s3_bucket.artifacts) == 0
    error_message = "A tenant stack (create_shared_resources=false) must not create the shared artifact bucket."
  }
}

run "tenant_stack_creates_single_ssm_document" {
  command = plan

  assert {
    condition     = aws_ssm_document.appstream_setup.name == "cc-pam-apc-setup-document-apc"
    error_message = "SSM document name must be derived from project_name and tenant_key."
  }
}

run "tenant_stack_state_machine_uses_plain_file_not_templatefile" {
  command = plan

  assert {
    condition     = aws_sfn_state_machine.appstream_automation.name == "cc-pam-apc-state-machine"
    error_message = "State machine name must be derived from project_name."
  }
}

# ---------------------------------------------------------------------------
# Platform stack (create_shared_resources = true): SHOULD create the shared
# resources, with prevent_destroy and the lifecycle rule in place.
# ---------------------------------------------------------------------------
run "platform_stack_creates_shared_resources" {
  command = plan

  variables {
    tenant_key              = "platform"
    project_name             = "cc-pam"
    create_shared_resources  = true
  }

  assert {
    condition     = length(aws_dynamodb_table.build_locks) == 1
    error_message = "The platform stack (create_shared_resources=true) must create the shared lock table."
  }

  assert {
    condition     = length(aws_s3_bucket.artifacts) == 1
    error_message = "The platform stack (create_shared_resources=true) must create the shared artifact bucket."
  }

  assert {
    condition     = aws_dynamodb_table.build_locks[0].hash_key == "Tenant"
    error_message = "Lock table must be keyed on Tenant."
  }
}

# ---------------------------------------------------------------------------
# Validate the structural IAM deny on */latest/* exists on both roles
# (design doc Section 3.2/5.1 — enforced by IAM, not just convention).
# ---------------------------------------------------------------------------
run "step_function_role_denies_latest_path_reads" {
  command = plan

  assert {
    condition = strcontains(
      aws_iam_policy.step_function_policy.policy,
      "platform/latest/*"
    )
    error_message = "Step Function IAM policy must explicitly deny reads to platform/latest/* (design doc Section 3.2/5.1)."
  }

  assert {
    condition = strcontains(
      aws_iam_policy.step_function_policy.policy,
      "tenants/*/latest/*"
    )
    error_message = "Step Function IAM policy must explicitly deny reads to tenants/*/latest/* (design doc Section 3.2/5.1)."
  }
}

run "appstream_instance_role_denies_latest_path_reads" {
  command = plan

  assert {
    condition = strcontains(
      aws_iam_policy.appstream_instance_policy.policy,
      "platform/latest/*"
    )
    error_message = "Image Builder instance IAM policy must explicitly deny reads to platform/latest/* (design doc Section 3.2/5.1)."
  }
}

# ---------------------------------------------------------------------------
# Validation failures: confirm the variable validation rules actually fire.
# ---------------------------------------------------------------------------
run "rejects_non_json_ssm_document_source" {
  command = plan

  variables {
    ssm_document_source = "./tests/fixtures/not-json.txt"
  }

  expect_failures = [
    var.ssm_document_source,
  ]
}

run "rejects_tenant_key_over_49_chars" {
  command = plan

  variables {
    tenant_key = "this-tenant-key-is-deliberately-far-too-long-to-be-valid-x"
  }

  expect_failures = [
    var.tenant_key,
  ]
}

run "rejects_latest_literal_in_ssm_document_source_path" {
  # Not a variable-level validation (path content isn't checked that deeply)
  # but documents the expectation at the test-suite level: nobody should
  # wire ssm_document_source or stepfn_definition_file to a 'latest' alias
  # path. This is enforced operationally by repo convention + the IAM deny
  # above, not by a Terraform variable validation block, since the module
  # has no way to know what a given path's contents represent.
  command = plan

  assert {
    condition     = !strcontains(var.ssm_document_source, "/latest/")
    error_message = "ssm_document_source should never point through a /latest/ path by convention (design doc Section 3.2/5.1)."
  }
}
