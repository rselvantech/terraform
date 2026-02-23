# Demo-05: Working with Terraform Providers

## Demo Overview

This demo dives deeper into **Terraform providers** — how they work, how they are named, how to configure multiple instances of the same provider for multi-region deployments, and how provider versioning works. Providers are Terraform's plugin layer that enables it to interact with remote APIs like AWS, GCP, and Azure.

**What you'll do:**
- Understand the provider plugin architecture and why naming conventions matter
- Break provider naming intentionally to understand the local name rule
- Configure two instances of the AWS provider targeting different regions using `alias`
- Deploy resources to multiple AWS regions from a single Terraform configuration
- Use `terraform version` to inspect installed provider versions
- Change version constraints and use `terraform init -upgrade` to update providers
- Understand the `.terraform.lock.hcl` dependency lock file

## Prerequisites

**From Previous Demos:**
- ✅ Completed [Demo-03: Remote Backends](../03-s3-backend/README.md)
- ✅ Completed [Demo-04: Partial Backend Configurations](../04-partial-backends/README.md)

**Required Tools:**
- ✅ Terraform CLI `>= 1.14.4`
- ✅ AWS CLI `>= 2.32.x` configured (`aws configure`)
- ✅ AWS account with S3 permissions in at least two regions

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

1. ✅ Understand what Terraform providers are and how they fit into the plugin architecture
2. ✅ Understand why the provider local name must match the resource type prefix
3. ✅ See what happens when the local name does NOT match (intentional break)
4. ✅ Configure a default provider and an aliased provider for a second region
5. ✅ Explicitly assign an aliased provider to a resource using `provider = aws.<alias>`
6. ✅ Deploy resources to two AWS regions from a single configuration
7. ✅ Use `terraform version` to see installed provider versions
8. ✅ Change version constraints and use `terraform init -upgrade` to install updated versions
9. ✅ Understand the role of `.terraform.lock.hcl`

---

## Concepts

### What is a Terraform Provider?

Terraform Core by itself cannot create or manage any cloud resources. It has no built-in knowledge of AWS, GCP, Azure, or any other platform. **Providers** are plugins that bridge this gap — each provider adds a set of resource types and data sources that Terraform can manage.

```
┌──────────────────┐        ┌──────────────────┐        ┌──────────────────┐
│  Terraform Core  │───────▶│  AWS Provider    │───────▶│  AWS APIs        │
│                  │        │  (Plugin)        │        │  (EC2, S3, etc.) │
│  Plan / Apply    │        │  hashicorp/aws   │        │                  │
│  State Mgmt      │        │  v5.x.x          │        │                  │
└──────────────────┘        └──────────────────┘        └──────────────────┘
```

**Key properties:**
- Providers are developed and maintained **separately from Terraform Core** — anyone can write a provider for any API
- They are downloaded at `terraform init` time from the Terraform Registry
- Each provider version is pinned in `.terraform.lock.hcl` for reproducibility
- Provider configuration belongs to the **root module** — child modules receive provider config from their parent

---

### The Provider Local Name Rule

When declaring a provider in `required_providers`, you give it a **local name**:

