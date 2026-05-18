## AppStream 2 Automation Infrastructure Module

This module provisions the core infrastructure used to automate AppStream image build workflows, including IAM roles/policies, an SSM document, and a Step Functions state machine.

## Testing

Terraform native tests for this module are defined in:

- `tests/main.tftest.hcl`

Fixture files used by tests are in:

- `tests/fixtures/ssm-document.json`
- `tests/fixtures/stepfunction_definition.json`

### Run Tests Locally

From this module directory:

```bash
terraform init -backend=false
terraform validate
terraform test
```

### CI Behavior

Terraform tests are executed via GitHub Actions from the top-level workflow and delegated to the reusable workflow.
Test result JSON artifacts are generated per module and summarized in pull request comments.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_iam_instance_profile.appstream_instance_profile](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_policy.appstream_instance_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.step_function_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.appstream_instance_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.step_function_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.appstream_instance_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.appstream_service_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.appstream_ssm_managed_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.step_function_policy_attachment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_sfn_state_machine.appstream_automation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sfn_state_machine) | resource |
| [aws_ssm_document.appstream_setup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_document) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS Account ID where the AppStream Image Builder and Step Functions will be created | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region | `string` | n/a | yes |
| <a name="input_base_image_name"></a> [base\_image\_name](#input\_base\_image\_name) | Base AppStream image name | `string` | n/a | yes |
| <a name="input_doc_source"></a> [doc\_source](#input\_doc\_source) | Path to the SSM document JSON (AppStreamImageAssistant-automation.json) | `string` | n/a | yes |
| <a name="input_live_account_id"></a> [live\_account\_id](#input\_live\_account\_id) | CCPamAppStreamLive AWS Account ID to share the image (live) | `string` | n/a | yes |
| <a name="input_prelive_account_id"></a> [prelive\_account\_id](#input\_prelive\_account\_id) | CCPamAppStreamPrelive AWS Account ID to share the image (prelive) | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name for resource naming | `string` | `"appstream-automation"` | no |
| <a name="input_security_group_id"></a> [security\_group\_id](#input\_security\_group\_id) | n/a | `string` | n/a | yes |
| <a name="input_stepfn_definition_file"></a> [stepfn\_definition\_file](#input\_stepfn\_definition\_file) | Path to the Step Functions definition JSON | `string` | n/a | yes |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | n/a | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC where AppStream Image Builder will launch | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_base_image_name"></a> [base\_image\_name](#output\_base\_image\_name) | Base image name |
| <a name="output_ssm_document_name"></a> [ssm\_document\_name](#output\_ssm\_document\_name) | Name of the SSM document |
| <a name="output_state_machine_arn"></a> [state\_machine\_arn](#output\_state\_machine\_arn) | ARN of the Step Function state machine |
<!-- END_TF_DOCS -->