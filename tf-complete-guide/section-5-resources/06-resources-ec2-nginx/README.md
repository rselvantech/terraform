# Demo-06: Deploy a Public NGINX Server on AWS EC2

## Demo Overview

This is the first complete end-to-end infrastructure project — deploying a **publicly accessible NGINX web server on AWS EC2** using Terraform. Everything is provisioned from scratch: networking, compute, and security. No manual Console actions for resource creation — Terraform manages the full lifecycle.

**What you'll build:**

```
Internet
    │  HTTP :80 / HTTPS :443
    ▼
┌──────────────────────────────────────────────┐
│  VPC  10.0.0.0/16                            │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │  Public Subnet  10.0.0.0/24            │  │
│  │                                        │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │  EC2 (t3.micro)                  │  │  │
│  │  │  AMI: Bitnami NGINX              │  │  │
│  │  │  Security Group: ports 80, 443   │  │  │
│  │  │  Public IP: assigned             │  │  │
│  │  └──────────────────────────────────┘  │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  Internet Gateway ──► Route Table            │
│  0.0.0.0/0 → IGW                             │
└──────────────────────────────────────────────┘
```

**Resources created (9 total):**
- `aws_vpc` — isolated network
- `aws_subnet` — public subnet
- `aws_internet_gateway` — internet access
- `aws_route_table` — routes internet traffic via IGW
- `aws_route_table_association` — binds route table to subnet
- `aws_security_group` — virtual firewall for EC2
- `aws_vpc_security_group_ingress_rule` × 2 — allow HTTP (80) and HTTPS (443)
- `aws_instance` — EC2 running NGINX

**Terraform concepts introduced:**
- `locals` block for common tags
- `merge()` function for resource-specific tag merging
- `provider "aws" { default_tags {} }` — alternative to locals for tagging
- `lifecycle { create_before_destroy = true }` — zero-downtime replacement
- `lifecycle { ignore_changes = [tags] }` — handling external drift
- `terraform state list` — inspect managed resources
- `terraform apply -destroy` — alias for `terraform destroy`
- In-place update vs forced replacement (AMI change)
- State refresh behavior

## Prerequisites

**From Previous Demos:**
- ✅ Completed [Demo-03: Remote Backends](../03-s3-backend/README.md)
- ✅ Completed [Demo-05: Providers](../05-providers/README.md)

**Required Tools:**
- ✅ Terraform CLI `>= 1.14.4` 
- ✅ AWS CLI `>= 2.32.x` configured (`aws configure`)
- ✅ AWS account with EC2, VPC, and S3 permissions

**Verify Prerequisites:**

```bash
terraform version
# Expected: Terraform v1.10.x or higher

aws sts get-caller-identity
# Expected: JSON with Account, UserId, Arn

aws configure get region
(or)
echo $AWS_REGION
# Expected: your target region (e.g., us-east-2)
```

---

## Demo Objectives

By the end of this demo, you will:

1. ✅ Build a complete AWS network foundation: VPC, subnet, IGW, route table
2. ✅ Use `locals` and `merge()` to manage tags without duplication
3. ✅ Find the correct AMI ID for your region (architecture gotcha: ARM64 vs AMD64)
4. ✅ Deploy an EC2 instance with a public IP and Bitnami NGINX AMI
5. ✅ Create a security group and attach ingress rules for ports 80 and 443
6. ✅ Access the NGINX welcome page via the instance's public IP
7. ✅ Understand in-place updates vs forced replacement (AMI change)
8. ✅ Use `lifecycle { create_before_destroy = true }` for zero-downtime replacement
9. ✅ Use `lifecycle { ignore_changes = [tags] }` to handle external tag drift
10. ✅ Use `terraform state list` and `terraform apply -destroy`
11. ✅ Understand professional validation and testing approaches for this infrastructure

---

## Concepts

### Terraform Resource Naming Conventions

When you have a single instance of a resource type, two conventions exist:

