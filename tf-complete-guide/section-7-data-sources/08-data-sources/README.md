# Demo-08: Data Sources

## Demo Overview

This demo explores **Terraform data sources** — one of the most important
concepts for writing professional, maintainable Terraform configurations.
Data sources allow Terraform to **query and retrieve information from
remote APIs** without creating or managing the resource. This enables you
to reference infrastructure managed by other teams, avoid hardcoded values,
and build dynamic, reusable configurations.

**What you'll cover — five real-world data source use cases:**

| Part | Data Source | Use Case |
|---|---|---|
| A | `aws_ami` | Dynamically resolve Ubuntu AMI ID — no more hardcoded region-specific IDs |
| B | `aws_caller_identity` + `aws_region` | Retrieve current AWS account ID and region for use in IAM policies and ARNs |
| C | `aws_vpc` | Reference a VPC managed by another team without importing or recreating it |
| D | `aws_availability_zones` | Build region-agnostic subnet configurations |
| E | `aws_iam_policy_document` | Define IAM policies in HCL with validation — replaces `jsonencode()` |

**Terraform concepts introduced:**
- `data` block syntax and structure
- Difference between `resource` and `data` blocks
- `most_recent`, `owners`, `filter` arguments in `aws_ami`
- `name_regex` for pattern-based AMI filtering
- Referencing data source attributes: `data.<type>.<name>.<attribute>`
- Using aliased providers to query data from another region
- `aws_iam_policy_document` — HCL-native IAM policy definition with validation
- `jsonencode()` vs `aws_iam_policy_document` — when to use each
- Data sources are read-only — they never create, modify, or destroy resources

## Prerequisites

**From Previous Demos:**
- ✅ Completed [Demo-06: Resources — EC2 NGINX](../06-resources-ec2-nginx/README.md)
- ✅ Completed [Demo-07: S3 Static Website](../07-s3-static-website/README.md)

**Required Tools:**
- ✅ Terraform CLI `>= 1.14.4`
- ✅ AWS CLI `>= 2.32.1` configured (`aws configure`)
- ✅ AWS account with EC2 and VPC permissions

**Verify Prerequisites:**

```bash
terraform version
# Expected: Terraform v1.14.4 or higher

aws sts get-caller-identity
# Expected: JSON with Account, UserId, Arn

aws configure get region
# or
echo $AWS_REGION
# Expected: your target region (e.g., us-east-2)
```

---

## Demo Objectives

By the end of this demo, you will:

1. ✅ Understand what data sources are and how they differ from resources
2. ✅ Use `data "aws_ami"` to resolve Ubuntu AMI IDs dynamically per region
3. ✅ Understand `most_recent`, `owners`, `filter`, and `name_regex` arguments
4. ✅ Use `data "aws_caller_identity"` to retrieve the current AWS account ID
5. ✅ Use `data "aws_region"` to retrieve the currently configured region
6. ✅ Use an aliased provider to query data from a different region
7. ✅ Use `data "aws_vpc"` to reference infrastructure managed by another team
8. ✅ Understand what happens when a data source filter matches nothing
9. ✅ Use `data "aws_availability_zones"` to build region-agnostic configurations
10. ✅ Use `data "aws_iam_policy_document"` as a better alternative to `jsonencode()`
11. ✅ Understand when to use `jsonencode()` vs `aws_iam_policy_document`

---

## Concepts

### What is a Data Source?

In Terraform, a `resource` block **creates and manages** infrastructure.
A `data` block **reads existing information** from a remote API — it never
creates, modifies, or destroys anything.

```hcl
# resource block — creates and manages an EC2 instance
resource "aws_instance" "web" {
  ami           = "ami-0abc123"
  instance_type = "t3.micro"
}

# data block — reads an existing AMI from AWS
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}
```

**Data block syntax:**

```hcl
data "<data_source_type>" "<local_name>" {
  # filter arguments
}
```

**Referencing a data source:**

```hcl
data.<data_source_type>.<local_name>.<attribute>

# example
data.aws_ami.ubuntu.id          # the resolved AMI ID
data.aws_ami.ubuntu.name        # the AMI name
data.aws_ami.ubuntu.arn         # the AMI ARN
```

