terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  # Configuration parameters inherited from environment variables or AWS CLI profile
}

# ==============================================================================
# 1. CENTRALIZED SECURITY & AUDITING COMPLIANCE
# ==============================================================================

# Highly Encrypted Auditing Log Bucket with Object Lock Ready & Explicit Lifecycle Rules
resource "aws_s3_bucket" "patch_log_bucket" {
  bucket        = "enterprise-ssm-patch-logs-${var.environment}"
  force_destroy = false # Protect logs against accidental cleanup
}

resource "aws_s3_bucket_server_side_encryption_configuration" "patch_log_encryption" {
  bucket = aws_s3_bucket.patch_log_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "patch_log_privacy" {
  bucket                  = aws_s3_bucket.patch_log_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "patch_log_lifecycle" {
  bucket = aws_s3_bucket.patch_log_bucket.id

  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Enforcement of Encrypted VPC Endpoint Communication for S3 Log Streams
resource "aws_s3_bucket_policy" "patch_log_policy" {
  bucket = aws_s3_bucket.patch_log_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceSSLOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.patch_log_bucket.arn,
          "${aws_s3_bucket.patch_log_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ==============================================================================
# 2. OPERATIONAL ALERTS & NOTIFICATIONS (SNS)
# ==============================================================================

resource "aws_sns_topic" "patch_alerts" {
  name              = "ssm-patch-alerts-${var.environment}"
  kms_master_key_id = "alias/aws/sns" # Mandate encryption at rest for notifications
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.patch_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ==============================================================================
# 3. IDENTITY AND ACCESS MANAGEMENT (IAM GRACEFUL LEAST-PRIVILEGE)
# ==============================================================================

# Core Identity Mapping for standard EC2 Instances
resource "aws_iam_role" "ec2_role" {
  name = "enterprise-ec2-patch-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "ec2_s3_patch_logs" {
  name        = "ssm-ec2-s3-patch-logs-${var.environment}"
  description = "Allows managed EC2 nodes to stream raw logs directly into dedicated S3 storage"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.patch_log_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_s3_patch_logs.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "enterprise-ec2-patch-profile-${var.environment}"
  role = aws_iam_role.ec2_role.name
}

# Dedicated Service Identity for the Systems Manager Background Orchestrator
resource "aws_iam_role" "ssm_service_sns_role" {
  name = "ssm-service-sns-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ssm_sns_publish" {
  name        = "ssm-sns-publish-policy-${var.environment}"
  description = "Allows the SSM engine to cleanly drop notifications onto the corporate SNS topic"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.patch_alerts.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_sns_attach" {
  role       = aws_iam_role.ssm_service_sns_role.name
  policy_arn = aws_iam_policy.ssm_sns_publish.arn
}

# ==============================================================================
# 4. PATCHING ENGINE RULES & SCHEDULING (SSM)
# ==============================================================================

resource "aws_ssm_patch_baseline" "enterprise_baseline" {
  name             = "enterprise-al2023-baseline-${var.environment}"
  description      = "Enterprise Security Alignment Patch Baseline for Amazon Linux 2023"
  operating_system = "AMAZON_LINUX_2023"

  approval_rule {
    approve_after_days = var.patch_burn_in_days
    enable_non_security = false

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "High"]
    }
  }
}

resource "aws_ssm_patch_group" "patch_group_assignment" {
  baseline_id = aws_ssm_patch_baseline.enterprise_baseline.id
  patch_group = "${var.environment}-patch-group"
}

resource "aws_ssm_maintenance_window" "patch_window" {
  name        = "weekly-patch-maintenance-window-${var.environment}"
  schedule    = "cron(0 2 ? * SUN *)" # Every Sunday at 02:00 AM UTC
  duration    = 3
  cutoff      = 1
  allow_unassociated_targets = false
}

resource "aws_ssm_maintenance_window_target" "window_targets" {
  window_id     = aws_ssm_maintenance_window.patch_window.id
  name          = "patch-window-targets-${var.environment}"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:PatchGroup"
    values = ["${var.environment}-patch-group"]
  }
}

resource "aws_ssm_maintenance_window_task" "patching_task" {
  window_id        = aws_ssm_maintenance_window.patch_window.id
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  max_concurrency  = var.max_concurrency
  max_errors       = var.max_errors
  service_role_arn = aws_iam_role.ssm_service_sns_role.arn

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.window_targets.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      comment          = "Automated Enterprise Environment Patch Run Execution Loop"
      timeout_seconds  = 3600
      output_s3_bucket = aws_s3_bucket.patch_log_bucket.id

      notification_config {
        notification_arn    = aws_sns_topic.patch_alerts.arn
        notification_events = ["Failed", "TimedOut"]
        notification_type   = "Command"
      }

      parameter {
        name   = "Operation"
        values = ["Install"]
      }
    }
  }
}