```hcl
resource "aws_vpc" "this" { ... }   # convention 1: "this"
resource "aws_vpc" "main" { ... }   # convention 2: "main" (preferred here)
resource "aws_vpc" "vpc"  { ... }   # acceptable: repeat type name
resource "aws_vpc" "vpc1" { ... }   # ❌ avoid: no semantic meaning
```

Use descriptive names when you have multiple instances of the same type:

```hcl
resource "aws_subnet" "public"  { ... }
resource "aws_subnet" "private" { ... }
```

---

### `locals` and the `merge()` Function

`locals` are internal variables — not input parameters, not outputs. They reduce code duplication and store intermediary computed values.

```hcl
locals {
  common_tags = {
    ManagedBy  = "Terraform"
    Project    = "06-resources-ec2-nginx"
    CostCenter = "1234"
  }
}
```

The `merge()` function combines two or more maps. Use it to apply common tags plus resource-specific tags without duplication:

```hcl
# Resource with only common tags
tags = local.common_tags

# Resource with common + specific tags
tags = merge(local.common_tags, {
  Name = "06-resources-ec2-nginx-public-subnet"
})
```

**Alternative: `provider "aws" { default_tags {} }`**

The AWS provider supports applying tags to all resources automatically:

```hcl
provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = "06-resources-ec2-nginx"
    }
  }
}
```

This removes the need to pass `local.common_tags` to every resource. The trade-off: tags applied via `default_tags` appear in the state under `tags_all`, not `tags` — which can cause minor confusion when reading the plan. Both approaches are valid; this demo uses `locals` for visibility.

---

```markdown
### Finding the Right AMI ID for Your Region in Console

AMI IDs are **region-specific** — the same image has a different ID in each AWS region.
Always ensure you are in the **correct region Console** before copying an AMI ID.

**Steps to find the Bitnami NGINX AMI ID (Console):**

1. Confirm your region in the top-right of the AWS Console (e.g., `US East (Ohio) us-east-2`)
2. Go to **EC2 → Instances → Launch instance**
3. Under **"Application and OS Images (Amazon Machine Image)"** → click **"Browse more AMIs"**
4. Click **"AWS Marketplace AMIs"** tab
5. Search `bitnami nginx`
6. Filter left panel: **Pricing Model → Free**
7. Find **"Bitnami package for Nginx Open Source"** → click **"Select"**
8. In the popup → click **"Subscribe now"**
9. After subscribing, AWS shows the AMI configuration page
10. Note the **Image ID** — e.g., `ami-06492140a3c4a3483`
11. Verify **Architecture: x86_64** ✅ — required for t3.micro
12. Click **Cancel** — do NOT launch from here, you only needed the AMI ID

> ⚠️ **Always verify Architecture is `x86_64`** before using the AMI ID.
> ARM64 AMIs require Graviton instance types and will fail with t3.micro.

> ⚠️ **The AMI ID shown is specific to your current Console region.**
> If you switch regions later, repeat these steps to get the correct AMI ID for that region.
```

![alt text](image-1.png)

---

### Finding the Right AMI ID for Your Region in CLI

**List AMI IDs for your region**

```bash
# List all your region's NGINX Marketplace AMIs
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters "Name=name,Values=*bitnami-nginx*" \
            "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images, &CreationDate)[-5:].{ID:ImageId,Name:Name,Date:CreationDate}' \
  --output table \
  --region us-east-2
```

**Identify architecture before using an AMI:**

```bash
aws ec2 describe-images \
  --image-ids ami-0YOUR_AMI_ID \
  --region us-east-2 \
  --query 'Images[*].{Name:Name,Arch:Architecture,Description:Description}' \
  --output table
```

**Expected:**
```
Architecture: x86_64
```
---

### Security Groups: `aws_security_group` vs Inline Rules

Two patterns exist for security group rules. This demo uses the **standalone rule resources** (recommended for Terraform ≥ 5.x AWS provider):

