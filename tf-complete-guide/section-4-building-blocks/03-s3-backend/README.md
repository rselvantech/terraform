# Demo-03: Terraform Remote Backends with AWS S3

## Demo Overview

This demo migrates Terraform state from a local backend to a **remote backend using AWS S3**, then walks through backend key migration, state locking, and stale state cleanup. Remote backends are foundational for any team-based or CI/CD Terraform workflow — they centralize state, enable collaboration, and prevent corruption from concurrent runs.

**What you'll do:**
- Create an S3 bucket manually to solve the bootstrap problem
- Configure the S3 backend block with `bucket`, `key`, `region`, `encrypt`, and `use_lockfile`
- Create a real AWS resource so state is non-empty before migration
- Migrate state between two S3 key paths using `terraform init -migrate-state`
- Observe exactly what happens in S3 (CLI vs Console) after migration
- Understand S3 Versioning behavior and its impact on state visibility
- Clean up stale state left behind after migration

## Prerequisites

**Required Tools:**
- ✅ Terraform CLI `>= 1.14.4` 
- ✅ AWS CLI `>= 2.32.x` configured (`aws configure`)
- ✅ AWS account with S3 permissions

**Knowledge Requirements:**
- ✅ Basic Terraform concepts: `init`, `plan`, `apply`, `destroy`
- ✅ Completion of previous demos (01–02) covering providers and local state

**Verify Prerequisites:**

```bash
# Verify Terraform version
terraform version
# Expected: Terraform v1.10.x or higher

# Verify AWS CLI and credentials
aws sts get-caller-identity
# Expected: JSON with your Account, UserId, Arn

# Verify default region
aws configure get region
(or)
echo $AWS_REGION
# Expected: us-east-2 (or your chosen region)
```

---

## Demo Objectives

By the end of this demo, you will:

1. ✅ Understand what a Terraform backend is and why remote backends are essential
2. ✅ Understand the chicken-and-egg bootstrapping problem
3. ✅ Configure the S3 backend block correctly
4. ✅ Understand the difference between the S3 bucket region and the AWS provider region
5. ✅ Understand why a `provider` block must be explicit when using a remote backend
6. ✅ Migrate state between two S3 key paths using `terraform init -migrate-state`
7. ✅ Understand exactly what happens in S3 after migration (CLI vs Console view)
8. ✅ Understand S3 Versioning behavior and delete markers
9. ✅ Clean up stale state files after migration

---

## Concepts

### What is a Terraform Backend?

A **Terraform backend** defines where Terraform stores its state file (`terraform.tfstate`). By default, Terraform uses a **local backend** writing state to disk.

```
# Default (local backend)
./terraform.tfstate
```

The **S3 backend** stores state as an S3 object:

```
# S3 remote backend
s3://your-bucket/path/to/state.tfstate
```

**Why remote backends matter:**

| Concern | Local Backend | S3 Remote Backend |
|---|---|---|
| Team collaboration | ❌ State conflicts | ✅ Single source of truth |
| CI/CD pipelines | ❌ No persistent state | ✅ Consistent across runs |
| State locking | ❌ None | ✅ Prevents concurrent corruption |
| Durability | ❌ Local file loss risk | ✅ S3 11-nines durability |
| Versioning / recovery | ❌ None | ✅ S3 Versioning enables rollback |
| Encryption | ❌ Plaintext on disk | ✅ Server-side encryption |

When there is no `backend` block configured, Terraform defaults to the **local backend** — fine for solo learning, problematic for anything else.

---

### The Chicken-and-Egg Bootstrap Problem

To use a remote backend, you need an S3 bucket. But to create infrastructure with Terraform, you need a backend. This creates a circular dependency:

```
Terraform needs S3 bucket → to store state
S3 bucket needs Terraform → to be created
```

**Common solutions:**