---

### Why Data Sources Matter

**The problem with hardcoded AMI IDs:**

```hcl
# ❌ Hardcoded — breaks when you switch regions
resource "aws_instance" "web" {
  ami = "ami-06492140a3c4a3483"   # only valid in us-east-2
}
```

`ami-06492140a3c4a3483` is the NGINX AMI ID for `us-east-2`. In `us-east-1`
this ID either doesn't exist or points to a completely different image.
Every region requires a different ID. Every time Ubuntu releases a new version
you need to manually update the ID.

**The solution — data source:**

```hcl
# ✅ Dynamic — resolves the correct AMI for whatever region the provider is in
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_instance" "web" {
  ami = data.aws_ami.ubuntu.id   # always the right AMI for the current region
}
```

---

### When are Data Sources Read?

Data sources are read during `terraform plan` when all their arguments are
known. If a data source argument depends on a value that is only known after
apply (e.g., a resource ID), it is deferred to the apply phase.

```
terraform plan / apply
  │
  ├── Read data sources (query remote APIs)
  ├── Diff: compare state vs desired config
  ├── Plan: compute resource changes
  └── Apply: execute changes (resources only — data sources are read-only)
```

---

### `jsonencode()` vs `aws_iam_policy_document`

Both produce valid IAM policy JSON. Here is when to use each:

| | `jsonencode()` | `aws_iam_policy_document` |
|---|---|---|
| Syntax | HCL map → JSON | HCL blocks → JSON |
| Validation | None — any value accepted | ✅ Validates structure |
| Reusability | Inline only | ✅ Referenceable from multiple places |
| Policy merging | ❌ Not supported | ✅ `source_policy_documents` + `override_policy_documents` |
| Output attribute | N/A | `.json` attribute |
| Best for | Simple one-off policies | All production IAM policies |

**Official recommendation (HashiCorp):** Use `aws_iam_policy_document` for
all IAM policies — it provides validation and reusability that `jsonencode()`
does not.

---

## Directory Structure

```
08-data-sources/
├── README.md
└── src/
    ├── provider.tf         # Terraform block + aws provider
    ├── compute.tf          # Part A: aws_ami data source + EC2 instance
    ├── identity.tf         # Part B: aws_caller_identity + aws_region
    ├── vpc.tf              # Part C: aws_vpc — external resource reference
    ├── availability.tf     # Part D: aws_availability_zones
    ├── iam.tf              # Part E: aws_iam_policy_document
    └── outputs.tf          # All outputs
```

---

## Part A: `aws_ami` — Dynamic AMI Resolution

### Step 1: Create `provider.tf`

```hcl
terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.30.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}
```

```bash
terraform init
```

---

### Step 2: Create `compute.tf` — AMI Data Source

```hcl
# Dynamically resolves the latest Ubuntu 24.04 LTS (Noble) AMI
# for the current provider region — no hardcoded AMI ID needed
data "aws_ami" "ubuntu" {
  # OPTIONAL — when multiple AMIs match, return the most recently created
  # Without this, Terraform errors if more than one result is found
  most_recent = true

  # MANDATORY — at least one owner required
  # "099720109477" is Canonical's AWS account ID (publisher of Ubuntu AMIs)
  # Using the account ID is more reliable than the alias "canonical"
  owners = ["099720109477"]

  # Filter by AMI name pattern — wildcards (*) match any characters
  # hvm-ssd-gp3 = HVM virtualization, gp3 EBS root volume (current gen)
  # ubuntu-noble-24.04 = Ubuntu 24.04 LTS
  # amd64 = x86_64 architecture (required for t3.micro)
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  # Ensures we only get HVM (hardware virtual machine) images
  # HVM is required for current-generation instance types (t3, m5, etc.)
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web" {
  # AMI resolved dynamically from the data source above
  # No region-specific AMI ID hardcoded here
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  tags = {
    Name      = "08-data-sources-web"
    ManagedBy = "Terraform"
    Project   = "08-data-sources"
  }
}
```

**Run plan and observe:**