```hcl
# Pattern 1: standalone rule resources (recommended)
resource "aws_security_group" "public_http" { ... }

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.public_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

# Pattern 2: inline rules (older style, avoid mixing with standalone)
resource "aws_security_group" "public_http" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

> **Do not mix both patterns** for the same security group — it causes conflicts. Standalone rule resources are preferred as they allow independent management of each rule.

---

### In-Place Update vs Forced Replacement

Not all resource attribute changes are equal in Terraform:

| Change | Behavior | Downtime |
|---|---|---|
| Tags, security group IDs | In-place update (`~`) | None |
| AMI ID | Forced replacement (`-/+`) | Yes (default) or minimal (with lifecycle) |
| Instance type | Requires stop/start | Brief |
| VPC, subnet | Forced replacement | Yes |

**In-place update (`~`)** — AWS updates the attribute on the existing running
resource directly. The EC2 instance keeps the same instance ID, same public IP,
and continues running without interruption. Example: adding a tag or changing
a security group just updates the metadata — the instance itself is untouched.

**Forced replacement (`-/+`)** — AWS cannot modify this attribute on a running
resource. Terraform must destroy the existing instance and create a brand new
one. The new instance gets a new instance ID and a new public IP. Example:
changing the AMI ID requires a full replacement because AWS does not support
swapping the root image of a running instance.

When Terraform shows `-/+` in the plan output, always check what is
**forcing the replacement** — Terraform marks this clearly with
`# forces replacement` next to the changed attribute.

---

### Lifecycle Meta-Arguments

Every Terraform resource has a default behavior for how it is created, updated,
and destroyed. **Lifecycle meta-arguments** allow you to override this default
behavior for a specific resource when the defaults do not suit your needs.

They are defined inside a `lifecycle` block within the resource:
```hcl
resource "aws_instance" "web" {
  ami           = "ami-0xxxxxxxxx"
  instance_type = "t3.micro"

  lifecycle {
    create_before_destroy = true   # override destroy-first default
    ignore_changes        = [tags] # ignore external changes to tags
    prevent_destroy       = true   # block accidental destruction
  }
}
```

**Available lifecycle meta-arguments:**

| Argument | What it does |
|---|---|
| `create_before_destroy` | Creates replacement resource before destroying the old one — minimizes downtime. Without this: Terraform destroys the old instance → creates new one (gap in availability). |
| `ignore_changes` | Tells Terraform to ignore changes to specific attributes made outside Terraform.Use case: another team or automation tool adds tags to your EC2 instance. Without `ignore_changes`, Terraform would remove those external tags on the next apply. With it, Terraform ignores tag drift entirely. |
| `prevent_destroy` | Blocks `terraform destroy` on this resource — useful for critical resources like databases |
| `replace_triggered_by` | Forces replacement of this resource when another specified resource changes |

> Lifecycle meta-arguments apply **per resource** — you can have different
> lifecycle rules on different resources within the same configuration.

> **Best practice:** Minimize use of `ignore_changes`. It hides drift and can mask real configuration problems. Prefer having a single owner for each resource's attributes.

---

### State Refresh

Every `terraform plan`, `apply`, and `destroy` begins with a **state refresh** — Terraform queries the real AWS APIs to compare the current real state against what is recorded in `terraform.tfstate`. If there are differences (drift), Terraform calculates what changes are needed to reconcile them.

```
terraform apply
  │
  ├── 1. Refresh: fetch real resource state from AWS APIs
  ├── 2. Diff: compare real state vs desired config
  ├── 3. Plan: compute changes needed
  └── 4. Apply: execute changes
```

This is why if you add for instance a tag manually in the Console shows up as a drift in the next `terraform plan` — Terraform's refresh detected the difference.

---

## Directory Structure

```
06-resources-ec2-nginx/
├── README.md
└── src/
    ├── provider.tf      # Terraform block + AWS provider
    ├── networking.tf    # VPC, subnet, IGW, route table, locals
    ├── security.tf      # Security group + ingress rules
    └── compute.tf       # EC2 instance
```

