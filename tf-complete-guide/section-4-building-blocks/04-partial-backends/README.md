# Demo-04: Partial Backend Configurations

## Demo Overview

This demo builds directly on [Demo-03](../03-s3-backend/README.md) and explores **partial backend configurations** — a pattern used in real-world projects to separate environment-specific backend settings from the core Terraform configuration. Instead of hardcoding all backend values in `backend.tf`, you externalize them into `.tfbackend` files or pass them via CLI — enabling the same Terraform code to target different environments (dev, prod) without modifying any `.tf` files.

**What you'll do:**
- Understand why partial backend configuration is needed for multi-environment setups
- Externalize the full backend config into a `dev.s3.tfbackend` file and pass it via `-backend-config`
- Create a `prod.s3.tfbackend` file for a production environment
- Pass partial config as CLI key-value pairs (`-backend-config="key=value"`)
- Use `terraform plan -out` to save a plan file and apply it without confirmation
- Use `terraform apply -auto-approve` for non-interactive applies
- Understand the CI/CD use case for partial backend configurations

## Prerequisites

**From Previous Demo:**
- ✅ Completed [Demo-03: Remote Backends with AWS S3](../03-s3-backend/README.md)
- ✅ S3 state bucket already exists (`terraform-course-yourname-remote-backend-east-2`)
- ✅ Familiarity with `terraform init -migrate-state`

**Required Tools:**
- ✅ Terraform CLI `>= 1.14.4`
- ✅ AWS CLI `>= 2.32.1` configured (`aws configure`)
- ✅ AWS account with S3 permissions

**Verify Prerequisites:**


```bash
terraform version
# Expected: Terraform v1.14.4 or higher

aws sts get-caller-identity
# Expected: JSON with Account, UserId, Arn

aws configure get region
(or)
echo $AWS_REGION
# Expected: your target region (e.g., us-east-2)

aws s3 ls | grep terraform
# Expected: your state bucket from Demo-03 listed
```

---

## Demo Objectives

By the end of this demo, you will:

1. ✅ Understand what partial backend configuration is and why it exists
2. ✅ Externalize backend config into a `.tfbackend` file
3. ✅ Use `terraform init -backend-config=<file>` to pass a backend config file
4. ✅ Use `terraform init -backend-config="key=value"` to pass individual values via CLI
5. ✅ Understand how multiple `-backend-config` flags are merged
6. ✅ Create separate dev and prod backend config files
7. ✅ Use `terraform plan -out=<planfile>` to save a plan
8. ✅ Use `terraform apply <planfile>` to apply a saved plan without confirmation
9. ✅ Use `terraform apply -auto-approve` for non-interactive applies
10. ✅ Understand the CI/CD use case for this pattern

---

## Concepts

### What is Partial Backend Configuration?

In Demo-03, all backend settings were hardcoded directly in `backend.tf`:

```hcl
# Demo-03: Full backend config hardcoded
backend "s3" {
  bucket      = "terraform-course-yourname-remote-backend-east-2"
  key         = "03-s3-backend/state.tfstate"
  region      = "us-east-2"
  encrypt     = true
  use_lockfile = true
}
```

This works fine for a single environment. But what if you need the **same Terraform code** to deploy to both `dev` and `prod`, each with their own state file? Hardcoding means editing `.tf` files every time you switch — which breaks the principle of environment parity.

**Partial backend configuration** solves this by leaving some (or all) backend values out of `backend.tf` and supplying them externally at `terraform init` time:

```hcl
# Partial backend block — only shared values hardcoded
backend "s3" {
  encrypt     = true
  use_lockfile = true
  # bucket, key, region supplied externally
}
```

The missing values are then provided via:
- A **`.tfbackend` file** passed with `-backend-config=<path>`
- **CLI key-value pairs** passed with `-backend-config="key=value"`
- A combination of both

---

### `.tfbackend` File Convention

Backend config files use the `.tfbackend` extension by convention (not enforced by Terraform — any file works, but this is the standard). They contain only the key-value pairs that belong in the backend block, with no `terraform {}` wrapper:

```hcl
# dev.s3.tfbackend
bucket = "terraform-course-yourname-remote-backend-east-2"
key    = "04-partial-backends/dev/state.tfstate"
region = "us-east-2"
```

