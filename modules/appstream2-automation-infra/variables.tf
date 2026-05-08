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
    condition     = length(trimspace(var.project_name)) > 0
    error_message = "project_name must not be empty."
  }
}

variable "doc_source" {
  description = "Path to the SSM document JSON (AppStreamImageAssistant-automation.json)"
  type        = string

  validation {
    condition     = length(trimspace(var.doc_source)) > 0
    error_message = "doc_source must not be empty."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC where AppStream Image Builder will launch"

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a valid VPC ID, for example vpc-0123456789abcdef0."
  }
}
variable "subnet_id" {
  type = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a valid subnet ID, for example subnet-0123456789abcdef0."
  }
}
variable "security_group_id" {
  type = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.security_group_id))
    error_message = "security_group_id must be a valid security group ID, for example sg-0123456789abcdef0."
  }
}

variable "stepfn_definition_file" {
  type        = string
  description = "Path to the Step Functions definition JSON"

  validation {
    condition     = length(trimspace(var.stepfn_definition_file)) > 0
    error_message = "stepfn_definition_file must not be empty."
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
    error_message = "banner_message must not be empty."
  }
}