---

## Implementation Steps

### Step 1: Create `provider.tf`

```hcl
terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}
```

Initialize the project:

```bash
terraform init
terraform version
# Verify both Terraform and AWS provider versions
```

---

### Step 2: Create `networking.tf` — VPC and Subnet

```hcl
locals {
  common_tags = {
    ManagedBy  = "Terraform"
    Project    = "06-resources-ec2-nginx"
    CostCenter = "1234"
  }
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-vpc"
  })
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = "10.0.0.0/24"

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-public"
  })
}
```

Apply and verify:

```bash
terraform fmt
terraform plan
terraform apply -auto-approve
```

**Verify in AWS Console:**

Navigate to **VPC → Your VPCs** — filter by tag `Project = 06-resources-ec2-nginx`. You should see:
- VPC with CIDR `10.0.0.0/16`
- Subnet with CIDR `10.0.0.0/24` under it
- A default route table (auto-created by AWS, not by Terraform)
- A resource map at the bottom of the VPC detail page
- Verify the tags 

---

### Step 3: Add Internet Gateway and Route Table to `networking.tf`

```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-igw"
  })
}

resource "aws_route_table" "public-rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-public-rtb"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
```

> **Note:** `aws_route_table_association` does not support `tags` — it is a relationship resource, not a standalone AWS resource.

Apply:

```bash
terraform fmt
terraform apply -auto-approve
```

**Verify in Console:**

VPC → Resource map → you should now see: VPC → Internet Gateway + Route Table → Subnet all connected.

---

### Step 4: Create `security.tf` — Security Group and Ingress Rules

```hcl
resource "aws_security_group" "public_http" {
  name        = "06-resources-ec2-nginx-public-http"
  description = "Allow HTTP and HTTPS inbound traffic from the internet"
  vpc_id      = aws_vpc.vpc.id

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.public_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
  description       = "Allow HTTP from internet"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.public_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
  description       = "Allow HTTPS from internet"
}
```

> **Why no egress rule?** By default, AWS security groups allow all outbound traffic. Without an explicit `aws_vpc_security_group_egress_rule`, outbound traffic is unrestricted — which is correct for a web server that needs to fetch packages, respond to requests, etc.

> **Why no SSH (port 22)?** Exposing port 22 publicly is a security risk. For production access, use **AWS Systems Manager Session Manager** instead — it requires no open inbound ports.

Apply:

```bash
terraform fmt
terraform apply -auto-approve
```

**Verify in AWS Console:**

1. Go to **EC2 → Network & Security → Security Groups**
2. Find `06-ec2-nginx-sg` in the Name column
3. Click on it
4. Click **"Inbound rules"** tab at the bottom
5. Verify you see two rules:

| Type | Protocol | Port | Source |
|---|---|---|---|
| HTTP | TCP | 80 | 0.0.0.0/0 |
| HTTPS | TCP | 443 | 0.0.0.0/0 |

6. Click **"Outbound rules"** tab — this will appear **empty** in the Console
   because no explicit egress rule was defined in Terraform. This is expected —
   AWS automatically allows all outbound traffic by default when no egress rules
   are defined. The EC2 instance can still reach the internet for outbound requests.

---

### Step 5: Find the Bitnami NGINX AMI ID for Your Region

**Via AWS Console (recommended — easiest):**

1. Go to **EC2 → Instances → Launch Instance**
2. Click **Browse more AMIs**
3. Select tab: **AWS Marketplace AMIs**
4. Search: `nginx`
5. Filter left panel: **Free** under Pricing Model
6. Find **"Bitnami package for Nginx"**
7. Click **Subscribe on Instance Launch**
8. Scroll down — the **AMI ID** is shown on this page
9. Copy it — this is your region-specific AMI ID

> ⚠️ **Critical:** Verify the architecture shown is **x86_64**, not arm64. Using an ARM64 AMI with a t3.micro instance type will fail.

**Via AWS CLI (alternative):**

