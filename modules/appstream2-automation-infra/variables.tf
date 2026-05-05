# Variables
variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "base_image_name" {
  description = "Base AppStream image name"
  type        = string
}

variable "live_account_id" {
  description = "CCPamAppStreamLive AWS Account ID to share the image (live)"
  type        = string
}

variable "prelive_account_id" {
  description = "CCPamAppStreamPrelive AWS Account ID to share the image (prelive)"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "appstream-automation"
}

variable "doc_source" { 
  description = "Path to the SSM document JSON (AppStreamImageAssistant-automation.json)"
  type        = string 
} 

variable "vpc_id" {
  type        = string
  description = "VPC where AppStream Image Builder will launch"
}
variable "subnet_id" {
  type        = string
}
variable "security_group_id" {
  type        = string
}

variable "stepfn_definition_file" {
  type        = string
  description = "Path to the Step Functions definition JSON"
}

variable "account_id" {
  description = "AWS Account ID where the AppStream Image Builder and Step Functions will be created"
  type        = string
}

variable "banner_message" {
  type        = string
  description = "Legal notice displayed to users at AppStream session start"
}