```bash
terraform fmt
terraform plan
```

**Expected — data source resolved at plan time:**
```
data.aws_ami.ubuntu: Reading...
data.aws_ami.ubuntu: Read complete after 1s [id=ami-0xxxxxxxxxxxxxxxxx]

Terraform will perform the following actions:

  + resource "aws_instance" "web" {
      + ami = "ami-0xxxxxxxxxxxxxxxxx"   ← resolved from data source
      ...
    }
```

The AMI ID shown is the correct one for `us-east-2` — Terraform resolved it
automatically. No Console navigation, no CLI command, no manual ID lookup.

---

### Step 3: Understand `name_regex` vs `filter`

`filter.name` uses shell-style wildcards (`*`). `name_regex` uses regular
expressions — more powerful but easier to misconfigure.

```hcl
# Using name_regex — matches any Ubuntu 22.04 regardless of storage type
data "aws_ami" "ubuntu_22" {
  most_recent = true
  owners      = ["099720109477"]

  # Regex: ubuntu, then anything, then 22.04, then amd64
  name_regex = "ubuntu.*22\\.04.*amd64.*"

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

> **Prefer `filter` over `name_regex`** for production use — filter patterns
> are simpler, less error-prone, and match how Ubuntu officially names its AMIs.

---

### Step 4: Add AMI Outputs to `outputs.tf`

```hcl
output "ubuntu_ami_id" {
  description = "Resolved Ubuntu 24.04 AMI ID for the current region"
  value       = data.aws_ami.ubuntu.id
}

output "ubuntu_ami_name" {
  description = "Full name of the resolved Ubuntu AMI"
  value       = data.aws_ami.ubuntu.name
}
```

```bash
terraform apply -auto-approve
terraform output
```

**Expected:**
```
ubuntu_ami_id   = "ami-0xxxxxxxxxxxxxxxxx"
ubuntu_ami_name = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-20250115"
```

**Verify in AWS Console:**

1. Go to **EC2 → Images → AMIs**
2. Change filter to **Public images**
3. Search the AMI ID from the output
4. Confirm: Owner is `099720109477` (Canonical), Architecture is `x86_64`

---

### Step 5: Query AMI from a Different Region (Multi-Region Pattern)

To resolve an AMI from a different region, use an aliased provider:

**Add to `provider.tf`:**

```hcl
# Additional provider instance for us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
```
**Add to `compute.tf`:**

```hcl
# Same AMI but in us-east-1 (uses aliased provider)
data "aws_ami" "ubuntu_us_east_1" {
  provider    = aws.us_east_1   # explicit provider assignment
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}
```

**Add to `outputs.tf`:**

```hcl
output "ami_us_east_1" {
  description = "Ubuntu AMI ID in us-east-1"
  value       = data.aws_ami.ubuntu_us_east_1.id
}
```

```bash
terraform init   # required after adding new provider alias
terraform plan
```

**Expected — two different AMI IDs:**
```
ami_us_east_1 = "ami-0bbb..."   ← us-east-1 AMI ID (different)
```

This confirms AMI IDs are region-specific — the same Ubuntu 24.04 image has
a different ID in every AWS region.

> After verifying, remove the multi-region block and revert to the single
> `aws_ami.ubuntu` data source to keep the config clean for the next parts.

---

## Part B: `aws_caller_identity` + `aws_region`

### Step 6: Create `identity.tf`

These two data sources retrieve metadata about the current AWS authentication
context and provider configuration. No arguments are required — they work
purely from the active provider and credentials.

```hcl
# Retrieves information about the AWS account and identity
# Terraform is currently authenticated as
# Primary use case: retrieve account_id for use in IAM policy ARNs
data "aws_caller_identity" "current" {}

# Retrieves the AWS region currently configured in the provider
# Primary use case: build region-aware resource names or ARNs
# without hardcoding the region string
data "aws_region" "current" {}
```

Add to `outputs.tf`:

```hcl
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
  value       = data.aws_region.current.name
}
```

```bash
terraform plan
```

**Expected:**
```
aws_account_id = "123456789012"
aws_user_arn   = "arn:aws:iam::123456789012:user/your-user"
aws_region_name = "us-east-2"
```

**Professional use case — building IAM ARNs without hardcoding account ID:**

```hcl
# ❌ Hardcoded account ID — breaks when used in other accounts
resource = "arn:aws:s3:::my-bucket"
principal = "arn:aws:iam::123456789012:role/my-role"

