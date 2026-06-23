# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region format, for example eu-west-2."
  }
}

variable "base_image_name" {
  description = "Base AppStream image name"
  type        = string

  validation {
    condition     = length(trimspace(var.base_image_name)) > 0
    error_message = "base_image_name must not be empty."
  }
}

variable "live_account_id" {
  description = "CCPamAppStreamLive AWS Account ID to share the image (live)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.live_account_id))
    error_message = "live_account_id must be a 12-digit AWS account ID."
  }
}

variable "prelive_account_id" {
  description = "CCPamAppStreamPrelive AWS Account ID to share the image (prelive)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.prelive_account_id))
    error_message = "prelive_account_id must be a 12-digit AWS account ID."
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "appstream-automation"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-63 characters, use lowercase letters, numbers, and hyphens, and start/end with a letter or number."
  }
}

variable "tenant_key" {
  description = "Single tenant this stack belongs to (for example 'platform', 'apc', 'xyz'). Drives the DynamoDB lock Tenant key, the SSM document name, and the Image Builder name."
  type        = string

  validation {
    condition     = length(trimspace(var.tenant_key)) > 0 && can(regex("^[A-Za-z0-9_.-]+$", var.tenant_key))
    error_message = "tenant_key must be non-empty and contain only letters, numbers, underscore, period, or hyphen."
  }

  validation {
    condition     = length(var.tenant_key) <= 49
    error_message = "tenant_key must be 49 characters or fewer so the generated SSM document name stays within AWS's 128-character limit for all valid project_name values."
  }
}

variable "ssm_document_source" {
  description = "Path to this tenant's SSM document JSON (for example tenants/apc/ssm/automation.json). One stack manages exactly one tenant's document"
  type        = string

  validation {
    condition     = length(trimspace(var.ssm_document_source)) > 0 && endswith(var.ssm_document_source, ".json")
    error_message = "ssm_document_source must be a non-empty path to a .json file."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC where AppStream Image Builder will launch"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID, for example vpc-0123456789abcdef0."
  }
}

variable "subnet_id" {
  type = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]{8,17}$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID, for example subnet-0123456789abcdef0."
  }
}

variable "security_group_id" {
  type = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]{8,17}$", var.security_group_id))
    error_message = "security_group_id must be a valid security group ID, for example sg-0123456789abcdef0."
  }
}

variable "stepfn_definition_file" {
  type        = string
  description = "Path to the Step Functions ASL definition JSON (appstream-build-orchestrator.asl.json)."

  validation {
    condition     = length(trimspace(var.stepfn_definition_file)) > 0 && can(regex("\\.json$", var.stepfn_definition_file))
    error_message = "stepfn_definition_file must be a non-empty path to a .json file."
  }
}

variable "account_id" {
  description = "AWS Account ID where the AppStream Image Builder and Step Functions will be created"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "banner_message" {
  type        = string
  description = "Legal notice displayed to users at AppStream session start"

  validation {
    condition     = length(trimspace(var.banner_message)) > 0
    error_message = "banner_message must not be empty or whitespace only."
  }
}

variable "artifact_bucket_name" {
  description = "Name of the existing S3 bucket holding versioned platform/tenant script artifacts. Created once, shared across all tenant stacks — not managed by this module."
  type        = string

  validation {
    condition     = length(trimspace(var.artifact_bucket_name)) > 0
    error_message = "artifact_bucket_name must not be empty."
  }
}

variable "build_lock_table_name" {
  description = "Name of the shared DynamoDB build-lock table. Created once, shared across all tenant stacks — not managed by this module."
  type        = string
  default     = "AppStreamBuildLocks"

  validation {
    condition     = length(trimspace(var.build_lock_table_name)) > 0
    error_message = "build_lock_table_name must not be empty."
  }
}

variable "build_lock_table_kms_key_arn" {
  description = "ARN of the KMS key that encrypts the shared build-lock table, required on every stack where create_shared_resources is false (every tenant except the owner, conventionally 'platform'). Needed because the owning stack's own aws_kms_key.sfn_logs is NOT necessarily the same key that encrypts the lock table for non-owning stacks — this was previously read from the data source's server_side_encryption block directly, but that field is a legacy SDKv2 schema Block, which Terraform's test-framework override_data cannot populate, so it's passed explicitly instead. Ignored entirely when create_shared_resources is true, since that stack reads its own aws_kms_key.sfn_logs.arn directly."
  type        = string
  default     = ""

  validation {
    condition     = var.create_shared_resources || length(trimspace(var.build_lock_table_kms_key_arn)) > 0
    error_message = "build_lock_table_kms_key_arn must be set on every stack where create_shared_resources is false."
  }
}

variable "create_shared_resources" {
  description = "Whether this stack creates the shared, account-wide resources (DynamoDB lock table, S3 artifact bucket). Set true on exactly one tenant stack — conventionally 'platform' — and false everywhere else, so the shared resources aren't duplicated or fought over across tenant stacks."
  type        = bool
  default     = false
}