| Approach | When to Use |
|---|---|
| **Create S3 bucket manually** (this demo) | Simplest; good for learning and small teams |
| **Bootstrap Terraform project** | Separate `bootstrap/` config with local state that creates the bucket, then migrates to it |
| **AWS CloudFormation / CDK** | Create state infrastructure entirely outside Terraform |
| **Terraform module** (e.g., `cloudposse/terraform-aws-tfstate-backend`) | Reusable module handling the full bootstrapping lifecycle |

For this demo, we create the bucket manually via the AWS Console — the fastest path to understanding backend configuration without extra complexity.

---

### S3 Backend Configuration

```hcl
terraform {
  required_version = "~> 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket      = "terraform-course-yourname-remote-backend-east-2"
    key         = "03-s3-backend/state.tfstate"
    region      = "us-east-2"
    encrypt     = true
    use_lockfile = true
  }
}
```

**Key arguments:**

| Argument | Purpose |
|---|---|
| `bucket` | Name of the S3 bucket (must already exist) |
| `key` | Object path within the bucket for the state file |
| `region` | Region where the S3 bucket lives |
| `encrypt` | Enable server-side encryption (AES-256) |
| `use_lockfile` | S3 native state locking (Terraform ≥ 1.10) — recommended |
| `dynamodb_table` | DynamoDB locking (legacy — deprecated, avoid for new projects) |

---



### Critical: Two Different `region` Arguments

There are **two separate `region` values** in a Terraform configuration and they are completely independent:

```hcl
terraform {
  backend "s3" {
    region = "us-east-2"    # ← Region where your STATE BUCKET lives
  }
}

provider "aws" {
  region = "us-east-2"      # ← Region where your INFRASTRUCTURE is deployed
}
```

Your S3 state bucket can be in `us-east-1` while infrastructure deploys in `eu-west-1`. This is intentional in multi-account architectures with a centralized state account.

---

### Always Define an Explicit `provider` Block

When no `provider "aws"` block is defined, Terraform silently falls back to your **AWS CLI default region**. This is fine on your laptop but breaks in CI/CD pipelines or other machines with different CLI defaults.

```hcl
# Always add this — never rely on CLI defaults
provider "aws" {
  region = "us-east-2"
}
```

---

### State Locking

State locking prevents two Terraform processes from modifying state simultaneously (race conditions), which can corrupt your state file.

**Evolution of S3 backend locking:**

| Method | How it works | Status |
|---|---|---|
| DynamoDB table (`dynamodb_table`) | Creates a lock item in a DynamoDB table | **Deprecated** as of Terraform 1.10+ |
| S3 native (`use_lockfile = true`) | Creates a `.tflock` file in the same S3 bucket | **Recommended** — no extra AWS resource needed |

[AWS Prescriptive Guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html) now recommends Amazon S3 native state locking (available since Terraform 1.10.0) over DynamoDB-based locking, which is considered a legacy approach that will be removed in future Terraform versions.

**How S3-native locking works:**

```
terraform apply
  │
  ├─ Terraform writes a lock file:  state.tfstate.tflock  (in same S3 path)
  │    Uses S3 conditional writes (If-None-Match header)
  │    If lock file already exists → returns error → prevents concurrent run
  │
  ├─ Runs plan + apply
  │
  └─ Deletes lock file → releases lock
```

No DynamoDB table needed. No extra AWS resource. No extra cost.

---

### S3 Versioning and State Visibility — Important Behavior

When **S3 Versioning is enabled** (recommended), every write to a state key creates a new version. This has important implications for how you observe state in S3:

| View | What You See |
|---|---|
| `aws s3 ls --recursive` | **Current live objects only** — no delete markers, no old versions |
| AWS Console (Show versions OFF) | Same as CLI — current live objects only |
| AWS Console (Show versions ON) | **All versions + delete markers** — full history |

**What is a Delete Marker?**

When you delete an S3 object in a versioning-enabled bucket, S3 does **not** actually remove the data. Instead it adds a **Delete marker** — a special version that hides the object from normal views. The actual data versions remain and are visible only with "Show versions" ON.