# ✅ Dynamic — works in any account
resource  = "arn:aws:s3:::my-bucket"
principal = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/my-role"
```

**Query a different region's metadata:**

```hcl
# Explicitly pass provider to get us-east-1 region info
data "aws_region" "us_east_1" {
  provider = aws.us_east_1
}
```

The `provider` argument is a **meta-argument** — available on all resources
and data sources, not listed under the data source's own argument reference.
It is added by Terraform itself, not by the AWS provider.

---

## Part C: `aws_vpc` — Referencing External Infrastructure

### Step 7: Create a Console-Managed VPC

This simulates a real-world pattern where a **platform team manages the VPC**
and your team only deploys applications into it.

1. Go to **VPC → Your VPCs → Create VPC**
2. Select **VPC only**
3. Name tag: `console-managed`
4. IPv4 CIDR: `172.16.0.0/16`
5. Add tag: `Key=Env`, `Value=prod`
6. Click **Create VPC**

> Do **not** create this VPC in Terraform — we are simulating external
> infrastructure. The whole point is to reference it without owning it.

---

### Step 8: Create `vpc.tf` — Reference Without Managing

```hcl
# Fetches an existing VPC by tag — does not create or manage it
# Use case: deploy resources into a VPC owned by another team
data "aws_vpc" "prod" {
  # Filter by tag to identify the correct VPC
  # Terraform errors if 0 or more than 1 VPC matches
  tags = {
    Env = "prod"
  }
}
```

Add to `outputs.tf`:

```hcl
output "prod_vpc_id" {
  description = "ID of the prod VPC managed outside this Terraform project"
  value       = data.aws_vpc.prod.id
}