```hcl
# prod.s3.tfbackend
bucket = "terraform-course-yourname-remote-backend-east-2"
key    = "04-partial-backends/prod/state.tfstate"
region = "us-east-2"
```

These files are **environment-specific** and can be committed to version control (they contain no secrets — just bucket names, keys, and regions).

> ⚠️ **Never put credentials in `.tfbackend` files.** Use IAM roles or environment variables for authentication.

---

### Three Ways to Provide Partial Backend Config

| Method | Command | Best For |
|---|---|---|
| **Full config in `.tfbackend` file** | `terraform init -backend-config=dev.s3.tfbackend` | Per-environment files in CI/CD |
| **CLI key-value pairs** | `terraform init -backend-config="region=us-east-2"` | Overriding a single value |
| **Combination** | Both flags together | Shared values in `backend.tf`, env-specific via file or CLI |

Multiple `-backend-config` flags can be combined — Terraform **merges** them. Values in the backend block + all `-backend-config` sources are merged into the final configuration. If the same key appears in multiple sources, the last one wins.

```bash
# Example: merge partial backend.tf + file + CLI override
terraform init \
  -backend-config=dev.s3.tfbackend \
  -backend-config="region=us-west-2"
```

---

### Plan Files: `terraform plan -out`

By default, `terraform apply` re-runs a plan and asks for confirmation. In CI/CD pipelines this is a problem because:
- The plan shown in CI and the plan applied must be **identical** (no drift between plan and apply)
- Interactive confirmation (`yes/no`) is not possible in automated pipelines

**Solution: save the plan to a file and apply it directly.**

```bash
# Save plan to a file
terraform plan -out=dev_plan

# Apply the saved plan — no confirmation prompt, no re-plan
terraform apply dev_plan
```

The saved plan file is **binary** — not human-readable. It contains the exact set of changes Terraform will make, locked at the moment the plan was created. Applying it guarantees no drift.

> ⚠️ **Plan files can contain sensitive data** (resource attributes, credentials passed to providers). Treat them like state files — do not commit to version control.

---

### `terraform apply -auto-approve`

For cases where you want to apply without a saved plan file but also without the confirmation prompt:

```bash
terraform apply -auto-approve
```

This re-runs the plan internally and applies immediately without asking for `yes`. Useful for:
- `terraform destroy` in CI/CD cleanup jobs
- Demo/learning environments where you trust the outcome

> ⚠️ **Use with caution in production.** Always prefer the `plan -out` + `apply <planfile>` pattern in real CI/CD pipelines — it gives you a reviewable plan step before apply.

---

### CI/CD Use Case

This is the primary reason partial backend configurations exist. A typical CI/CD pipeline looks like:

```
┌─────────────────────────────────────────────────┐
│  CI/CD Pipeline Run (e.g., GitLab CI / GitHub   │
│  Actions)                                       │
│                                                 │
│  Step 1: terraform init                         │
│    -backend-config=environments/dev.s3.tfbackend│
│                                                 │
│  Step 2: terraform plan -out=tfplan             │
│                                                 │
│  Step 3: (manual approval gate — optional)      │
│                                                 │
│  Step 4: terraform apply tfplan                 │
└─────────────────────────────────────────────────┘
```

The same Terraform code runs for both dev and prod — only the `-backend-config` flag changes between pipeline runs. The `.tf` files are never modified.

---

### Architecture

```
Same Terraform Code
        │
        ├── terraform init -backend-config=dev.s3.tfbackend
        │         │
        │         ▼
        │   S3: 04-partial-backends/dev/state.tfstate
        │   (dev environment state)
        │
        └── terraform init -backend-config=prod.s3.tfbackend
                  │
                  ▼
            S3: 04-partial-backends/prod/state.tfstate
            (prod environment state)
```

---

## Directory Structure

```
04-partial-backends/
├── README.md
└── src/
    ├── main.tf                  # Provider block + demo resource
    ├── backend.tf               # Partial backend block (shared values only)
    ├── dev.s3.tfbackend         # Dev environment backend config
    └── prod.s3.tfbackend        # Prod environment backend config
```

> **Note:** `.tfbackend` files are **not** Terraform configuration files — Terraform does not auto-load them. They must be explicitly passed via `-backend-config`. They are kept in the `src/` directory for convenience but could also live in an `environments/` or `config/` subdirectory.