```hcl
terraform {
  required_providers {
    aws = {                      # ← "aws" is the local name
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

This local name is critical — Terraform uses it to:
1. Match the `provider "aws" {}` configuration block
2. Match the prefix of every resource type that uses this provider (`aws_s3_bucket`, `aws_instance`, etc.)

**The local name must match the resource type prefix.** If you name it anything else, Terraform cannot automatically associate the provider with its resources.

```hcl
# ❌ Wrong — local name "whatever" does not match "aws_s3_bucket" prefix
terraform {
  required_providers {
    whatever = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "whatever" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "demo" { # ← Terraform looks for provider "aws", not "whatever"
  bucket = "my-bucket"
}
```

**What happens:** Terraform will complain that `aws_s3_bucket` requires a provider named `aws` but only finds `whatever`. It may try to implicitly install `hashicorp/aws` as a second provider, causing conflicts.

**Best practice:** Always use the last segment of the provider source as the local name:
- `hashicorp/aws` → local name `aws`
- `hashicorp/google` → local name `google`
- `hashicorp/azurerm` → local name `azurerm`

---

### Multiple Provider Instances with `alias`

Sometimes you need to deploy resources to **multiple regions** or **multiple accounts** using the same provider. Terraform supports this via provider **aliases**.

```hcl
# Default provider — used when no provider is explicitly specified
provider "aws" {
  region = "us-east-2"
}

# Aliased provider — must be explicitly referenced
provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
}
```

**Rules:**
- A provider block **without** `alias` = the **default** provider for that type
- A provider block **with** `alias` = must be explicitly referenced in each resource that uses it
- Resources that do not specify a `provider` argument automatically use the default provider

```hcl
# Uses default provider → deploys to us-east-2
resource "aws_s3_bucket" "bucket_default" {
  bucket = "my-bucket-us-east-2"
}

# Uses aliased provider → deploys to us-east-1
resource "aws_s3_bucket" "bucket_useast1" {
  bucket   = "my-bucket-us-east-1"
  provider = aws.useast1    # ← explicit reference using aws.<alias>
}
```

Think of providers like class constructors — same source and version, but instantiated with different parameters (region, credentials, etc.).

---

### Provider Versioning and the Lock File

**Version constraints in `required_providers`** define what versions are acceptable:

| Constraint | Meaning |
|---|---|
| `~> 5.0` | `>= 5.0, < 6.0` — any patch/minor within major 5 |
| `~> 5.94` | `>= 5.94, < 6.0` — any patch within 5.94+ |
| `>= 5.0` | Anything 5.0 or higher |
| `< 5.0` | Anything below 5.0 |
| `= 5.94.0` | Exactly this version |

**`.terraform.lock.hcl`** — the dependency lock file:
- Created automatically by `terraform init`
- Records the **exact version** of each provider installed (not the constraint — the resolved version)
- Should be **committed to version control** so all team members and CI/CD use identical provider versions
- Unlike `.terraform/` (which should be gitignored), the lock file is safe and encouraged to commit

**`terraform init -upgrade`** — needed when you change version constraints:
- Normal `terraform init` respects the lock file and installs the locked version
- `-upgrade` ignores the lock file and installs the newest version that satisfies the updated constraint
- Always run `terraform init -upgrade` after changing `version` in `required_providers`

```bash
# After changing version constraint in required_providers:
terraform init -upgrade
# Then verify:
terraform version
```

---

### `terraform version`

Shows both the Terraform CLI version and the **currently installed provider versions**:

```
Terraform v1.10.x
on darwin_arm64
+ provider registry.terraform.io/hashicorp/aws v5.100.0
```

The provider version shown is the **effective installed version** — the result of resolving your constraint against available versions and the lock file. It is not the constraint string from your config.

---

## Directory Structure

```
05-providers/
├── README.md
└── src/
    └── providers.tf    # All configuration in one file (provider + resources)
```

> This demo uses a single `providers.tf` file to keep all provider-related config together. In larger projects, you would typically split resources into separate files by service or concern.

---

## Part A: The Provider Local Name Rule

### Step 1: Create `providers.tf` with Intentionally Wrong Local Name

First, let's break it intentionally to understand the rule:

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    whatever = {                 # ← intentionally wrong local name
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "whatever" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "demo" {
  bucket = "my-demo-bucket-yourname-12345"
}
```

### Step 2: Init and Observe the Error

```bash
terraform init
terraform plan
```

**Expected output (error):**
```
│ Error: Invalid provider configuration
│
│ The resource "aws_s3_bucket.demo" requires a provider named "aws" but
│ the provider "whatever" has a different local name in the required_providers
│ block. Either rename the local name in required_providers to match or
│ explicitly assign the provider to this resource.
```

Terraform uses the `aws_` prefix of `aws_s3_bucket` to look for a provider named `aws` in `required_providers`. It finds `whatever` instead and cannot make the association automatically.

---

### Step 3: Fix — Use the Correct Local Name

Update `providers.tf` to follow best practice:

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {                      # ← matches "aws_s3_bucket" prefix and source name
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "demo" {
  bucket = "my-demo-bucket-yourname-12345"
}
```

```bash
terraform init
terraform plan
```

**Expected output:**
```
Plan: 1 to add, 0 to change, 0 to destroy.
```

✅ **Provider local name correctly matches resource prefix.**

---

## Part B: Multiple Provider Instances with `alias`

### Step 4: Add a Second Provider Instance for a Different Region

Update `providers.tf` to add a second AWS provider targeting `us-east-1`:

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider — no alias — used by resources that don't specify a provider
provider "aws" {
  region = "us-east-2"
}

# Aliased provider — must be explicitly referenced in each resource
provider "aws" {
  alias  = "useast1"
  region = "us-east-1"
}

# Uses default provider → deploys to us-east-2
resource "aws_s3_bucket" "bucket_useast2" {
  bucket = "my-demo-bucket-yourname-us-east-2"
}

# Uses aliased provider → deploys to us-east-1
resource "aws_s3_bucket" "bucket_useast1" {
  bucket   = "my-demo-bucket-yourname-us-east-1"
  provider = aws.useast1    # ← references the aliased provider
}
```

> **Note:** Both provider blocks use the **same source and version** (`hashicorp/aws ~> 5.0`). The alias doesn't create a different provider — it creates a second instance of the same provider configured differently (different region).

---

### Step 5: Apply and Verify Multi-Region Deployment

```bash
terraform apply -auto-approve
```

**Expected output:**
```
aws_s3_bucket.bucket_useast2: Creating...
aws_s3_bucket.bucket_useast1: Creating...
aws_s3_bucket.bucket_useast2: Creation complete
aws_s3_bucket.bucket_useast1: Creation complete

Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
```

**Verify in AWS Console:**

Navigate to **S3** and check bucket regions:

```
my-demo-bucket-yourname-us-east-2  →  US East (Ohio)      us-east-2  ✅
my-demo-bucket-yourname-us-east-1  →  US East (N. Virginia) us-east-1  ✅
```

Two buckets, two regions, one Terraform configuration.

**Verify via CLI:**

```bash
aws s3api get-bucket-location \
  --bucket my-demo-bucket-yourname-us-east-2
# Expected: "LocationConstraint": "us-east-2"

aws s3api get-bucket-location \
  --bucket my-demo-bucket-yourname-us-east-1
# Expected: "LocationConstraint": null  ← us-east-1 returns null by AWS convention
```

> **AWS quirk:** `us-east-1` returns `null` for `LocationConstraint` — this is expected AWS API behavior, not an error. The bucket is in `us-east-1`.

✅ **Resources deployed to two regions from a single Terraform configuration.**

---

## Part C: Provider Versioning

### Step 6: Check Installed Provider Version

```bash
terraform version
```

**Expected output:**
```
Terraform v1.10.x
on darwin_arm64
+ provider registry.terraform.io/hashicorp/aws v5.100.0
```

The provider version shown (`v5.100.0`) is the **resolved installed version** — the newest version satisfying `~> 5.0` at the time of `terraform init`. This may differ from what you see depending on when you run it.

---

### Step 7: Change the Version Constraint and Observe

First destroy existing resources:

```bash
terraform destroy -auto-approve
```

Change the version constraint in `providers.tf` to force an older version:

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "< 5.0"           # ← changed from "~> 5.0"
  }
}
```

Try running `terraform plan` without re-initializing:

```bash
terraform plan
```

**Expected error:**
```
│ Error: Required plugins are not installed
│
│ The following required plugins are not installed:
│   - hashicorp/aws (~> 5.0 -> < 5.0): there is no package for
│     registry.terraform.io/hashicorp/aws 5.100.0 cached in .terraform
│
│ Please run "terraform init" to install the missing plugins.
```

Terraform detects the constraint changed and refuses to proceed.

---

### Step 8: Upgrade Provider with `-upgrade`

```bash
terraform init -upgrade
```

**Expected output:**
```
Initializing provider plugins...
- Finding hashicorp/aws versions matching "< 5.0"...
- Installing hashicorp/aws v4.67.0...
- Installed hashicorp/aws v4.67.0 (signed by HashiCorp)

