# Outputs
output "state_machine_arn" {
  description = "ARN of the Step Function state machine"
  value       = aws_sfn_state_machine.appstream_automation.arn
}

output "ssm_document_names" {
  description = "Map of tenant keys to Terraform-managed SSM document names"
  value       = { for tenant, doc in aws_ssm_document.appstream_setup : tenant => doc.name }
}

output "base_image_name" {
  description = "Base image name"
  value       = var.base_image_name
}