This means **"emptying" a versioning-enabled bucket via the Console or `aws s3 rm`** does not truly delete the data — it only adds delete markers. To permanently remove all data you must explicitly delete all versions.

---

### What Actually Happens During `terraform init -migrate-state`

This is the key behavior confirmed through real demo observation:

**Before migration:**
```
S3 bucket:
  03-s3-backend/state.tfstate    ← active state (has real resources)
```

**After changing `key` in backend.tf and running `terraform init -migrate-state`:**
```
S3 bucket:
  03-s3-backend/state.tfstate          ← OLD key — now STALE (Terraform no longer uses this)
  remote/03-s3-backend/state.tfstate   ← NEW key — ACTIVE (Terraform reads/writes here)
```

**Terraform copies state to the new key path — it never deletes the old one.**

Both objects are visible via `aws s3 ls --recursive` and in the AWS Console (without needing "Show versions"):

```bash
aws s3 ls s3://your-bucket/ --recursive
# Output:
# 2026-02-20 23:32:51   2712  03-s3-backend/state.tfstate
# 2026-02-20 23:40:44   2712  remote/03-s3-backend/state.tfstate
```

> **Important:** The `yes/no` migration confirmation prompt only appears when state is **non-empty** (i.e., you have real resources). If state is empty, Terraform skips the prompt and silently initializes the new key. This is why creating a real resource before migration is important for observing the full behavior.

---

### Architecture

```
┌─────────────────────────────────┐
│  Developer / CI/CD Pipeline     │
│  terraform init                 │
│  terraform apply                │
└──────────────┬──────────────────┘
               │
┌──────────────▼──────────────────┐
│  Terraform CLI                  │
│                                 │
│  1. Read backend config         │
│  2. Acquire lock (.tflock → S3) │
│  3. Read current state          │
│  4. Apply changes               │
│  5. Write updated state         │
│  6. Release lock                │
└──────────────┬──────────────────┘
               │
    ┌──────────┴──────────┐
    ▼                     ▼
┌──────────────┐   ┌──────────────────────┐
│  AWS S3      │   │  AWS Provider        │
│  State Bucket│   │  Deploy Region       │
│  (lock +     │   │                      │
│   state)     │   │  aws_s3_bucket etc.  │
└──────────────┘   └──────────────────────┘
```

---

## Directory Structure

```
03-s3-backend/
├── README.md
└── src/
    ├── main.tf        # Provider block + demo resource (aws_s3_bucket)
    └── backend.tf     # Terraform block with S3 backend configuration
```

> **Best Practice:** Keep the `backend` block in a dedicated `backend.tf`. This makes it easy to find, review, and change independently from resource definitions.

---

## Part A: Create the S3 State Bucket Manually

### Step 1: Create the S3 Bucket

Ensure you are logged in to the AWS Console in your chosen region (e.g., `eu-west-1`). Although S3 is a global service, **buckets are bound to a specific region** — confirm your region before creating.

Navigate to **S3 → Create bucket** in the AWS Console.

**Configuration:**

| Field | Value |
|---|---|
| **Bucket type** | General purpose (default) |
| **Bucket name** | A globally unique name, e.g., `terraform-course-yourname-remote-backend` |
| **Object Ownership** | ACLs disabled (default) |
| **Block Public Access** | ✅ Block all public access (keep enabled) |
| **Bucket Versioning** | **Enable** ← strongly recommended |
| **Encryption type** | SSE-S3 or SSE-KMS (enable encryption) 
| **Bucket key** | Enable (default) 


Create the bucket and copy the bucket name for use in the next step.

**Verify via CLI:**

```bash
aws s3 ls | grep terraform
# Expected: your bucket name listed
```

---

## Part B: Write the Terraform Configuration

### Step 2: Create `backend.tf`

```hcl
terraform {
  required_version = "~> 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket      = "terraform-course-yourname-remote-backend-east-2"
    key         = "03-s3-backend/state.tfstate"
    region      = "us-east-2"
    encrypt     = true
    use_lockfile = true
  }
}
```

