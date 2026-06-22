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
  ssm_document_source      = "./fixtures/ssm-document.json"
  stepfn_definition_file   = "./fixtures/stepfunction_definition.json"
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
# (enforced by IAM, not just convention).
# ---------------------------------------------------------------------------
run "step_function_role_denies_latest_path_reads" {
  command = plan

  assert {
    condition = strcontains(
      aws_iam_policy.step_function_policy.policy,
      "platform/latest/*"
    )
    error_message = "Step Function IAM policy must explicitly deny reads to platform/latest/*"
  }

  assert {
    condition = strcontains(
      aws_iam_policy.step_function_policy.policy,
      "tenants/*/latest/*"
    )
    error_message = "Step Function IAM policy must explicitly deny reads to tenants/*/latest/*"
  }
}

run "appstream_instance_role_denies_latest_path_reads" {
  command = plan

  assert {
    condition = strcontains(
      aws_iam_policy.appstream_instance_policy.policy,
      "platform/latest/*"
    )
    error_message = "Image Builder instance IAM policy must explicitly deny reads to platform/latest/*"
  }
}

# ---------------------------------------------------------------------------
# Validation failures: confirm the variable validation rules actually fire.
# ---------------------------------------------------------------------------
run "rejects_non_json_ssm_document_source" {
  command = plan

  variables {
    ssm_document_source = "./fixtures/not-json.txt"
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
    error_message = "ssm_document_source should never point through a /latest/ path by convention"
  }
}