```bash
aws ec2 describe-images \
  --owners aws-marketplace \
  --filters \
    "Name=name,Values=bitnami-nginx-*" \
    "Name=architecture,Values=x86_64" \
    "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-3:].{ID:ImageId,Name:Name,Date:CreationDate}' \
  --output table \
  --region us-east-2
```

Take the **most recent** (last row) AMI ID from the output.

**Verify your chosen AMI:**

```bash
aws ec2 describe-images \
  --image-ids ami-0YOUR_AMI_ID \
  --region us-east-2 \
  --query 'Images[*].{Name:Name,Arch:Architecture,Owner:OwnerId}' \
  --output table
```

---

### Step 6: Create `compute.tf` — EC2 Instance

```hcl
# NGINX AMI ID — replace with the AMI ID from Step 5 for your region
# ami_nginx  = "ami-0xxxxxxxxxxxxxx"  # Bitnami NGINX x86_64
# ami_ubuntu = "ami-0xxxxxxxxxxxxxx"  # Ubuntu 24.04 x86_64 (for reference)

resource "aws_instance" "web" {
  # MANDATORY — no default, Terraform errors without it
  ami = "ami-0YOUR_NGINX_AMI_ID"

  # MANDATORY — no default, Terraform errors without it
  instance_type = "t3.micro"

  # OPTIONAL — if omitted, AWS launches into the default subnet
  # of the default VPC in your region
  subnet_id = aws_subnet.public.id

  # OPTIONAL — defaults to false
  # If omitted, instance has no public IP and is unreachable from internet
  associate_public_ip_address = true

  # OPTIONAL — if omitted, AWS attaches the default security group
  # of the VPC automatically (allows only internal VPC traffic)
  vpc_security_group_ids = [aws_security_group.public_http.id]

  # OPTIONAL block — if omitted entirely, AWS applies these defaults:
  #   volume_size           = 8 GB
  #   volume_type           = gp2
  #   delete_on_termination = true
  root_block_device {
    # OPTIONAL — defaults to AMI's root volume size (varies per AMI)
    volume_size = 10

    # OPTIONAL — defaults to gp2 (older generation)
    # Explicitly setting gp3 gives better performance at same cost
    volume_type = "gp3"

    # OPTIONAL — defaults to true for root volumes
    # Best practice to explicitly set it to avoid confusion
    delete_on_termination = true
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, {
    Name = "06-ec2-nginx-web"
  })
}
```

Apply:

```bash
terraform fmt
terraform plan    # review carefully — 1 resource to add
terraform apply -auto-approve
```