output "prod_vpc_cidr" {
  description = "CIDR block of the prod VPC"
  value       = data.aws_vpc.prod.cidr_block
}
```

```bash
terraform plan
```

**Expected:**
```
prod_vpc_id   = "vpc-0xxxxxxxxxxxxxxxxx"
prod_vpc_cidr = "172.16.0.0/16"
```

**Verify in AWS Console:**

1. Go to **VPC → Your VPCs**
2. Find `console-managed` VPC
3. Copy the VPC ID — it should match the `prod_vpc_id` output exactly

---

### Step 9: Observe Error When Filter Matches Nothing

Change the tag value to something that does not exist:

```hcl
data "aws_vpc" "prod" {
  tags = {
    Env = "nonexistent"   # no VPC has this tag
  }
}
```

```bash
terraform plan
```

**Expected error:**
```
│ Error: no matching VPC found
│
│   with data.aws_vpc.prod,
│   on vpc.tf line 1, in data "aws_vpc" "prod":
│    1: data "aws_vpc" "prod" {
```

Terraform **stops execution** when a data source filter returns no results —
it does not silently continue. This is a safety feature.

> ⚠️ **The flip side:** If you accidentally write the wrong tag value (e.g.,
> `prod` when you meant `staging`), Terraform will happily fetch the wrong
> VPC and deploy into the wrong environment. Always double-check filter values.
> Terraform `postconditions` (covered in advanced topics) can add validation
> to prevent this.

Revert the tag value back to `prod` before continuing.

---

## Part D: `aws_availability_zones` — Region-Agnostic Configurations

### Step 10: Create `availability.tf`

Availability zone names differ by region. Hardcoding `us-east-2a` breaks when
the configuration is reused in a different region. Data sources solve this.

```hcl
# Fetches all availability zones in the current region
# state = "available" — excludes impaired or unavailable AZs
data "aws_availability_zones" "available" {
  state = "available"
}
```

Add to `outputs.tf`:

```hcl
output "availability_zones" {
  description = "All available AZs in the current region"
  value       = data.aws_availability_zones.available.names
}
```

```bash
terraform plan
```

**Expected (for us-east-2):**
```
availability_zones = [
  "us-east-2a",
  "us-east-2b",
  "us-east-2c",
]
```

**What the data source returns — object structure:**

```hcl
data.aws_availability_zones.available = {
  id     = "us-east-2"                          # region ID
  names  = ["us-east-2a", "us-east-2b", "us-east-2c"]  # list of AZ names
  state  = "available"
  zone_ids = ["use2-az1", "use2-az2", "use2-az3"]
}
```

**Professional use case — region-agnostic subnet creation:**

```hcl
# Creates one subnet per AZ — works in any region
# regardless of how many AZs that region has

resource "aws_subnet" "public" {
  count             = length(data.aws_availability_zones.available.names)
  vpc_id            = data.aws_vpc.prod.id   # ← references the data source VPC
  availability_zone = data.aws_availability_zones.available.names[count.index]
  cidr_block        = "10.0.${count.index}.0/24"
}

```

This pattern automatically creates 2 subnets in `eu-west-1` (2 AZs), 3 in
`us-east-2` (3 AZs), and 6 in `us-east-1` (6 AZs) — all from the same code.
`count` and `count.index` will be covered fully in a later demo.

---

## Part E: `aws_iam_policy_document` — HCL-Native IAM Policies

### Step 11: Refactor the S3 Bucket Policy from Demo-07

In Demo-07, the S3 bucket policy was written using `jsonencode()`:

```hcl
# Demo-07 approach — jsonencode()
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Sid       = "PublicReadGetObject"
    Effect    = "Allow"
    Principal = "*"
    Action    = "s3:GetObject"
    Resource  = "${aws_s3_bucket.static_website.arn}/*"
  }]
})
```

The `aws_iam_policy_document` data source achieves the same result with
better validation and reusability.

### Step 12: Create `iam.tf`

```hcl
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
```

Add to `outputs.tf`:

```hcl
output "s3_public_read_policy_json" {
  description = "The rendered IAM policy JSON from aws_iam_policy_document"
  value       = data.aws_iam_policy_document.s3_public_read.json
}
```

```bash
terraform plan
```

**Expected — see the rendered JSON:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-bucket/*"
    }
  ]
}
```

This is identical to what `jsonencode()` would produce — the difference is
that `aws_iam_policy_document` validates the structure as you write it.

**Validation in action — observe a caught error:**

Remove the `identifiers` argument from `principals`:

```hcl
principals {
  type = "*"
  # identifiers missing
}
```

```bash
terraform validate
```

**Expected:**
```
│ Error: Missing required argument
│
│   The argument "identifiers" is required, but no definition was found.
```

`jsonencode()` would silently accept this malformed input and produce invalid
JSON that only fails at apply time when AWS rejects it. `aws_iam_policy_document`
catches it immediately at validate/plan time.

Restore the correct `identifiers` before continuing.

---

### Step 13: Multi-Statement Policy — Professional Use Case

A more realistic example: an IAM policy for an EC2 instance role that needs
to read from S3 and write CloudWatch logs.

Add to `iam.tf`:

```hcl
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
```

Add to `outputs.tf`:

```hcl
output "ec2_app_policy_json" {
  description = "Multi-statement IAM policy for EC2 app role"
  value       = data.aws_iam_policy_document.ec2_app_policy.json
}
```

```bash
terraform plan
```

The output shows a clean, correctly formatted multi-statement JSON policy.
Writing this as `jsonencode()` would work but becomes hard to read and
maintain as the number of statements grows.

---

## Cleanup

```bash
# Destroy only Terraform-managed resources (EC2 instance)
terraform destroy
# Type: yes

# Manually delete the Console-managed VPC (not managed by Terraform)
# Go to: VPC → Your VPCs → select "console-managed" → Actions → Delete VPC
```

```bash
rm -rf .terraform/ .terraform.lock.hcl
```

---

## What You Learned

In this demo, you:

