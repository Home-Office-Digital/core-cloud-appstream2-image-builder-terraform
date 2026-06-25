# Outputs
output "state_machine_arn" {
  description = "ARN of the Step Function state machine"
  value       = aws_sfn_state_machine.appstream_automation.arn
}

output "ssm_document_name" {
  description = "Terraform-managed SSM document name for this tenant"
  value       = aws_ssm_document.appstream_setup.name
}

output "base_image_name" {
  description = "Base image name"
  value       = var.base_image_name
}

output "appstream_instance_role_arn" {
  description = "ARN of the IAM role used by the Image Builder instance (instance profile role)"
  value       = aws_iam_role.appstream_instance_role.arn
}

output "build_lock_table_name" {
  description = "Name of the DynamoDB build-lock table this stack uses (owned by the stack with create_shared_resources = true)"
  value       = var.build_lock_table_name
}

output "artifact_bucket_name" {
  description = "Name of the S3 artifact bucket this stack uses (owned by the stack with create_shared_resources = true)"
  value       = var.artifact_bucket_name
}

output "build_lock_table_kms_key_arn" {
  description = "KMS key ARN encrypting the shared build-lock table — set on the platform (owning) stack only"
  value       = var.create_shared_resources ? aws_kms_key.sfn_logs.arn : null
}

output "sfn_logs_kms_key_arn" {
  description = "Deprecated: use build_lock_table_kms_key_arn. Retained so tenant stacks can read platform outputs during the output rename migration."
  value       = var.create_shared_resources ? aws_kms_key.sfn_logs.arn : null
}