**Expected output:**
```
aws_instance.web: Creating...
aws_instance.web: Still creating... [10s elapsed]
aws_instance.web: Still creating... [20s elapsed]
aws_instance.web: Creation complete after 32s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

---

**Get the public IP via Console:**

1. Go to **EC2 → Instances**
2. Find your instance named `06-resources-ec2-nginx-web`
3. Click on the Instance ID
4. Under **"Instance summary"** — copy the **Public IPv4 address**

Wait 1–2 minutes after `apply` completes for NGINX to fully initialize, then open in browser:
```
http://<PUBLIC_IP>
```

**Expected:** Bitnami NGINX welcome page loads successfully.

> If you see a browser certificate warning (`Your connection is not private`) when accessing via HTTPS — this is expected. The instance has no TLS certificate configured. Click **Advanced → Proceed** to confirm NGINX is running. The HTTP connection on port 80 will work without a warning.

---

### Step 8: Inspect All Managed Resources


#### `terraform state list`

Terraform maintains a **state file** (`terraform.tfstate`) that tracks every resource it manages. `terraform state list` reads this state file and prints all the resources currently tracked by your Terraform project:


**How to read the output:**

Each line follows the format `<resource_type>.<local_name>` — exactly matching
how the resource is declared in your `.tf` files:

**Expected output:**
```
aws_instance.web
│               │
│               └── local name from your resource block
└── resource type (AWS resource being managed)
```

**What it is useful for:**

- **Confirming** all expected resources were created successfully
- **Before destroying** — see exactly what will be removed
- **Troubleshooting** — check if a resource is tracked or orphaned
- **Before `terraform state show`** — get the exact resource address to inspect

To inspect full details of a specific resource from the list:
```bash
terraform state show aws_instance.web
# Shows every attribute Terraform knows about this resource —
# instance ID, public IP, AMI, tags, security groups, etc.
```

> `terraform state list` only reads the local state file — it does
> not make any API calls to AWS. It shows what Terraform believes
> exists, not necessarily what actually exists in AWS right now.
> Run `terraform refresh` first if you suspect drift.


```bash
terraform state list
```

**Expected output:**
```
aws_instance.web
aws_internet_gateway.main
aws_route_table.public
aws_route_table_association.public
aws_security_group.public_http
aws_subnet.public
aws_vpc.main
aws_vpc_security_group_ingress_rule.http
aws_vpc_security_group_ingress_rule.https
```

Nine resources — all managed by Terraform. Destroying any of them incorrectly without Terraform would leave orphaned dependencies.

```bash
# Inspect details of a specific resource
terraform state show aws_instance.web
```

---

### Step 9: Observe In-Place Update vs Forced Replacement

**In-place update example — add a tag:**

Add `Environment = "demo"` to the instance tags in `compute.tf`:

```hcl
tags = merge(local.common_tags, {
  Name        = "06-resources-ec2-nginx-web"
  Environment = "demo"
})
```

```bash
terraform plan
```

**Expected plan output:**
```
~ resource "aws_instance" "web" {
    ~ tags = {
        + "Environment" = "demo"
          ...
      }
}

Plan: 0 to add, 1 to change, 0 to destroy.
```

The `~` means in-place update — no replacement, no downtime.

**Forced replacement example — change the AMI:**

Change `ami` in `compute.tf` to any other valid AMI ID (e.g., swap back to Ubuntu):

```bash
terraform plan
```

**Expected plan output:**
```
~ resource "aws_instance" "web" {
    ~ ami = "ami-OLD" -> "ami-NEW" # forces replacement
}

Plan: 1 to add, 0 to change, 1 to destroy.
```

The `# forces replacement` note and `-/+` indicator means Terraform will destroy and recreate. With `create_before_destroy = true` in the lifecycle block, the new instance is created first, then the old one destroyed — minimizing the downtime window.

Revert the tag and  AMI  back to the NGINX AMI before continuing.

---

### Step 10: Handle External Tag Drift with `ignore_changes`

**Simulate external tag drift:**

In the AWS Console:
1. Go to **EC2 → Instances**
2. Select your instance → **Tags tab → Manage Tags**
3. Add tag: `Key=Team`, `Value=platform`
4. Save

Now run:

```bash
terraform plan
```

**Expected:** Terraform wants to remove the `Team` tag — it is not in the configuration.

**Solution — if the tag is managed externally and should be preserved:**

Add to the `lifecycle` block in `compute.tf`:

```hcl
lifecycle {
  create_before_destroy = true
  ignore_changes        = [tags]
}
```

```bash
terraform plan
# Expected: No changes. Your infrastructure matches the configuration.
```