> **What does `encrypt = true` actually do?**
>
> `encrypt = true` enables **server-side encryption (SSE-S3)** — it encrypts the state file
> **at rest on AWS's storage infrastructure**. It does NOT prevent authorized IAM users from
> reading the file. If you have `s3:GetObject` permission on the bucket, you can always open
> and read the `.tfstate` file — AWS decrypts it transparently for you.
>
> | What it protects against | What it does NOT protect |
> |---|---|
> | Physical access to AWS storage media | IAM users with `s3:GetObject` permission |
> | AWS compliance requirements (SOC2, HIPAA) | Anyone with valid bucket access credentials |
>
> **The real protection for sensitive state data is IAM** — restrict who has `s3:GetObject`
> on the state bucket using bucket policies and IAM roles. `encrypt = true` is a compliance
> and defence-in-depth measure, not access control.

### Step 3: Create `main.tf`

```hcl
provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "demo" {
  bucket = "my-demo-bucket-yourname-12345"
}
```

> **Why add a real resource?** If state is empty, `terraform init -migrate-state` skips the confirmation prompt and you won't observe the full migration behavior. A real resource ensures state is non-empty before migration.

---

## Part C: Initialize and Apply

### Step 4: Initialize with S3 Backend

```bash
terraform init
```

**Expected output:**
```
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Terraform has been successfully initialized!
```

**Verify bucket is still empty:**

```bash
aws s3 ls s3://terraform-course-yourname-remote-backend-east-2/
# Expected: no output (empty bucket)
```

---

### Step 5: Apply and Verify State is Remote

```bash
terraform apply
# Type: yes
```

**Expected:**
```
aws_s3_bucket.demo: Creating...
aws_s3_bucket.demo: Creation complete after 2s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

**Verify state is written to S3:**

```bash
aws s3 ls s3://terraform-course-yourname-remote-backend-east-2/ --recursive
```

**Expected:**
```
2026-02-20 23:32:51   2712  03-s3-backend/state.tfstate
```

**No local `.tfstate` file exists** — state is entirely remote.

```bash
ls | grep tfstate
# Expected: no output
```

✅ **State is in S3. Real resource created.**

---

## Part D: Migrate State to a New Key Path

### Step 6: Change the `key` in `backend.tf`

Update the `key` argument to simulate a path rename or project restructure:

```hcl
backend "s3" {
  bucket      = "terraform-course-yourname-remote-backend-east-2"
  key         = "remote/03-s3-backend/state.tfstate"   # changed
  region      = "us-east-2"
  encrypt     = true
  use_lockfile = true
}
```

---

### Step 7: Detect the Backend Change

```bash
terraform init
```

**Expected output:**
```
╷
│ Error: Backend configuration changed
│
│ A change in the backend configuration has been detected, which may
│ require migrating existing state.
│
│ If you wish to attempt automatic migration of the state, use
│ "terraform init -migrate-state".
│ If you wish to store the current configuration with no changes to
│ the state, use "terraform init -reconfigure".
╵
```

Terraform detects the key change and refuses to proceed without an explicit decision.

---

### Step 8: Migrate State

```bash
terraform init -migrate-state
```

**Expected output:**
```
Initializing the backend...
Backend configuration changed!

Terraform has detected that the configuration specified for the backend
has changed. Terraform will now check for existing state in the backends.

Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "s3" backend
  to the newly configured "s3" backend. No existing state was found in
  the newly configured "s3" backend. Do you want to copy this state to
  the new backend? Enter a value:
