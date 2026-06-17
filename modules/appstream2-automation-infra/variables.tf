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

variable "ssm_document_sources" {
  description = "Map of tenant names to SSM document JSON paths (for example platform/apc)."
  type        = map(string)

  validation {
    condition = length(var.ssm_document_sources) > 0 && alltrue([
      for doc_path in values(var.ssm_document_sources) : (
        length(trimspace(doc_path)) > 0 && endswith(doc_path, ".json")
      )
    ])
    error_message = "ssm_document_sources must contain at least one tenant mapped to a non-empty .json file path."
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
  description = "Path to the Step Functions definition JSON"

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