---

## Part A: Set Up the Project

### Step 1: Create Project Structure

```bash
cp -r 03-s3-backend/ 04-partial-backends/
cd 04-partial-backends/src/

# Clean up from previous demo
rm -rf .terraform/ .terraform.lock.hcl
```

---

### Step 2: Create `main.tf`

```hcl
provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "demo" {
  bucket = "my-demo-bucket-yourname-12345"
}
```

---

### Step 3: Create a Partial `backend.tf`

Remove the environment-specific values (`bucket`, `key`, `region`) and keep only the shared settings:

```hcl
terraform {
  required_version = "~> 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.30.0"
    }
  }
  backend "s3" {
    encrypt     = true
    use_lockfile = true
    # bucket, key, and region are supplied via -backend-config at init time
  }
}
```

> Terraform allows an **empty backend block** (`backend "s3" {}`) — all values supplied externally. You can also keep some values hardcoded (like `encrypt` and `use_lockfile`) and externalize only the environment-specific ones. Both approaches are valid.

---

## Part B: Backend Config Files

### Step 4: Create `dev.s3.tfbackend`

```hcl
bucket = "terraform-course-yourname-remote-backend-east-2"
key    = "04-partial-backends/dev/state.tfstate"
region = "us-east-2"
```

### Step 5: Create `prod.s3.tfbackend`

```hcl
bucket = "terraform-course-yourname-remote-backend-east-2"
key    = "04-partial-backends/prod/state.tfstate"
region = "us-east-2"
```

> Both files point to the **same S3 bucket** but different `key` paths — dev and prod state are isolated from each other within the same bucket.

---

## Part C: Initialize with Dev Backend Config File

### Step 6: Init with `-backend-config` File

```bash
terraform init -backend-config=dev.s3.tfbackend
```

**Expected output:**
```
Initializing the backend...

Successfully configured the backend "s3"! Terraform will automatically
use this backend unless the backend configuration changes.

Terraform has been successfully initialized!
```

Terraform merges `dev.s3.tfbackend` values with the partial `backend.tf` block to produce the complete backend configuration.

---

### Step 7: Create a Saved Plan for Dev

```bash
terraform plan -out=dev_plan
```

**Expected output:**
```
Terraform used the selected providers to generate the following execution plan.

  + resource "aws_s3_bucket" "demo" {
      + bucket = "my-demo-bucket-yourname-12345"
      ...
    }

Plan: 1 to add, 0 to change, 0 to destroy.

Saved the plan to: dev_plan
```

> The `dev_plan` file is binary — not human-readable. It captures the exact changes to be made.

---

### Step 8: Apply the Saved Plan

```bash
terraform apply dev_plan
```

**Expected output:**
```
aws_s3_bucket.demo: Creating...
aws_s3_bucket.demo: Creation complete after 2s

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

No confirmation prompt — applying a saved plan file is always non-interactive.

**Verify dev state in S3:**

```bash
aws s3 ls s3://terraform-course-yourname-remote-backend-east-2/ --recursive
```

**Expected:**
```
2026-02-21 10:00:00   2712  04-partial-backends/dev/state.tfstate
```

✅ **Dev state written to its own isolated key path.**

---

## Part D: Switch to Prod Backend Config File

### Step 9: Destroy Dev Resources First

```bash
terraform destroy -auto-approve
```

> Using `-auto-approve` here since this is a demo environment and we are confident in the outcome. In production always use `plan -out` + `apply <planfile>`.

---

### Step 10: Init with Prod Backend Config File

```bash
terraform init -backend-config=prod.s3.tfbackend -migrate-state
```

**Expected output:**
```
Initializing the backend...
Backend configuration changed!

...

Do you want to copy existing state to the new backend?
  Enter a value: yes