```

Type `yes`.

```
Successfully configured the backend "s3"!
```

> **Note:** The `yes/no` prompt only appears because state is **non-empty** (it contains `aws_s3_bucket.demo`). If state were empty, Terraform would skip this prompt silently. This is why creating a real resource in Step 3 matters.

---

### Step 9: Verify Migration in S3

**CLI view — shows both objects (old and new key):**

```bash
aws s3 ls s3://terraform-course-yourname-remote-backend-east-2/ --recursive
```

**Expected:**
```
2026-02-20 23:32:51   2712  03-s3-backend/state.tfstate
2026-02-20 23:40:44   2712  remote/03-s3-backend/state.tfstate
```

**Console view (Show versions OFF) — same, two folders visible:**

```
03-s3-backend/    ← Folder (old key — stale)
remote/           ← Folder (new key — active)
```

**Key observations:**
- Terraform **copied** state to the new key — it did **not** delete the old one
- Both objects are **immediately visible** in CLI and Console without needing "Show versions"
- `03-s3-backend/state.tfstate` is now **stale** — Terraform no longer reads or writes to it
- `remote/03-s3-backend/state.tfstate` is now **active**

**Confirm active state is correct:**

```bash
terraform plan
# Expected: No changes — your resource still tracked correctly in new key
```

> **"Show versions" in Console** is only needed to see version history and delete markers — it is not needed to see the two separate key paths after migration. Both paths are visible in normal view.

---

## Part E: Clean Up Stale State

### Step 10: Understand the Risk

The old `03-s3-backend/state.tfstate` is now disconnected from your Terraform project. However it still contains the full state of your infrastructure at the time of migration — resource IDs, metadata, and any sensitive outputs. It will never be automatically cleaned up by Terraform.

**Rule: After every backend migration, explicitly delete the old key path.**

---

### Step 11: Delete the Stale State File

```bash
aws s3 rm s3://terraform-course-yourname-remote-backend-east-2/03-s3-backend/state.tfstate
```

> **With versioning enabled:** `aws s3 rm` adds a **delete marker** rather than permanently removing the data. Old versions remain accessible via "Show versions" in the Console. 

**Verify only the active key remains:**

```bash
aws s3 ls s3://terraform-course-yourname-remote-backend-east-2/ --recursive
# Expected:
# 2026-02-20 23:40:44   2712  remote/03-s3-backend/state.tfstate
```

✅ **Stale state cleaned up.**

---

## Cleanup

```bash
# Destroy all Terraform-managed resources
terraform destroy
# Type: yes

# Delete all objects in state bucket (adds delete markers if versioning is on)
aws s3 rm s3://terraform-course-yourname-remote-backend-east-2/ --recursive

# To truly empty a versioned bucket, delete the bucket entirely
aws s3 rb s3://terraform-course-yourname-remote-backend-east-2 --force

