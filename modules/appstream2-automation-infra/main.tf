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

#checkov:skip=CKV_AWS_355:Describe APIs used by Step Functions (EC2/SSM) require wildcard resources and cannot be resource-scoped.
resource "aws_iam_policy" "step_function_policy" {
  name = "${var.project_name}-step-function-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [

      # Allow AppStream Image Builder & Image actions, scoped to account.
      # NOTE: there is no appstream:CreateImage API — image creation happens
      # ON the Image Builder instance via the AppStreamImageAssistant CLI
      # (platform/scripts/create_image.sh, run inside RunSSMInstall under the
      # instance role below), not via a Step Functions SDK call. The Step
      # Function only ever polls DescribeImages afterward.
      {
        Effect = "Allow"
        Action = [
          "appstream:CreateImageBuilder",
          "appstream:DeleteImageBuilder",
          "appstream:DescribeImageBuilders",
          "appstream:StartImageBuilder",
          "appstream:StopImageBuilder",
          "appstream:DescribeImages",
          "appstream:UpdateImagePermissions",
          "appstream:TagResource"
        ]
        Resource = [
          "arn:aws:appstream:${var.aws_region}:${var.account_id}:image-builder/*",
          "arn:aws:appstream:${var.aws_region}:${var.account_id}:image/*"
        ]
      },

      # SSM permissions for the RunSSMInstall / GetSSMStatus states
      {
        Effect = "Allow"
        Action = [
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
        Effect = "Allow"
        Action = [
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
      # Build lock: conditional PutItem/UpdateItem on this tenant's lock row only.
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = local.build_lock_table_arn
      },
      # Deliberately NOT granted: s3:GetObject on */latest/* — see local.artifact_latest_deny below.
      # The Step Function must only ever receive pre-resolved SHAs from CI/CD.
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.artifact_bucket_arn,
          "${local.artifact_bucket_arn}/*"
        ]
      },
      # FIXED: WriteJobFile (replacing RunSSMInstall's ssm:sendCommand --
      # see the ASL's own Comment field on that state for the full reason)
      # writes jobs/<builderName>/job.json, and GetJobResult reads
      # jobs/<builderName>/result.json back. The existing statement above
      # is read-only and was written before the poller mechanism existed --
      # confirmed needed via the same AccessDenied pattern already hit and
      # fixed on the instance role's policy for its own jobs/ write access.
      # Scoped narrowly to jobs/ only, mirroring the instance role's grant.
      # FIXED (round 2): DeleteObject added -- ClearStaleResult (a new ASL
      # state, runs immediately before WriteJobFile) deletes any leftover
      # result.json from a prior attempt before writing the new job, to
      # close a real race: without this, a stale result (e.g. a
      # no_job_received sentinel from a previous timed-out attempt) could
      # still be sitting at this key when THIS execution's GetJobResult
      # polls, which can happen within seconds -- long before the poller
      # itself would ever reach its own (much later) stale-result check.
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${local.artifact_bucket_arn}/jobs/*"
        ]
      },
      {
        Effect   = "Deny"
        Action   = ["s3:GetObject"]
        Resource = local.artifact_latest_deny_resources
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
      # FIXED: separate grant for the build-lock table's actual encryption
      # key, which is NOT the same as this stack's own sfn_logs key for any
      # tenant except platform (the table owner) — see
      # local.build_lock_table_kms_key_arn above. Needed for AcquireLock's
      # dynamodb:PutItem and ReleaseLockSuccess/ReleaseLockFail's
      # dynamodb:UpdateItem, all of which read/write an item in a
      # server-side-encrypted table.
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = local.build_lock_table_kms_key_arn
      },
      # Required for Step Functions X-Ray tracing when tracing_configuration is enabled
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
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
  name = "${var.project_name}-appstream-instance-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:SendCommand"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.account_id}:managed-instance/*"
      },
      {
        Effect = "Allow"
        Action = [
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
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "ssm:GetParameter"
        ]
        Resource = [
          aws_kms_key.sfn_logs.arn,
          "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/${var.project_name}/appstream/*"
        ]
      },
      # The Image Builder instance itself downloads pinned platform/tenant script
      # artifacts at build time -- never the latest/ pointer.
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          local.artifact_bucket_arn,
          "${local.artifact_bucket_arn}/*"
        ]
      },
      # FIXED: the boot-time poller (ccpam-build-poller.sh) writes
      # result.json/result.log back to jobs/<builderName>/ to report build
      # success/failure -- this is a genuinely new requirement introduced
      # by the poller mechanism, which replaced the original SSM
      # SendCommand approach (confirmed unworkable: AppStream Image
      # Builder instances live in an AWS-internal account, invisible to
      # ec2:describeInstances/ssm:DescribeInstanceInformation in this
      # account). The original instance role was read-only by design,
      # since nothing previously needed to write back -- confirmed via a
      # real AccessDenied on s3:PutObject the first time the poller
      # actually tried to report a result. Scoped narrowly to jobs/ only,
      # not the full bucket, since the instance should never need to
      # write into platform/ or tenants/.
      # FIXED: DeleteObject added -- the poller's stale-result cleanup
      # (deleting a result.json belonging to a different, older jobId
      # before starting a new build) uses `aws s3 rm`, which needs this.
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${local.artifact_bucket_arn}/jobs/*"
        ]
      },
      {
        Effect   = "Deny"
        Action   = ["s3:GetObject"]
        Resource = local.artifact_latest_deny_resources
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

# Single SSM document for this tenant's stack.
# One stack = one tenant = one document, matching the per-tenant isolation
# for_each that bundled every tenant's document into one shared apply.
resource "aws_ssm_document" "appstream_setup" {
  name            = "${var.project_name}-setup-document-${var.tenant_key}"
  document_type   = "Command"
  document_format = "JSON"
  content         = file(var.ssm_document_source)
}

# ---------------------------------------------------------------------------
# Shared resources: DynamoDB build-lock table and S3 artifact bucket.
#
# These are account-wide, not per-tenant, but Terraform doesn't have a native
# "create once across many module calls" primitive. create_shared_resources
# should be true on exactly one tenant stack (conventionally "platform") and
# false everywhere else — every other stack only reads the ARNs via locals
# below using data sources, never re-declares the resources.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "build_locks" {
  count        = var.create_shared_resources ? 1 : 0
  name         = var.build_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "Tenant"

  attribute {
    name = "Tenant"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.sfn_logs.arn
  }

  # This table is shared across every tenant stack.
  # Destroying it would break every tenant's build lock simultaneously, not
  # just this stack's. Guard against an accidental `terraform destroy` on
  # the platform stack taking the whole lock mechanism down with it.
  lifecycle {
    prevent_destroy = true
  }
}

#checkov:skip=CKV2_AWS_62:No S3 event consumer exists in this design (no Lambda/SQS/EventBridge reacting to new objects) — adding a notification configuration with nothing subscribed to it would configure a capability nothing uses, not close a real gap.
#checkov:skip=CKV_AWS_144:Every object here is a SHA-versioned, checksum-verified copy of content already in source control (platform/scripts/**, tenants/*/scripts/**) — recovery from a regional loss is "re-run publish-artifacts.yaml", not "fail over to a replica." CRR would add ongoing cost/complexity to protect data that isn't actually unique or irreplaceable.
resource "aws_s3_bucket" "artifacts" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = var.artifact_bucket_name

  # Shared across every tenant stack. Same reasoning
  # as the lock table above — accidental destroy here would delete every
  # tenant's versioned script history, not just this stack's.
  lifecycle {
    prevent_destroy = true
  }
}

# Access logging target for the artifact bucket (Checkov: S3 access logging).
# A separate bucket is required — S3 does not allow a bucket to log to itself.
#checkov:skip=CKV2_AWS_62:Same reasoning as the artifacts bucket above — no event consumer exists for this bucket either.
#checkov:skip=CKV_AWS_144:Access logs are operationally useful but not irreplaceable business data; same cost/complexity reasoning as the artifacts bucket above applies.
resource "aws_s3_bucket" "artifacts_access_logs" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = "${var.artifact_bucket_name}-access-logs"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts_access_logs" {
  count                   = var.create_shared_resources ? 1 : 0
  bucket                  = aws_s3_bucket.artifacts_access_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "artifacts_access_logs" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = aws_s3_bucket.artifacts_access_logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts_access_logs" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = aws_s3_bucket.artifacts_access_logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.sfn_logs.arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts_access_logs" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = aws_s3_bucket.artifacts_access_logs[0].id

  rule {
    id     = "expire-old-access-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Log bucket needs s3:PutObject granted to the S3 log delivery service
# principal, scoped to this account, per AWS's standard server access
# logging setup — without this ACL/policy grant, log delivery silently fails.
resource "aws_s3_bucket_policy" "artifacts_access_logs" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = aws_s3_bucket.artifacts_access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.artifacts_access_logs[0].arn}/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.artifacts[0].arn
          }
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_logging" "artifacts" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  target_bucket = aws_s3_bucket.artifacts_access_logs[0].id
  target_prefix = "artifact-bucket-access-logs/"
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id

  rule {
    id     = "expire-old-build-artifacts"
    status = "Enabled"

    # Versioned S3 prefixes here exist purely to give each concurrent build
    # an immutable pin for the duration of that build
    # — they are not a long-term audit trail; git already provides
    # that. A pin only needs to stay stable for the life of one build, so
    # pruning prefixes well past any plausible build duration keeps the
    # bucket small without weakening the concurrency guarantee.
    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  count  = var.create_shared_resources ? 1 : 0
  bucket = aws_s3_bucket.artifacts[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.sfn_logs.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  count                   = var.create_shared_resources ? 1 : 0
  bucket                  = aws_s3_bucket.artifacts[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tenant stacks that don't own the shared resources look them up by name/ARN
# instead of re-declaring them, so every stack can reference the same ARNs
# for IAM policy attachment regardless of which stack created them.
data "aws_dynamodb_table" "build_locks" {
  count = var.create_shared_resources ? 0 : 1
  name  = var.build_lock_table_name
}

data "aws_s3_bucket" "artifacts" {
  count  = var.create_shared_resources ? 0 : 1
  bucket = var.artifact_bucket_name
}

locals {
  build_lock_table_arn = var.create_shared_resources ? aws_dynamodb_table.build_locks[0].arn : data.aws_dynamodb_table.build_locks[0].arn
  artifact_bucket_arn  = var.create_shared_resources ? aws_s3_bucket.artifacts[0].arn : data.aws_s3_bucket.artifacts[0].arn

  # FIXED (round 2): the previous version of this local read
  # data.aws_dynamodb_table.build_locks[0].server_side_encryption[0].kms_key_arn
  # — a real, correct attribute path against actual AWS, but
  # server_side_encryption is implemented as a legacy SDKv2 schema Block,
  # not a plain Attribute, and Terraform's test-framework override_data
  # cannot populate Block-typed fields at all (confirmed: a real
  # HashiCorp Discuss report of this exact limitation). The override
  # silently no-ops, leaving the list empty in every test run regardless of
  # what values are specified, causing "Invalid index" every time. Switched
  # to a plain input variable instead — same pattern as
  # build_lock_table_name/artifact_bucket_name above — which sidesteps the
  # whole class of problem since variables are trivially settable in both
  # real Terragrunt inputs and test run blocks.
  build_lock_table_kms_key_arn = var.create_shared_resources ? aws_kms_key.sfn_logs.arn : var.build_lock_table_kms_key_arn

  # Structurally enforces : nothing reading
  # through this module's IAM roles may ever resolve the latest/ pointer.
  # Only the CI/CD role (managed outside this module) may read it.
  artifact_latest_deny_resources = [
    "${local.artifact_bucket_arn}/platform/latest/*",
    "${local.artifact_bucket_arn}/tenants/*/latest/*"
  ]
}

# Step Function State Machine
# Definition is the v1.5 ASL -- a pure JSON file, not a
# templatefile(). Nothing tenant-specific is baked into the definition itself;
# every value (tenant, platformVersion, tenantVersion, builderName,
# startedAtEpoch, imageName, liveAccountId, preliveAccountId) arrives at
# StartExecution time, resolved by CI/CD. instanceId was removed entirely
# in v1.5 -- the poller-based design (see ccpam-build-poller.sh) never
# needed one; only builderName is required to address the jobs/ S3 paths.
resource "aws_sfn_state_machine" "appstream_automation" {
  name     = "${var.project_name}-state-machine"
  role_arn = aws_iam_role.step_function_role.arn

  # Keep tracing enabled to satisfy security/compliance controls.
  tracing_configuration {
    enabled = true
  }

  definition = file(var.stepfn_definition_file)

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

resource "aws_iam_role_policy_attachment" "step_function_logging_policy_attachment" {
  role       = aws_iam_role.step_function_role.name
  policy_arn = aws_iam_policy.sfn_logging.arn
}

# SSM Parameter Store — AppStream session banner message
resource "aws_ssm_parameter" "banner_message" {
  name        = "/${var.project_name}/appstream/banner-message"
  type        = "SecureString"
  key_id      = aws_kms_key.sfn_logs.arn
  description = "Legal banner message displayed at AppStream session start"
  value       = var.banner_message

  lifecycle {
    ignore_changes = [value] # ← prevents Terraform overwriting manual updates
  }
}

# KMS Key for Step Functions CloudWatch log encryption
resource "aws_kms_key" "sfn_logs" {
  description             = "KMS key for ${var.project_name} Step Functions CloudWatch logs"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow the account root full access
      {
        Sid    = "EnableRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      # Allow Step Functions role to use the key for log encryption
      {
        Sid    = "AllowStepFunctionsLogging"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      # Allow CloudWatch Logs to use the key
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "sfn_logs" {
  name          = "alias/${var.project_name}-sfn-logs"
  target_key_id = aws_kms_key.sfn_logs.key_id
}

# IAM Policy for Step Functions logging.
#
# Previously built from a data "aws_iam_policy_document" "sfn_logging" block
# — removed in favour of a direct jsonencode(), matching every other policy
# in this file, after that exact data source ran into an unresolved upstream
# bug in terraform-provider-aws (github.com/hashicorp/terraform-provider-aws
# issue #36700) and terraform core (issue #34764): under `mock_provider
# "aws" {}` in terraform test, aws_iam_policy_document's computed .json
# output does not populate correctly even with override_data targeting it
# explicitly. Since this statement was entirely static (no variable
# interpolation), a plain jsonencode() removes the dependency on the
# affected data source entirely rather than working around a bug that has
# no working workaround.
#checkov:skip=CKV_AWS_355:CloudWatch Logs delivery APIs used here require wildcard resources.
resource "aws_iam_policy" "sfn_logging" {
  name = "${var.project_name}-sfn-logging-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}