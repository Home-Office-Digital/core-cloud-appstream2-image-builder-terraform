provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

run "plan_succeeds_with_required_inputs" {
  command = plan

  variables {
    project_name            = "test-appstream"
    aws_region              = "eu-west-2"
    account_id              = "111111111111"
    base_image_name         = "AppStream-RockyLinux8-2026-05-01"
    live_account_id         = "222222222222"
    prelive_account_id      = "333333333333"
    ssm_document_sources    = {
      platform = "tests/fixtures/ssm-document.json"
      apc      = "tests/fixtures/ssm-document.json"
    }
    stepfn_definition_file  = "tests/fixtures/stepfunction_definition.json"
    vpc_id                  = "vpc-0123456789abcdef0"
    subnet_id               = "subnet-0123456789abcdef0"
    security_group_id       = "sg-0123456789abcdef0"
    banner_message          = "Authorised use only"
  }

  assert {
    condition     = output.base_image_name == "AppStream-RockyLinux8-2026-05-01"
    error_message = "base_image_name output should match the test input"
  }

  assert {
    condition     = output.ssm_document_names["platform"] == "test-appstream-setup-document-platform"
    error_message = "Platform SSM document name should include the project name and tenant"
  }

  assert {
    condition     = output.ssm_document_names["apc"] == "test-appstream-setup-document-apc"
    error_message = "APC SSM document name should include the project name and tenant"
  }

  assert {
    condition     = aws_ssm_document.appstream_setup["platform"].document_type == "Command"
    error_message = "Platform SSM document type should be Command"
  }

  assert {
    condition     = aws_ssm_document.appstream_setup["apc"].document_format == "JSON"
    error_message = "APC SSM document format should be JSON"
  }

  assert {
    condition     = aws_sfn_state_machine.appstream_automation.name == "test-appstream-state-machine"
    error_message = "State machine name should include the project name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.sfn_logs.retention_in_days == 365
    error_message = "State machine log group retention should be 365 days"
  }

  assert {
    condition     = aws_ssm_parameter.banner_message.type == "SecureString"
    error_message = "Banner message parameter should be a SecureString"
  }

  assert {
    condition     = aws_ssm_parameter.banner_message.name == "/test-appstream/appstream/banner-message"
    error_message = "Banner message parameter name should include the project name"
  }

  assert {
    condition     = aws_kms_alias.sfn_logs.name == "alias/test-appstream-sfn-logs"
    error_message = "KMS alias should include the project name"
  }

  assert {
    condition     = aws_iam_role.step_function_role.name == "test-appstream-step-function-role"
    error_message = "Step Functions IAM role name should include the project name"
  }
}

run "plan_uses_default_project_name" {
  command = plan

  variables {
    aws_region              = "eu-west-2"
    account_id              = "111111111111"
    base_image_name         = "AppStream-RockyLinux8-2026-05-01"
    live_account_id         = "222222222222"
    prelive_account_id      = "333333333333"
    ssm_document_sources    = {
      platform = "tests/fixtures/ssm-document.json"
    }
    stepfn_definition_file  = "tests/fixtures/stepfunction_definition.json"
    vpc_id                  = "vpc-0123456789abcdef0"
    subnet_id               = "subnet-0123456789abcdef0"
    security_group_id       = "sg-0123456789abcdef0"
    banner_message          = "Authorised use only"
  }

  assert {
    condition     = output.ssm_document_names["platform"] == "appstream-automation-setup-document-platform"
    error_message = "Default project_name should be used in tenant SSM document names when not supplied"
  }

  assert {
    condition     = aws_sfn_state_machine.appstream_automation.name == "appstream-automation-state-machine"
    error_message = "State machine name should use default project_name"
  }
}

run "plan_fails_with_invalid_live_account_id" {
  command = plan

  variables {
    project_name            = "test-appstream"
    aws_region              = "eu-west-2"
    account_id              = "111111111111"
    base_image_name         = "AppStream-RockyLinux8-2026-05-01"
    live_account_id         = "invalid-account-id"
    prelive_account_id      = "333333333333"
    ssm_document_sources    = {
      platform = "tests/fixtures/ssm-document.json"
    }
    stepfn_definition_file  = "tests/fixtures/stepfunction_definition.json"
    vpc_id                  = "vpc-0123456789abcdef0"
    subnet_id               = "subnet-0123456789abcdef0"
    security_group_id       = "sg-0123456789abcdef0"
    banner_message          = "Authorised use only"
  }

  expect_failures = [
    var.live_account_id,
  ]
}

run "plan_fails_with_invalid_vpc_id" {
  command = plan

  variables {
    project_name            = "test-appstream"
    aws_region              = "eu-west-2"
    account_id              = "111111111111"
    base_image_name         = "AppStream-RockyLinux8-2026-05-01"
    live_account_id         = "222222222222"
    prelive_account_id      = "333333333333"
    ssm_document_sources    = {
      platform = "tests/fixtures/ssm-document.json"
    }
    stepfn_definition_file  = "tests/fixtures/stepfunction_definition.json"
    vpc_id                  = "not-a-vpc-id"
    subnet_id               = "subnet-0123456789abcdef0"
    security_group_id       = "sg-0123456789abcdef0"
    banner_message          = "Authorised use only"
  }

  expect_failures = [
    var.vpc_id,
  ]
}

run "plan_fails_with_empty_banner_message" {
  command = plan

  variables {
    project_name            = "test-appstream"
    aws_region              = "eu-west-2"
    account_id              = "111111111111"
    base_image_name         = "AppStream-RockyLinux8-2026-05-01"
    live_account_id         = "222222222222"
    prelive_account_id      = "333333333333"
    ssm_document_sources    = {
      platform = "tests/fixtures/ssm-document.json"
    }
    stepfn_definition_file  = "tests/fixtures/stepfunction_definition.json"
    vpc_id                  = "vpc-0123456789abcdef0"
    subnet_id               = "subnet-0123456789abcdef0"
    security_group_id       = "sg-0123456789abcdef0"
    banner_message          = "   "
  }

  expect_failures = [
    var.banner_message,
  ]
}

run "plan_fails_with_invalid_security_group_id" {
  command = plan

  variables {
    project_name           = "test-appstream"
    aws_region             = "eu-west-2"
    account_id             = "111111111111"
    base_image_name        = "AppStream-RockyLinux8-2026-05-01"
    live_account_id        = "222222222222"
    prelive_account_id     = "333333333333"
    ssm_document_sources   = {
      platform = "tests/fixtures/ssm-document.json"
    }
    stepfn_definition_file = "tests/fixtures/stepfunction_definition.json"
    vpc_id                 = "vpc-0123456789abcdef0"
    subnet_id              = "subnet-0123456789abcdef0"
    security_group_id      = "not-a-security-group-id"
    banner_message         = "Authorised use only"
  }

  expect_failures = [
    var.security_group_id,
  ]
}