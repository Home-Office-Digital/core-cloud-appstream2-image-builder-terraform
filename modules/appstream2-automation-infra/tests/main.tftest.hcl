override_data {
  target = data.aws_dynamodb_table.build_locks[0]
  values = {
    arn = "arn:aws:dynamodb:eu-west-2:979566283533:table/AppStreamBuildLocks"
  }
}

override_data {
  target = data.aws_s3_bucket.artifacts[0]
  values = {
    arn = "arn:aws:s3:::appstream-artifacts-979566283533-eu-west-2"
  }
}

override_resource {
  target = aws_dynamodb_table.build_locks[0]
  values = {
    arn = "arn:aws:dynamodb:eu-west-2:979566283533:table/AppStreamBuildLocks"
  }
}

override_resource {
  target = aws_s3_bucket.artifacts[0]
  values = {
    arn = "arn:aws:s3:::appstream-artifacts-979566283533-eu-west-2"
  }
}

override_resource {
  target = aws_iam_role.appstream_instance_role
  values = {
    arn = "arn:aws:iam::979566283533:role/cc-pam-apc-appstream-instance-role"
  }
}

override_resource {
  target = aws_iam_role.step_function_role
  values = {
    arn = "arn:aws:iam::979566283533:role/cc-pam-apc-step-function-role"
  }
}

override_resource {
  target = aws_iam_policy.step_function_policy
  values = {
    arn = "arn:aws:iam::979566283533:policy/cc-pam-apc-step-function-policy"
  }
}

override_resource {
  target = aws_iam_policy.appstream_instance_policy
  values = {
    arn = "arn:aws:iam::979566283533:policy/cc-pam-apc-appstream-instance-policy"
  }
}

override_resource {
  target = aws_iam_policy.sfn_logging
  values = {
    arn = "arn:aws:iam::979566283533:policy/cc-pam-apc-sfn-logging-policy"
  }
}

override_resource {
  target = aws_kms_key.sfn_logs
  values = {
    arn    = "arn:aws:kms:eu-west-2:979566283533:key/00000000-0000-0000-0000-000000000000"
    key_id = "00000000-0000-0000-0000-000000000000"
  }
}

override_resource {
  target = aws_cloudwatch_log_group.sfn_logs
  values = {
    arn = "arn:aws:logs:eu-west-2:979566283533:log-group:/aws/states/cc-pam-apc-state-machine"
  }
}

mock_provider "aws" {}

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
  ssm_document_source      = "./tests/fixtures/ssm-document.json"
  stepfn_definition_file   = "./tests/fixtures/stepfunction_definition.json"
  artifact_bucket_name     = "appstream-artifacts-979566283533-eu-west-2"
  build_lock_table_name    = "AppStreamBuildLocks"
  create_shared_resources  = false
}

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

run "step_function_role_denies_latest_path_reads" {
  command = apply

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
  command = apply

  assert {
    condition = strcontains(
      aws_iam_policy.appstream_instance_policy.policy,
      "platform/latest/*"
    )
    error_message = "Image Builder instance IAM policy must explicitly deny reads to platform/latest/*"
  }
}

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
  command = plan

  assert {
    condition     = !strcontains(var.ssm_document_source, "/latest/")
    error_message = "ssm_document_source should never point through a /latest/ path by convention"
  }
}
