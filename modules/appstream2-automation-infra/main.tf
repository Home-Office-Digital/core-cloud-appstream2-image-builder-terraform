# IAM Role for Step Functions
resource "aws_iam_role" "step_function_role" {
  name = "${var.project_name}-step-function-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "step_function_policy" {
  name   = "${var.project_name}-step-function-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # Allow AppStream Image Builder & Image actions, scoped to account
      {
        Effect   = "Allow"
        Action   = [
          "appstream:CreateImageBuilder",
          "appstream:DeleteImageBuilder",
          "appstream:DescribeImageBuilders",
          "appstream:DescribeImages",
          "appstream:UpdateImagePermissions",
          "appstream:TagResource"
        ]
        Resource = [
          "arn:aws:appstream:${var.aws_region}:${var.account_id}:image-builder/*",
          "arn:aws:appstream:${var.aws_region}:${var.account_id}:image/*"
        ]
      },

      # SSM permissions for the RunSSMCommand step
      {
        Effect   = "Allow"
        Action   = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.account_id}:managed-instance/*"
      },

      # Allow step-function-role to perfom iam:PassRole on appstream-instance-role
      {
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = [
          aws_iam_role.appstream_instance_role.arn
        ]
      },
      # Allow Step-function-role to perform EC2DescribeInstances on Builder Instances
      {
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceAttribute",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      },
      # SSM permissions for ssm:DescribeInstanceInformation
      {
        Effect   = "Allow"
        Action   = ["ssm:DescribeInstanceInformation"]
        Resource = "*"
      },
      # Allow Step Functions to use the KMS key for CloudWatch Log Group encryption
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.sfn_logs.arn
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "step_function_policy_attachment" {
  role       = aws_iam_role.step_function_role.name
  policy_arn = aws_iam_policy.step_function_policy.arn
}

# IAM Role for AppStream Image Builder
resource "aws_iam_role" "appstream_instance_role" {
  name = "${var.project_name}-appstream-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com",
            "appstream.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_policy" "appstream_instance_policy" {
  name   = "${var.project_name}-appstream-instance-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.account_id}:managed-instance/*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:${var.account_id}:instance/*"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "appstream_instance_policy_attachment" {
  role       = aws_iam_role.appstream_instance_role.name
  policy_arn = aws_iam_policy.appstream_instance_policy.arn
}

# attach the SSM managed instance policy
resource "aws_iam_role_policy_attachment" "appstream_ssm_managed_policy" {
  role       = aws_iam_role.appstream_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "appstream_instance_profile" {
  name = "${var.project_name}-appstream-instance-profile"
  role = aws_iam_role.appstream_instance_role.name
}
# attach the AppStream ServiceAccess managed policy
resource "aws_iam_role_policy_attachment" "appstream_service_access" {
  role       = aws_iam_role.appstream_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAppStreamServiceAccess"
}

# SSM Document for package installation
resource "aws_ssm_document" "appstream_setup" {
  name          = "${var.project_name}-setup-document"
  document_type = "Command"
  content       = file(var.doc_source)
  document_format = "JSON"
}

# Step Function State Machine
resource "aws_sfn_state_machine" "appstream_automation" {
  name       = "${var.project_name}-state-machine"
  role_arn   = aws_iam_role.step_function_role.arn

  
  definition = templatefile(
    var.stepfn_definition_file,
    {
      SSMDocName = aws_ssm_document.appstream_setup.name
      AppStreamInstanceRoleArn = aws_iam_role.appstream_instance_role.arn
      LiveAccountId      = var.live_account_id
      PreliveAccountId   = var.prelive_account_id
    }
  )

  logging_configuration {
    include_execution_data = true
    level                  = "ALL"
    log_destination        = "${aws_cloudwatch_log_group.sfn_logs.arn}:*" 
  }
}

resource "aws_cloudwatch_log_group" "sfn_logs" {
  name              = "/aws/states/${var.project_name}-state-machine"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.sfn_logs.arn
}

data "aws_iam_policy_document" "sfn_logging" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "step_function_logging_policy_attachment" {
  role       = aws_iam_role.step_function_role.name
  policy_arn = aws_iam_policy.sfn_logging.arn
}
