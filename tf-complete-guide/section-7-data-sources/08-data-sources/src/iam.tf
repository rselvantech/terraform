# Defines an S3 public read policy as a reusable data source
# Produces the same JSON as jsonencode() but with:
# - HCL block syntax (easier to read for complex multi-statement policies)
# - Structural validation (Terraform catches invalid principals, etc.)
# - Reusable — reference .json attribute anywhere in the config
data "aws_iam_policy_document" "s3_public_read" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"

    # Principal "*" — anyone (anonymous public access)
    # type = "*" produces "Principal": "*" in JSON
    # type = "AWS" with identifiers = ["*"] produces "Principal": {"AWS": "*"}
    # These are subtly different — use type = "*" for S3 public website policies
    principals {
      type        = "*"
      identifiers = ["*"]
    }

    # s3:GetObject — allows fetching objects by key (what browsers do)
    # Deliberately excludes s3:ListBucket — prevents listing all object names
    actions = ["s3:GetObject"]

    # /* — applies to all objects inside the bucket, not the bucket itself
    resources = ["arn:aws:s3:::example-bucket/*"]
  }
}

data "aws_iam_policy_document" "ec2_app_policy" {
  # Statement 1: Allow reading from a specific S3 bucket
  statement {
    sid    = "AllowS3Read"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::my-app-config-bucket",
      "arn:aws:s3:::my-app-config-bucket/*",
    ]
  }

  # Statement 2: Allow writing CloudWatch logs
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  # Statement 3: Allow SSM Session Manager (no SSH needed)
  statement {
    sid    = "AllowSSMSession"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}