Terraform has made some changes to the provider dependency selections recorded
in .terraform.lock.hcl. Review those changes and commit them to your
version control system.
```

```bash
terraform version
```

**Expected:**
```
Terraform v1.10.x
+ provider registry.terraform.io/hashicorp/aws v4.67.0   ← downgraded
```

---

### Step 9: Restore the Original Constraint

Change `providers.tf` back to `~> 5.0`:

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"           # ← restored
  }
}
```

Without `-upgrade`, `terraform init` will use the lock file (which now has `v4.67.0`):

```bash
terraform version
# Still shows v4.67.0 — lock file takes precedence
```

Run with `-upgrade` to resolve to the latest `~> 5.0` version:

```bash
terraform init -upgrade
terraform version
# Now shows v5.x.x again
```

> **Key lesson:** Changing the constraint in `required_providers` alone is not enough — you must run `terraform init -upgrade` to actually install the updated version and update the lock file.

---

### Step 10: Inspect the Lock File

```bash
cat .terraform.lock.hcl
```

**Expected output:**
```hcl
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.100.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:...",
    "zh:...",
  ]
}
```

The lock file records:
- The **exact resolved version** (`5.100.0`)
- The **constraint** that was applied (`~> 5.0`)
- **Cryptographic hashes** for integrity verification

**Commit this file to version control** — it ensures everyone on the team installs the exact same provider version.

---

## Cleanup

```bash
# Destroy all resources
terraform destroy -auto-approve

# Remove local Terraform files
rm -rf .terraform/

# Keep .terraform.lock.hcl — commit this to version control
```

---

## What You Learned

In this demo, you:

- ✅ Understood that Terraform Core has no built-in cloud knowledge — providers are plugins that add this
- ✅ Understood that the provider local name in `required_providers` must match the resource type prefix
- ✅ Observed the error that occurs when the local name does not match
- ✅ Configured two instances of the AWS provider using `alias` for multi-region deployments
- ✅ Used `provider = aws.<alias>` to explicitly assign an aliased provider to a resource
- ✅ Deployed resources to two AWS regions from a single Terraform configuration
- ✅ Used `terraform version` to inspect installed provider versions
- ✅ Changed version constraints and used `terraform init -upgrade` to install updated versions
- ✅ Understood the role of `.terraform.lock.hcl` and why it should be committed to version control

**Key Insight:** Providers are Terraform's extensibility mechanism — any platform with a remote API can have a Terraform provider. The aliasing system makes multi-region and multi-account deployments straightforward from a single configuration, while version pinning via the lock file ensures reproducible infrastructure across teams and CI/CD runs.

---

## Lessons Learned

### 1. Always Use the Source Name as the Local Name

The local name in `required_providers` should always be the last segment of the source path. This is a convention enforced in practice by Terraform's resource prefix matching:

```hcl
# Source: hashicorp/aws → local name: aws
# Source: hashicorp/google → local name: google
# Source: hashicorp/azurerm → local name: azurerm
```

### 2. Default vs Aliased Providers

A provider without `alias` is the default — used by all resources that don't explicitly specify a `provider` argument. If you only configure aliased providers (no default), every resource must explicitly reference a provider or Terraform will error.

### 3. Changing Version Constraints Requires `terraform init -upgrade`

Normal `terraform init` respects the lock file. If you change a version constraint, the lock file still wins until you explicitly run `terraform init -upgrade`. This is by design — it prevents unexpected provider updates from breaking your configuration.

### 4. The Lock File Is Not Optional

`.terraform.lock.hcl` is not a generated artifact to ignore — it is a critical part of your project. Commit it to version control. Without it, different team members or CI/CD runs may install different provider versions, leading to inconsistent behavior.

### 5. `us-east-1` Returns `null` for `get-bucket-location`

This is an AWS API quirk — `us-east-1` is AWS's default region and predates the `LocationConstraint` concept. A `null` response from `get-bucket-location` means `us-east-1`, not an error.

---

## Improvements Over the Course Demo

| Improvement | Why |
|---|---|
| **Intentional break documented step-by-step** | Makes the local name rule concrete and memorable |
| **`aws.useast1` alias naming convention** | Uses a clear, consistent naming pattern for aliases |
| **AWS `get-bucket-location` verification** | Confirms multi-region deployment via CLI, not just Console |
| **`us-east-1` null quirk documented** | Prevents confusion when verifying bucket location |
| **Lock file contents shown and explained** | Connects `terraform init -upgrade` to what actually changes on disk |
| **Upgrade → downgrade → restore sequence** | Shows the full versioning lifecycle, not just one direction |

---

## Next Steps

**Demo-06: Terraform Variables**
- Input variables (`variable {}`) for parameterizing configurations
- Variable types, defaults, and validation
- Passing variables via CLI, `.tfvars` files, and environment variables
- Output values (`output {}`) for exposing resource attributes

---

## Troubleshooting

**`Error: Duplicate provider configuration`:**

You have two `provider "aws" {}` blocks without an `alias` on one of them. Terraform allows only one default (non-aliased) provider per type. Ensure exactly one block has no `alias`:

```hcl
provider "aws" { region = "us-east-2" }           # ← default (no alias)
provider "aws" { alias = "useast1"; region = "..." } # ← aliased
```

**`Error: Missing required argument` — alias not specified:**

You referenced `provider = aws.something` but no provider block with `alias = "something"` exists. Check the alias name matches exactly.

**Provider version not updating after changing constraint:**

Run `terraform init -upgrade` — normal `terraform init` respects the existing lock file and will not update the provider version even if the constraint changed.

**`terraform plan` fails after version constraint change:**

This is expected — Terraform detects a mismatch between the installed version and the new constraint. Run `terraform init -upgrade` to resolve.

---

## Common Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Initialize project; download providers per lock file |
| `terraform init -upgrade` | Re-initialize and upgrade providers to latest version matching constraints |
| `terraform version` | Show Terraform CLI version and all installed provider versions |
| `terraform plan` | Show planned changes without applying |
| `terraform apply -auto-approve` | Apply changes without confirmation prompt |
| `terraform destroy -auto-approve` | Destroy all resources without confirmation |
| `terraform fmt` | Format `.tf` files to canonical HCL style |
| `aws s3api get-bucket-location --bucket <name>` | Get the AWS region of an S3 bucket |
| `cat .terraform.lock.hcl` | Inspect the dependency lock file |