Successfully configured the backend "s3"!
```

Type `yes` — this copies the (now empty) state to the prod key path.

**Verify both paths now exist in S3:**

```bash
aws s3 ls s3://terraform-course-yourname-remote-backend-east-2/ --recursive
```

**Expected:**
```
2026-02-21 10:00:00    181  04-partial-backends/dev/state.tfstate
2026-02-21 10:05:00    181  04-partial-backends/prod/state.tfstate
```

Both paths exist — dev state (empty after destroy) and prod state (initialized).

---

### Step 11: Apply to Prod

```bash
terraform plan -out=prod_plan
terraform apply prod_plan
```

**Verify prod state:**

```bash
aws s3 ls s3://terraform-course-yourname-remote-backend-east-2/ --recursive
```

**Expected:**
```
2026-02-21 10:00:00    181  04-partial-backends/dev/state.tfstate
2026-02-21 10:10:00   2712  04-partial-backends/prod/state.tfstate
```

✅ **Dev and prod states are fully isolated — same code, different state paths.**

---

## Part E: Partial Config via CLI Key-Value Pairs

Instead of a `.tfbackend` file, individual values can be passed directly on the command line. This is useful for overriding a single value or in environments where files are not convenient (e.g., passing secrets from a vault via environment).

### Step 12: Pass Backend Config as Key-Value Pairs

First destroy prod resources:

```bash
terraform destroy -auto-approve
```

Then re-init passing each backend value individually:

```bash
terraform init \
  -backend-config="bucket=terraform-course-yourname-remote-backend-east-2" \
  -backend-config="key=04-partial-backends/dev/state.tfstate" \
  -backend-config="region=us-east-2" \
  -migrate-state
```

**Expected:** Same successful init output as before.

> Each `-backend-config="key=value"` flag supplies one backend argument. Multiple flags are merged in order. This achieves the same result as the `.tfbackend` file — just inline instead.

**Combining file and CLI key-value pair:**

```bash
# Shared values in dev.s3.tfbackend, override region via CLI
terraform init \
  -backend-config=dev.s3.tfbackend \
  -backend-config="region=us-west-2" \
  -migrate-state
```

Terraform merges all sources — CLI value overrides the file value for `region`.

---

## Part F: Cleanup

### Step 13: Destroy All Resources and Clean S3

```bash
# Destroy all Terraform-managed resources
terraform destroy -auto-approve

# Remove dev and prod state paths from S3
aws s3 rm s3://terraform-course-yourname-remote-backend-east-2/04-partial-backends/ --recursive

# Verify cleanup
aws s3 ls s3://terraform-course-yourname-remote-backend-east-2/ --recursive
# Expected: no 04-partial-backends/ objects remain