- ✅ Understood the difference between `resource` (creates) and `data` (reads) blocks
- ✅ Used `aws_ami` with `most_recent`, `owners`, `filter` to resolve Ubuntu AMI IDs dynamically
- ✅ Understood why `filter` is preferred over `name_regex` for production AMI lookups
- ✅ Used an aliased provider to query AMI IDs from a different region
- ✅ Used `aws_caller_identity` to retrieve account ID and user ARN without hardcoding
- ✅ Used `aws_region` to retrieve the current provider region dynamically
- ✅ Used `aws_vpc` to reference a VPC managed by another team
- ✅ Observed Terraform stopping with an error when a data source filter matches nothing
- ✅ Used `aws_availability_zones` to build region-agnostic subnet configurations
- ✅ Used `aws_iam_policy_document` to define IAM policies in HCL with validation
- ✅ Understood when to use `jsonencode()` vs `aws_iam_policy_document`

**Key Insight:** Data sources are what make Terraform configurations reusable
across regions, accounts, and environments. Hardcoded AMI IDs, account IDs,
and AZ names are the most common causes of Terraform configurations that work
in one environment but fail in another. Data sources eliminate all of these.

---

## Lessons Learned

### 1. Canonical's AWS Account ID Is More Reliable Than the Alias

`owners = ["099720109477"]` (Canonical's account ID) is more stable than
`owners = ["canonical"]` (alias). AWS owner aliases can change — account IDs
do not.

### 2. Always Use `state = "available"` for Availability Zones

Without this filter, Terraform may include impaired or unavailable AZs in the
result. Always filter by `state = "available"` to avoid deploying into
degraded infrastructure.

### 3. Data Source Filter Must Match Exactly One Result (Unless `most_recent`)

For most data sources (e.g., `aws_vpc`), Terraform errors if the filter
matches zero OR more than one result. Use specific tag combinations to ensure
uniqueness. For `aws_ami`, add `most_recent = true` to handle multiple matches.

### 4. `aws_iam_policy_document` Over `jsonencode()` for All IAM Policies

`jsonencode()` is fine for simple one-off cases (like Demo-07's S3 bucket
policy). For any IAM policy that might grow, be reused, or be reviewed —
use `aws_iam_policy_document`. It validates structure, supports merging
policies, and produces cleaner code.

### 5. Deleting an Externally-Managed Resource Breaks Your Data Source

If someone deletes the `console-managed` VPC from the Console while your
Terraform project references it via `data "aws_vpc"`, the next
`terraform plan` will error. This is expected — you are dependent on
external infrastructure. Always coordinate with the team that owns it.

---


## Next Steps

**Demo-09: Input Variables and Outputs**
- Parameterize configurations with `variable {}` blocks
- Variable types, defaults, validation rules
- Pass variables via CLI, `.tfvars` files, and environment variables
- Use `output {}` to expose values between Terraform projects

---

## Troubleshooting

**`no matching AMI found` on `terraform plan`:**

The `filter` name pattern does not match any available AMIs. Ubuntu renames
their AMI paths periodically. Verify the current pattern:

```bash
aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble*amd64*" \
  --query 'Images[*].Name' \
  --output table \
  --region us-east-2
```

**`no matching VPC found`:**

The tag filter returned no results. Verify the VPC exists and the tag key/value
matches exactly (case-sensitive):

1. Go to **VPC → Your VPCs**
2. Click the VPC → **Tags tab**
3. Confirm the exact tag key and value

**`multiple VPCs matched` error:**

More than one VPC has the same tag. Add additional filters to narrow to a
single result (e.g., add `cidr_block` or a more specific tag).

**`aws_caller_identity` shows unexpected account:**

Your AWS CLI is configured with credentials for a different account than
expected. Verify:

```bash
aws sts get-caller-identity
```

---

## Common Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Initialize project and download providers |
| `terraform fmt` | Format all `.tf` files to canonical style |
| `terraform validate` | Validate configuration syntax and argument types |
| `terraform plan` | Show planned changes and data source reads |
| `terraform apply -auto-approve` | Apply without confirmation prompt |
| `terraform destroy` | Destroy all managed resources |
| `terraform output` | Show all output values |
| `terraform output <name>` | Show a specific output value |
| `terraform state list` | List all resources tracked in state |