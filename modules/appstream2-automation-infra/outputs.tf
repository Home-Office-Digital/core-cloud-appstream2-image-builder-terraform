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

output "sfn_logs_kms_key_arn" {
  description = "ARN of this stack's own KMS key (aws_kms_key.sfn_logs). On the owning stack (create_shared_resources = true, conventionally 'platform'), this is ALSO the key that encrypts the shared build-lock table — every other stack reads this output via a terragrunt dependency block to populate its own build_lock_table_kms_key_arn input, rather than hardcoding the ARN, so the value always reflects whatever key actually exists rather than a snapshot that could silently go stale (e.g. after a destroy/recreate or manual key replacement on the owning stack)."
  value       = aws_kms_key.sfn_logs.arn
}