# Remove local Terraform files
rm -rf .terraform/ .terraform.lock.hcl dev_plan prod_plan
```

---

## What You Learned

In this demo, you:

- ✅ Understood why partial backend configuration is needed for multi-environment setups
- ✅ Created `.tfbackend` files for dev and prod environments
- ✅ Used `terraform init -backend-config=<file>` to pass a backend config file
- ✅ Used `terraform init -backend-config="key=value"` to pass individual backend values via CLI
- ✅ Understood that multiple `-backend-config` sources are merged by Terraform
- ✅ Used `terraform plan -out=<planfile>` to save a plan
- ✅ Applied a saved plan with `terraform apply <planfile>` — no confirmation prompt
- ✅ Used `terraform apply -auto-approve` for non-interactive applies
- ✅ Understood the CI/CD use case: same code, different `-backend-config` per environment

**Key Insight:** Partial backend configuration is what makes a single Terraform codebase deployable to multiple environments. The `.tf` files never change — only the backend config file passed at `terraform init` time. This is the foundation for environment promotion patterns in CI/CD pipelines.

---

## Lessons Learned

### 1. The `backend.tf` Block Can Be Completely Empty

Terraform allows `backend "s3" {}` with no values at all — everything supplied externally. This is the most flexible approach for CI/CD but requires discipline: whoever runs `terraform init` must always provide the correct `-backend-config`.

### 2. Plan Files Are Not Human-Readable — and That Is By Design

`terraform plan -out=dev_plan` creates a binary file. This is intentional — the binary format prevents tampering. If you need a human-readable version, use:

```bash
terraform show dev_plan
```

### 3. `-auto-approve` vs Saved Plan Files

| Method | Re-plans? | Confirmation? | Best For |
|---|---|---|---|
| `terraform apply` | ✅ Yes | ✅ Yes | Local development |
| `terraform apply -auto-approve` | ✅ Yes | ❌ No | Demo / destroy in CI |
| `terraform apply <planfile>` | ❌ No (uses saved plan) | ❌ No | Production CI/CD |

In real CI/CD, always use `plan -out` + `apply <planfile>`. This ensures what was reviewed is exactly what gets applied — no drift between plan and apply steps.

### 4. `.tfbackend` Files Are Not Auto-Loaded

Unlike `*.tf` and `*.tfvars` files, `.tfbackend` files are **never auto-loaded** by Terraform. They must always be explicitly passed via `-backend-config=<path>`. If you forget the flag, Terraform will either use only the partial values in `backend.tf` (and fail if required values are missing) or prompt you interactively.

### 5. Switching Environments Locally Is Not the Intended Use Case

On a local machine, switching between dev and prod backends by re-running `terraform init` with different `-backend-config` flags works but is cumbersome. The real use case is CI/CD — each pipeline run starts fresh with `terraform init`, and the environment is determined by which config file the pipeline passes. Locally, consider using **Terraform Workspaces** (Demo-05) for environment switching.

---

## Improvements Over the Course Demo

| Improvement | Why |
|---|---|
| **`encrypt = true` and `use_lockfile = true` kept in partial `backend.tf`** | These are not environment-specific — keep shared security settings in code |
| **Separate `dev_plan` and `prod_plan` files** | Makes it explicit which plan belongs to which environment |
| **`terraform show <planfile>` documented** | Plan files are binary — this is the correct way to read them |
| **`-auto-approve` vs `plan -out` comparison table** | Makes the production vs demo use cases explicit |
| **CI/CD pipeline pattern documented** | Connects the concept to real-world usage |

---

## Next Steps

**Demo-05: Terraform Workspaces**
- Use `terraform workspace new dev` / `terraform workspace new prod` to manage environments
- Each workspace gets its own isolated state automatically — no manual key path management
- Compare: partial backend configs (CI/CD pattern) vs workspaces (local switching pattern)

---

## Troubleshooting

**`Error: Backend configuration changed` on every `terraform init`:**

This happens because the backend config is supplied externally — Terraform detects a change each time. Always add `-migrate-state` or `-reconfigure` when switching between environments:

```bash
terraform init -backend-config=dev.s3.tfbackend -migrate-state
```

**`Error: Invalid backend configuration argument` — unknown key:**

Check that your `.tfbackend` file contains only valid S3 backend arguments. Common mistake: using `backend "s3" { ... }` wrapper inside the `.tfbackend` file. It should contain only bare key-value pairs:

```hcl
# Correct
bucket = "my-bucket"
key    = "path/state.tfstate"
region = "us-east-2"

# Wrong — do not wrap in backend block
backend "s3" {
  bucket = "my-bucket"
}
```

**`terraform apply dev_plan` fails with `"the provided plan file was created by a different Terraform version"`:**

The plan file is tied to the exact Terraform version that created it. Use the same version for plan and apply. Check with `terraform version`.

**Plan file applied but changes are different from what was planned:**

This should not happen — saved plan files guarantee exact reproducibility. If you see this, you likely ran `terraform apply` (without the plan file) instead of `terraform apply dev_plan`.

---

## Common Commands Reference

| Command | Description |
|---|---|
| `terraform init -backend-config=<file>` | Init with backend config from a `.tfbackend` file |
| `terraform init -backend-config="key=value"` | Init with a single backend config value via CLI |
| `terraform init -backend-config=<file> -migrate-state` | Init with new backend config and migrate existing state |
| `terraform init -backend-config=<file> -reconfigure` | Init with new backend config, discard old state link |
| `terraform plan -out=<planfile>` | Run plan and save to a binary plan file |
| `terraform apply <planfile>` | Apply a saved plan file — no re-plan, no confirmation |
| `terraform apply -auto-approve` | Apply with auto-confirmation — no saved plan, re-plans internally |
| `terraform destroy -auto-approve` | Destroy with auto-confirmation |
| `terraform show <planfile>` | Display a saved plan file in human-readable form |
| `terraform show` | Display current state in human-readable form |
| `terraform init` | Initialize project with backend from `backend.tf` |
| `terraform init -migrate-state` | Re-init and migrate state to new backend config |
| `terraform init -reconfigure` | Re-init and discard old backend state link |
| `aws s3 ls s3://<bucket>/ --recursive` | List all current objects in bucket |
| `aws s3 rm s3://<bucket>/<prefix>/ --recursive` | Delete all objects under a prefix |