> **When to use `ignore_changes`:** Only when another system (another team's Terraform, a cost-allocation tool, an auto-tagger Lambda) manages specific attributes of a resource you also manage. Prefer a single owner for all attributes of a resource where possible.

Revert: remove `ignore_changes` from the lifecycle block after this test.

---

## Cleanup

```bash
# View all resources before destroying
terraform state list

# Destroy all resources
terraform apply -destroy   # same as terraform destroy — shows plan first
# OR
terraform destroy

# Type: yes


**Verify destruction via Console:**

1. Go to **EC2 → Instances**
   - Your instance should show **"Terminated"** state
   - Terminated instances disappear from the list after a short period

2. Go to **VPC → Your VPCs**
   - Filter by tag `Project = 06-resources-ec2-nginx`
   - No VPC should appear — confirms VPC and all its dependencies
     (subnet, IGW, route table) were fully removed

3. Go to **EC2 → Network & Security → Security Groups**
   - Search for `06-ec2-nginx-sg`
   - Should not appear — confirms security group was removed

**Remove local Terraform files:**
```bash
rm -rf .terraform/ .terraform.lock.hcl
```

---

## What You Learned

In this demo, you:

- ✅ Built a complete AWS network stack from scratch with Terraform
- ✅ Used `locals` and `merge()` to manage tags without duplication
- ✅ Found the correct Bitnami NGINX AMI for your region (avoiding the ARM64 pitfall)
- ✅ Deployed an EC2 instance with a public IP and attached security group
- ✅ Accessed a live NGINX server deployed entirely via Terraform
- ✅ Observed the difference between in-place updates and forced replacement
- ✅ Used `lifecycle { create_before_destroy = true }` to minimize replacement downtime
- ✅ Used `lifecycle { ignore_changes = [tags] }` to handle external drift
- ✅ Used `terraform state list` and `terraform state show` to inspect managed resources
- ✅ Understood that `terraform apply -destroy` is equivalent to `terraform destroy`
- ✅ Validated infrastructure professionally at infrastructure, connectivity, and compliance layers

**Key Insight:** Real infrastructure is not just about creating resources — it is about managing their full lifecycle: creation, updates, replacement strategies, drift handling, and clean destruction. Terraform handles all of this consistently via a single declarative configuration.

---

## Lessons Learned

### 1. AMI IDs Are Region-Specific — Always Verify Architecture

The same Bitnami NGINX product has a different AMI ID in every region. Always retrieve the AMI for your specific region. Always verify the architecture is `x86_64` before using it with a `t3.micro` instance — ARM64 AMIs require Graviton instance types.

### 2. Always Run `terraform plan` Before `apply` in Production

`-auto-approve` is convenient in demos but dangerous in production. In CI/CD, always use `terraform plan -out=tfplan` + `terraform apply tfplan` — the saved plan guarantees what was reviewed is exactly what gets applied.

### 3. `create_before_destroy` Should Be Default for Stateful Compute

For any resource that serves live traffic (EC2, RDS, etc.), always set `create_before_destroy = true`. The default destroy-first behavior guarantees downtime during AMI or configuration replacements.

### 4. Tags Are Governance — Not Optional

In corporate environments, missing tags block deployments or trigger auto-remediation. Use `locals` + `merge()` or `provider default_tags` to ensure all resources carry required tags without repetition.


---

## Troubleshooting

**`UnsupportedOperation: The requested configuration is currently not supported`:**

You used an ARM64 AMI with a non-Graviton instance type. Verify AMI architecture


**Instance running but browser times out:**

Check the route table has a default route to the IGW:

Check the security group allows port 80 from `0.0.0.0/0`.

**NGINX not responding immediately after apply:**

Wait 1–2 minutes. The Bitnami image runs initialization scripts after the instance boots. Status checks in EC2 Console will show `2/2 checks passed` when ready.


**`terraform plan` shows unexpected changes after a `terraform apply`:**

This is drift — something changed the real resource outside Terraform. Run:

```bash
terraform refresh   # sync state with real resource state
terraform plan      # identify what drifted
```

---

## Common Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Initialize project and download providers |
| `terraform fmt` | Format all `.tf` files to canonical style |
| `terraform validate` | Validate configuration syntax |
| `terraform plan` | Show planned changes |
| `terraform apply -auto-approve` | Apply without confirmation prompt |
| `terraform apply -destroy` | Plan and destroy all resources (alias for destroy) |
| `terraform destroy` | Destroy all managed resources |
| `terraform state list` | List all resources tracked in state |
| `terraform state show <resource>` | Show full details of a specific resource |
| `terraform refresh` | Sync state file with real resource state |
