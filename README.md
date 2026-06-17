# core-cloud-appstream2-image-builder-terraform

# Core Cloud AppStream 2.0 Rocky Linux Image Build Automation Module

This repository houses the **Terraform module** for provisioning the AWS resources required to automate an Amazon AppStream 2.0 streaming image build. The module sets up:

* IAM Roles & Policies for Step Functions and AppStream Image Builder
* Terraform-managed tenant SSM Automation Documents to install and configure packages on a Rocky Linux Image Builder instance
* A Step Functions State Machine to orchestrate the build pipeline
* SFN definition rendered via `templatefile`

---

## Repository Structure

```text
./
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE.md
├── modules
│   └── appstream2-automation-infra
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── tests/
│       │   ├── main.tftest.hcl
│       │   └── fixtures/
│       │       ├── ssm-document.json
│       │       └── stepfunction_definition.json
│       └── README.md
└── README.md         ← (this file)

.github/
├── CODEOWNERS
├── ISSUE_TEMPLATE/
│   ├── bug_report.md
│   └── feature_request.md
├── labels.yml
├── PULL_REQUEST_TEMPLATE.md
└── workflows/
    ├── pull-request-sast.yaml
    ├── pull-request-semver-label-check.yaml
    └── pull-request-semver-tag-merge.yaml
```

---

## Usage

Reference this module from your Terragrunt or Terraform root:

```hcl
module "appstream2_automation" {
  source = "git::https://github.com/UKHomeOffice/core-cloud-appstream2-image-builder-terraform.git//modules/appstream2-automation-infra?ref=v1.0.0"

  # Required inputs
  project_name           = "<your-project>"
  base_image_name        = "AppStream-RockyLinux8-YYYY-MM-DD"
  live_account_id        = "<aws-account-id>"
  prelive_account_id     = "<aws-account-id>"
  ssm_document_sources   = {
    platform = "${path.module}/../platform/ssm/AppStreamImageAssistant-automation.json"
    apc      = "${path.module}/../apc/ssm/AppStreamImageAssistant-automation.json"
  }
  stepfn_definition_file = "${path.module}/../shared/stepfunctions/stepfunction_definition.json"

  # Networking
  vpc_id                 = "<vpc-id>"
  subnet_id              = "<subnet-id>"
  security_group_id      = "<sg-id>"
}
```

After applying this module, you will have:

* An IAM role and policy for running the SSM automation on EC2
* Terraform-managed tenant SSM Automation documents (`aws_ssm_document`) to install packages and invoke `AppStreamImageAssistant`
* A Step Functions state machine (`aws_sfn_state_machine`) definition ready to orchestrate the image build

---

## Inputs

| Name                     | Description                                                                       | Type   | Default | Required |
| ------------------------ | --------------------------------------------------------------------------------- | ------ | ------- | :------: |
| project\_name            | Prefix for naming IAM roles, instance profiles, and state machine                 | string | n/a     |    yes   |
| base\_image\_name        | The base AppStream image name to extend (e.g. `AppStream-RockyLinux8-YYYY-MM-DD`) | string | n/a     |    yes   |
| live\_account\_id        | AWS account ID to share the final image with                                      | string | n/a     |    yes   |
| prelive\_account\_id     | AWS account ID to share the final image with (pre-production)                     | string | n/a     |    yes   |
| ssm\_document\_sources   | Map of tenant names to local SSM Automation JSON document paths                   | map(string) | n/a | yes |
| stepfn\_definition\_file | Local path to the Step Functions JSON definition                                  | string | n/a     |    yes   |
| vpc\_id                  | VPC ID for the AppStream Image Builder instance                                   | string | n/a     |    yes   |
| subnet\_id               | Subnet ID for the Image Builder instance                                          | string | n/a     |    yes   |
| security\_group\_id      | Security Group ID for the Image Builder instance                                  | string | n/a     |    yes   |

---

## Outputs

| Name                | Description                                     |
| ------------------- | ----------------------------------------------- |
| ssm\_document\_names | Map of created SSM Document names by tenant     |
| state\_machine\_arn | ARN of the created Step Functions state machine |
| base\_image\_name   | The `base_image_name` input (echoed back)       |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (if applicable) for guidelines on reporting issues or submitting enhancements.

---

## License

This project is licensed under the [MIT License](LICENSE.md).