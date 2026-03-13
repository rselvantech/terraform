output "ubuntu_ami_id" {
  description = "Resolved Ubuntu 24.04 AMI ID for the current region"
  value       = data.aws_ami.ubuntu.id
}

output "ubuntu_ami_name" {
  description = "Full name of the resolved Ubuntu AMI"
  value       = data.aws_ami.ubuntu.name
}

output "ami_us_east_1" {
  description = "Ubuntu AMI ID in us-east-1"
  value       = data.aws_ami.ubuntu_us_east_1.id
}

output "aws_account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_user_arn" {
  description = "ARN of the identity Terraform is authenticated as"
  value       = data.aws_caller_identity.current.arn
}

output "aws_region_name" {
  description = "Current AWS region name"
  value       = data.aws_region.current.region # ← was .name, now .region
}

output "prod_vpc_id" {
  description = "ID of the prod VPC managed outside this Terraform project"
  value       = data.aws_vpc.prod.id
}

output "prod_vpc_cidr" {
  description = "CIDR block of the prod VPC"
  value       = data.aws_vpc.prod.cidr_block
}

output "availability_zones" {
  description = "All available AZs in the current region"
  value       = data.aws_availability_zones.available.names
}

output "s3_public_read_policy_json" {
  description = "The rendered IAM policy JSON from aws_iam_policy_document"
  value       = data.aws_iam_policy_document.s3_public_read.json
}

output "ec2_app_policy_json" {
  description = "Multi-statement IAM policy for EC2 app role"
  value       = data.aws_iam_policy_document.ec2_app_policy.json
}