# Remove local Terraform files
rm -rf .terraform/ .terraform.lock.hcl
```

---

## What You Learned

In this demo, you:

- ✅ Understood why remote backends are essential for team and CI/CD workflows
- ✅ Understood the chicken-and-egg bootstrapping problem
- ✅ Configured an S3 backend with `bucket`, `key`, `region`, `encrypt`, and `use_lockfile`
- ✅ Understood that the S3 bucket region and AWS provider region are independent
- ✅ Understood why an explicit `provider` block is required
- ✅ Migrated state between two S3 key paths using `terraform init -migrate-state`
- ✅ Observed that migration produces **two separate S3 objects** — old key is not deleted
- ✅ Understood S3 Versioning behavior — delete markers vs permanent deletion
- ✅ Understood that `aws s3 ls --recursive` shows current objects; "Show versions" shows full history
- ✅ Cleaned up stale state left behind after migration

**Key Insight:** Terraform treats your state file as a critical artifact — it never deletes state automatically, even during migration. This protects against data loss but means **you are responsible for cleaning up stale state paths** after every migration.

---

## Lessons Learned

### 1. Always Enable S3 Bucket Versioning

 In any real project, **always enable versioning**. Without it, accidental state deletion has no recovery path.


### 2. Create a Real Resource Before Demonstrating Migration

With empty state, `terraform init -migrate-state` skips the confirmation prompt silently. You won't observe the full behavior. Always have a real resource in state before migrating so the `yes/no` prompt triggers and you can observe what Terraform copies.

### 3. Terraform Copies, Never Deletes, During Migration

`terraform init -migrate-state` copies state to the new key. The old key remains as a separate S3 object — fully visible in CLI and Console. You must manually delete it.

### 4. `aws s3 rm` vs Permanent Deletion on Versioned Buckets

On a versioning-enabled bucket:
- `aws s3 rm <key>` → adds a **delete marker** (object hidden but data remains)
- `aws s3api delete-object --version-id <id>` → **permanently removes** a specific version

### 5. Always Define an Explicit `provider` Block

Without it, Terraform uses the AWS CLI default region silently. This works locally but breaks in CI/CD. Make the deploy region explicit in code.

---

## Improvements Over the Course Demo

| Improvement | Why |
|---|---|
| **S3 bucket versioning enabled** | State recovery from accidental deletion or corruption |
| **`encrypt = true`** | State encrypted at rest (AES-256) |
| **`use_lockfile = true`** | S3 native locking — no DynamoDB dependency |
| **Explicit `provider "aws"` block** | Deploy region explicit in code, not dependent on CLI defaults |
| **Real resource created before migration** | Triggers proper `yes/no` prompt; shows true migration behavior |
| **Separate `backend.tf` file** | Clean separation from resource definitions |
| **Stale state deletion documented** | Covers both `aws s3 rm` (delete marker) and permanent version deletion |

---

## Next Steps

**Demo-04: Terraform Workspaces**
- Use `terraform workspace` to manage multiple environments (dev, staging, prod) from a single configuration
- Each workspace automatically gets its own state file key in S3
- Compare workspaces vs separate Terraform projects for environment isolation

---

## Troubleshooting

**`NoSuchBucket` during `terraform init`:**
```bash
aws s3 ls | grep your-bucket-name
# If missing, create the bucket first (Part A)
```

**`AccessDenied` during `terraform init`:**

Minimum required S3 permissions:
- `s3:ListBucket` on the bucket
- `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on `bucket/key-prefix/*`

**`Error acquiring the state lock`:**
```bash
# View current lock
aws s3 cp s3://your-bucket/your-key.tfstate.tflock -

# Force-unlock (only if you are certain no apply is running)
terraform force-unlock <LOCK_ID>
```

**Migration prompt not appearing (empty state):**

This is expected — Terraform skips the prompt when there is nothing to copy. Create a real resource first, then re-test migration.

**Old key still visible after `aws s3 rm` (versioning enabled):**

`aws s3 rm` only adds a delete marker. Use `aws s3api delete-object --version-id` to permanently remove specific versions. See Step 11.

---

## Common Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Initialize project; configure backend |
| `terraform init -migrate-state` | Initialize and migrate state to new backend/key |
| `terraform init -reconfigure` | Reconfigure backend without migrating state |
| `terraform apply` | Apply changes; read/write state to configured backend |
| `terraform destroy` | Destroy resources; update remote state |
| `terraform fmt` | Format `.tf` files to canonical HCL style |
| `terraform show` | Display current state in human-readable form |
| `terraform state list` | List all resources in state |
| `terraform state show <resource>` | Show details of a specific resource |
| `terraform force-unlock <LOCK_ID>` | Release a stuck state lock |
| `aws s3 ls s3://<bucket>/` | List top-level objects/prefixes in bucket |
| `aws s3 ls s3://<bucket>/ --recursive` | List all current (live) objects in bucket |
| `aws s3 cp s3://<bucket>/<key> -` | Print S3 object content to stdout |
| `aws s3 rm s3://<bucket>/<key>` | Delete object (adds delete marker if versioning on) |
| `aws s3 rm s3://<bucket>/ --recursive` | Delete all current objects (adds delete markers if versioning on) |
| `aws s3 rb s3://<bucket> --force` | Delete bucket and all versions permanently |
| `aws sts get-caller-identity` | Verify current AWS credentials and account |