# Demo-07: S3 Static Website

## Demo Overview

This demo deploys a **fully functional static website hosted on AWS S3** using
Terraform. Everything is managed by Terraform — bucket creation, public access
configuration, bucket policy, website configuration, and HTML file uploads.
No manual steps in the AWS Console for resource creation.

**What you'll build:**

```
Browser
    │  HTTP
    ▼
┌─────────────────────────────────────────┐
│  S3 Bucket                              │
│  terraform-project01-<random_hex>   │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  Static Website Configuration   │    │
│  │  index document: index.html     │    │
│  │  error document: error.html     │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Objects (uploaded via Terraform):      │
│  ├── index.html                         │
│  └── error.html                         │
│                                         │
│  Bucket Policy: public read (GetObject) │
│  Public Access Block: disabled          │
└─────────────────────────────────────────┘
    │
    ▼
Output: website_endpoint (Terraform output)
```

**Resources created (6 total):**
- `random_id` — unique bucket name suffix (from `hashicorp/random` provider)
- `aws_s3_bucket` — the static website bucket
- `aws_s3_bucket_public_access_block` — disables all public access restrictions
- `aws_s3_bucket_policy` — allows anyone to read objects (`s3:GetObject`)
- `aws_s3_bucket_website_configuration` — configures index and error documents
- `aws_s3_object` × 2 — uploads `index.html` and `error.html` via Terraform

**Terraform concepts introduced:**
- Multiple providers in one project (`aws` + `random`)
- `random_id` resource for unique, stable resource name suffixes
- `jsonencode()` function for inline IAM policy definition
- `aws_s3_bucket_policy` with ARN reference
- `etag = filemd5()` — detect local file changes and trigger re-upload
- `output` block and `outputs.tf` — expose values from Terraform
- `terraform output <key>` command
- `depends_on` — explicit dependency for race condition handling
- Destroy order — Terraform manages object deletion before bucket deletion

## Prerequisites

**From Previous Demos:**
- ✅ Completed [Demo-03: Remote Backends](../03-s3-backend/README.md)
- ✅ Completed [Demo-05: Providers](../05-providers/README.md)

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
```

---

## Demo Objectives

By the end of this demo, you will:

1. ✅ Understand why S3 bucket names must be globally unique and how `random_id` solves this
2. ✅ Configure the `random` provider alongside the `aws` provider
3. ✅ Disable S3 public access block — understanding all four settings
4. ✅ Write an S3 bucket policy using `jsonencode()` inline
5. ✅ Configure S3 static website hosting with index and error documents
6. ✅ Upload HTML files to S3 via `aws_s3_object` with `etag = filemd5()`
7. ✅ Expose the website endpoint using an `output` block
8. ✅ Use `terraform output` to retrieve values programmatically
9. ✅ Understand `depends_on` for explicit dependency declaration
10. ✅ Understand how Terraform handles destroy order for dependent resources

---

## Concepts

### Why S3 Bucket Names Must Be Globally Unique

S3 bucket names share a **single global namespace across all AWS accounts and
all regions**. A bucket named `my-website` cannot be created if any other AWS
account in the world already owns that name. This makes hardcoded bucket names
fragile — they will fail if someone else has already taken the name.

**Solution: append a random suffix using `random_id`**

```hcl
resource "random_id" "bucket_suffix" {
  byte_length = 4   # 4 bytes = 8 hex characters
}

resource "aws_s3_bucket" "static_website" {
  bucket = "terraform-project01-${random_id.bucket_suffix.hex}"
}
```

The `hex` attribute produces a padded hexadecimal string — always **twice as
long** as `byte_length`. With `byte_length = 4`, you get 8 hex characters
(e.g., `a3f2c19b`), making the full bucket name unique and reproducible.

**`random_id` is stable** — once generated and stored in state, the value does
not change on subsequent `terraform apply` runs unless you explicitly change
the `byte_length` or `keepers`. This is intentional — Terraform needs
predictable infrastructure, not randomness on every run.

---

### The `random` Provider

`random` is a separate provider from `hashicorp` that generates random values
managed by Terraform state. It requires no API credentials — it runs locally.

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.30.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.8.1"
    }
  }
}
```

Both providers are listed under `required_providers`. `terraform init`
downloads both. No `provider "random" {}` block is needed — the random
provider requires no configuration.

---

### S3 Public Access Block — Four Settings

By default, AWS applies aggressive public access restrictions to all S3
buckets. For a static website, all four must be explicitly disabled:

```hcl
resource "aws_s3_bucket_public_access_block" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  block_public_acls       = false  # allow public ACLs to be set
  block_public_policy     = false  # allow public bucket policies
  ignore_public_acls      = false  # do not ignore public ACLs
  restrict_public_buckets = false  # do not restrict public access
}
```

| Argument | Default (AWS) | Set to | Reason |
|---|---|---|---|
| `block_public_acls` | `true` | `false` | Allow public ACLs |
| `block_public_policy` | `true` | `false` | Allow the public read policy |
| `ignore_public_acls` | `true` | `false` | Respect public ACLs |
| `restrict_public_buckets` | `true` | `false` | Allow public bucket access |

> **All four must be `false`** — setting even one to `true` will block public
> access and make the website unreachable.

---

### `jsonencode()` for Inline IAM Policies

IAM policies in AWS are JSON documents. Terraform's `jsonencode()` function
lets you write the policy in HCL map/list syntax and converts it to JSON at
apply time — no need to write raw JSON strings or heredocs.

```hcl
resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.static_website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"           # anyone
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_website.arn}/*"
      }
    ]
  })
}
```

**Why `s3:GetObject` only?**
- `GetObject` — retrieve a specific object (what browsers do when loading a page) ✅
- `ListBucket` — list all objects in the bucket (not needed, would expose all file names) ❌
- `PutObject` — write to the bucket (never expose this publicly) ❌

**Why use the bucket `arn` attribute?**

Using `aws_s3_bucket.static_website.arn` is cleaner and safer than manually
constructing the ARN string. Terraform retrieves the exact ARN from the
created resource — no risk of typos.

---

### `etag = filemd5()` — Detecting File Changes

When uploading files to S3 via `aws_s3_object`, Terraform needs to know when
the local file has changed so it can re-upload it. The `etag` argument
combined with `filemd5()` achieves this:

```hcl
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static_website.id
  key          = "index.html"
  source       = "build/index.html"
  content_type = "text/html"
  etag         = filemd5("build/index.html")
}
```

`filemd5()` computes the **MD5 hash of the local file** and stores it in
Terraform state. On every `terraform plan`, Terraform recomputes the hash
and compares it to the stored value. If the file changed, the hash changes,
Terraform detects a diff and re-uploads the file.

**Without `etag`** — Terraform would only re-upload if the resource
definition itself changed (e.g., the `key` or `bucket`). Editing the HTML
content alone would not trigger a re-upload.

> **Official docs note:** `etag` is not compatible with KMS encryption or
> objects larger than 16 MB (multipart upload). For those cases, use
> `source_hash = filemd5("path/to/file")` instead.

---

### `output` Block and `outputs.tf`

Terraform `output` blocks expose values from your configuration — making them
visible after `apply` and accessible to other tools, pipelines, or Terraform
projects.

```hcl
output "website_endpoint" {
  value = aws_s3_bucket_website_configuration.static_website.website_endpoint
}
```

**Best practice:** put all outputs in a dedicated `outputs.tf` file.

After `terraform apply`, outputs are printed automatically. Retrieve them
individually with:

```bash
terraform output website_endpoint
```

This is especially useful in **CI/CD pipelines** — the website URL can be
passed to a later pipeline step (e.g., a smoke test or notification) without
anyone needing to navigate the AWS Console.

---

### `depends_on` — Explicit Dependencies

Terraform automatically infers dependencies from resource references. When
resource A references `resource_B.id`, Terraform knows to create B before A.
This is called an **implicit dependency**.

Sometimes the dependency exists but is not expressed through a reference —
for example, a bucket policy requires the public access block to be applied
first, but it does not directly reference it. In these cases, you can declare
an **explicit dependency** with `depends_on`:

```hcl
resource "aws_s3_bucket_policy" "public_read" {
  bucket     = aws_s3_bucket.static_website.id
  policy     = jsonencode({ ... })
  depends_on = [aws_s3_bucket_public_access_block.static_website]
}
```

This guarantees the public access block is fully applied before Terraform
attempts to set the bucket policy — preventing the race condition that can
produce an `AccessDenied` error even with correct IAM permissions.

---

### Destroy Order — Terraform Handles Object Deletion

AWS does not allow deleting an S3 bucket that still contains objects. If you
manually upload files to a bucket managed by Terraform and then run
`terraform destroy`, it will fail — Terraform cannot delete the bucket
because the manually uploaded files are not tracked in state.

**When files are uploaded via `aws_s3_object`:**
Terraform tracks the objects in state and automatically deletes them before
attempting to delete the bucket. The destroy order is:

```
terraform destroy
  │
  ├── 1. Destroy aws_s3_object.index          (object deleted first)
  ├── 2. Destroy aws_s3_object.error          (object deleted first)
  ├── 3. Destroy aws_s3_bucket_policy
  ├── 4. Destroy aws_s3_bucket_public_access_block
  ├── 5. Destroy aws_s3_bucket_website_configuration
  └── 6. Destroy aws_s3_bucket               (bucket now empty — deleted successfully)
```

> **Lesson:** Always manage file uploads via Terraform (`aws_s3_object`) rather
> than manually via Console. Manual uploads create untracked objects that will
> block `terraform destroy`.

---

## Directory Structure

```
07-s3-static-website/
├── README.md
└── src/
    ├── provider.tf    # Terraform block + aws and random providers
    ├── s3.tf          # S3 bucket, public access block, policy, website config
    ├── objects.tf     # S3 object uploads (index.html, error.html)
    ├── outputs.tf     # Output: website endpoint
    └── build/
        ├── index.html # Static website index page
        └── error.html # Static website error page
```

---

## Implementation Steps

### Step 1: Create `provider.tf`

```hcl
terraform {
  required_version = "~>1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>6.30.0"
    }
    # random provider — generates stable random values
    # No provider block needed — requires no configuration
    random = {
      source  = "hashicorp/random"
      version = "~>3.8.1"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}
```

Initialize and verify both providers are downloaded:

```bash
terraform init
terraform version
```

**Expected — two providers shown:**
```
Terraform v1.10.x
+ provider registry.terraform.io/hashicorp/aws v6.x.x
+ provider registry.terraform.io/hashicorp/random v3.x.x
```

---

### Step 2: Create `s3.tf` — Bucket and Random Suffix

```hcl
# Generates a stable 8-character hex suffix for the bucket name
# Ensures global uniqueness without manual naming
resource "random_id" "bucket_suffix" {
  # MANDATORY — minimum value is 1
  # 4 bytes = 8 hex characters in the .hex output attribute
  byte_length = 4
}

resource "aws_s3_bucket" "static_website" {
  # Bucket name must be globally unique across all AWS accounts
  # Suffix from random_id ensures this
  bucket = "terraform-project01-${random_id.bucket_suffix.hex}"

  tags = {
    Name      = "07-s3-static-website"
    ManagedBy = "Terraform"
    Project   = "07-s3-static-website"
  }
}
```

Apply and verify:

```bash
terraform fmt
terraform plan
terraform apply -auto-approve
```

**Verify in AWS Console:**

1. Go to **S3 → Buckets**
2. Search for `terraform-course-proj01`
3. Your bucket should appear with the random hex suffix appended
4. Click the bucket → **Properties tab** → confirm region is correct

---

### Step 3: Add Public Access Block to `s3.tf`

By default AWS blocks all public access. Disable all four settings:

```hcl
resource "aws_s3_bucket_public_access_block" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  # All four must be false for a public static website
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
```

```bash
terraform apply -auto-approve
```

**Verify in AWS Console:**

1. Go to **S3 → Buckets** → click your bucket
2. Click **"Permissions"** tab
3. Under **"Block public access (bucket settings)"** → click **Edit**
4. All four checkboxes should be **unchecked** ✅

---

### Step 4: Add Bucket Policy to `s3.tf`

```hcl
resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.static_website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        # arn/* grants access to all objects inside the bucket
        Resource  = "${aws_s3_bucket.static_website.arn}/*"
      }
    ]
  })

  # depends_on prevents AccessDenied race condition:
  # the public access block must be fully applied before
  # the policy can be attached
  depends_on = [aws_s3_bucket_public_access_block.static_website]
}
```

```bash
terraform apply -auto-approve
```

> ⚠️ **If you get `AccessDenied` on first apply:** This is a known AWS race
> condition — the public access block settings have not fully propagated before
> the policy is applied. Re-run `terraform apply -auto-approve` — it will
> succeed on the second run. The `depends_on` reduces but does not fully
> eliminate this in all cases.

**Verify in AWS Console:**

1. Go to **S3** → click your bucket → **Permissions** tab
2. Scroll to **"Bucket policy"**
3. The policy JSON should be visible showing `s3:GetObject` with `Principal: *`

---

### Step 5: Add Website Configuration to `s3.tf`

```hcl
resource "aws_s3_bucket_website_configuration" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  # suffix — the default file served when accessing the root URL
  index_document {
    suffix = "index.html"
  }

  # key — the file returned for any missing/non-existent path
  error_document {
    key = "error.html"
  }
}
```

> **Note the argument difference:**
> `index_document` uses `suffix` — the filename appended to the URL path
> `error_document` uses `key` — the exact S3 object key to serve on error

```bash
terraform apply -auto-approve
```

**Verify in AWS Console:**

1. Go to **S3** → click your bucket → **Properties** tab
2. Scroll to the very bottom — **"Static website hosting"**
3. Status should show **"Enabled"**
4. The **Bucket website endpoint** URL is visible here
   (we will expose this via Terraform output in Step 7)

---

### Step 6: Create HTML Files in `build/`

Create the `build/` directory and two HTML files:

**`build/index.html`:**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>My Static S3 Website</title>
  <meta name="description" content="My Static S3 Website">
  <meta name="keywords" content="Terraform, S3, AWS, HashiCorp">
</head>
<body>
  <h1>My Static S3 Website</h1>
  <p>This page is hosted on AWS S3 and deployed with Terraform.</p>
</body>
</html>
```

**`build/error.html`:**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>My Static S3 Website</title>
</head>
<body>
  <h1>Oops — this page does not exist.</h1>
  <p><a href="/">Go back to the homepage</a></p>
</body>
</html>
```

---

### Step 7: Create `objects.tf` — Upload Files via Terraform

```hcl
resource "aws_s3_object" "index" {
  # MANDATORY — target bucket
  bucket = aws_s3_bucket.static_website.id

  # MANDATORY — the S3 key (path/filename inside the bucket)
  key = "index.html"

  # OPTIONAL — local file to upload
  # Path is relative to the directory where terraform commands are run
  source = "build/index.html"

  # OPTIONAL — MD5 hash of the local file
  # Triggers re-upload whenever the file content changes
  # Without this, editing index.html would not cause Terraform to re-upload
  etag = filemd5("build/index.html")

  # OPTIONAL — MIME type sent to browsers
  # Without this, S3 serves the file as application/octet-stream
  # which causes browsers to download rather than render the HTML
  content_type = "text/html"
}

resource "aws_s3_object" "error" {
  bucket       = aws_s3_bucket.static_website.id
  key          = "error.html"
  source       = "build/error.html"
  etag         = filemd5("build/error.html")
  content_type = "text/html"
}
```

```bash
terraform fmt
terraform apply -auto-approve
```

**Verify in AWS Console:**

1. Go to **S3** → click your bucket → **Objects** tab
2. You should see two objects: `index.html` and `error.html`
3. Click on `index.html` → **Properties** tab
4. Confirm **Content-Type** is `text/html`
5. Click **"Open"** — the raw HTML file opens in the browser

---

### Step 8: Create `outputs.tf` — Expose Website Endpoint

```hcl
output "website_endpoint" {
  description = "The S3 static website endpoint URL"
  value       = aws_s3_bucket_website_configuration.static_website.website_endpoint
}
```

```bash
terraform apply -auto-approve
```

**Expected output at the end of apply:**
```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

website_endpoint = "terraform-project01-a3f2c19b.s3-website.us-east-2.amazonaws.com"
```

**Retrieve the output value at any time:**

```bash
terraform output website_endpoint
# Returns just the value — useful in CI/CD pipelines
```

**Test the website:**

Open in browser:
```
http://<website_endpoint>
```

**Expected:** Your `index.html` page loads.

Test the error page by visiting a non-existent path:
```
http://<website_endpoint>/nonexistent.html
```

**Expected:** Your `error.html` page loads.

---

### Step 9: Verify File Change Detection with `etag`

Edit `build/index.html` — change the `<h1>` text to anything different.

```bash
terraform plan
```

**Expected plan output:**
```
~ resource "aws_s3_object" "index" {
    ~ etag   = "abc123..." -> "def456..."
    ~ source = "build/index.html"
}

Plan: 0 to add, 1 to change, 0 to destroy.
```

Terraform detected the file change via the MD5 hash difference and will
re-upload only the changed file.

```bash
terraform apply -auto-approve
```

Refresh the browser — the updated content is live.

---

## Cleanup

```bash
terraform state list
# Verify all 6 resources are listed before destroying

terraform destroy
# Type: yes
```

**Terraform destroy order (automatic):**

Terraform automatically resolves the correct destroy order based on
dependencies — objects are deleted before the bucket:

```
Destroy complete! Resources: 6 destroyed.
```

**Verify in AWS Console:**

1. Go to **S3 → Buckets**
2. Search for `terraform-course-proj01` — bucket should no longer exist

```bash
rm -rf .terraform/ .terraform.lock.hcl
```

---

## What You Learned

In this demo, you:

- ✅ Used `random_id` with the `random` provider to generate stable unique bucket name suffixes
- ✅ Configured two providers (`aws` + `random`) in a single Terraform project
- ✅ Disabled all four S3 public access block settings for a public website
- ✅ Wrote an S3 bucket policy inline using `jsonencode()` with ARN reference
- ✅ Configured S3 static website hosting with index and error documents
- ✅ Uploaded HTML files via `aws_s3_object` with `etag = filemd5()` for change detection
- ✅ Exposed the website endpoint using an `output` block in `outputs.tf`
- ✅ Retrieved output values with `terraform output <key>`
- ✅ Used `depends_on` to handle the public access block → policy race condition
- ✅ Understood how Terraform manages destroy order for dependent resources

**Key Insight:** Managing file uploads via Terraform (`aws_s3_object`) rather
than manually via the Console is critical — it ensures Terraform can track,
update, and cleanly destroy all resources including the objects that must be
removed before the bucket can be deleted.

---

## Lessons Learned

### 1. `random_id` is Stable — Not Random on Every Run

Once generated and stored in state, `random_id.hex` does not change on
subsequent applies. This is by design — Terraform needs predictable names.
The value only regenerates if `byte_length` changes or you explicitly
`terraform taint` the resource.

### 2. `content_type` on `aws_s3_object` is Critical

Without `content_type = "text/html"`, S3 serves HTML files as
`application/octet-stream` — browsers download the file instead of
rendering it. Always set `content_type` explicitly for web assets.

### 3. All Four Public Access Block Settings Must Be `false`

Setting even one to `true` blocks public access. The four settings are
independently enforced by AWS — they are not redundant.

### 4. `depends_on` for Non-Reference Dependencies

When resource A must wait for resource B but does not reference B's
attributes, use `depends_on` explicitly. The classic example in this demo:
`aws_s3_bucket_policy` depends on `aws_s3_bucket_public_access_block` even
though it does not reference any of its attributes directly.

### 5. `output` Values Are Available After Every Apply

You do not need to `terraform apply` again just to see outputs. Run
`terraform output` at any time to retrieve all outputs, or
`terraform output <name>` for a specific value.

### 6. Never Manually Upload Files to Terraform-Managed Buckets

Manual uploads create objects that Terraform does not know about. When you
run `terraform destroy`, Terraform will fail to delete the bucket because it
is not empty. Always use `aws_s3_object` to manage files that live in
Terraform-managed buckets.

---


## Troubleshooting

**`AccessDenied` when applying bucket policy:**

The public access block settings have not fully propagated before the policy
is applied — this is an AWS eventual consistency issue. Re-run
`terraform apply -auto-approve`. It succeeds on the second run. The
`depends_on` in the policy resource reduces but does not always eliminate
this in all environments.

**Browser downloads HTML instead of rendering it:**

`content_type` is missing or incorrect on the `aws_s3_object`. Set
`content_type = "text/html"` and re-apply.

**Website endpoint returns `403 Forbidden`:**

Either the public access block is not fully disabled (check all four
settings are `false`) or the bucket policy is missing/incorrect. Verify both
in the AWS Console under the bucket's **Permissions** tab.

**Website endpoint returns `404 Not Found`:**

The `index.html` object was not uploaded or the key does not match the
`suffix` in `index_document`. Verify the object exists in S3 and its key is
exactly `index.html`.

**`terraform destroy` fails with `BucketNotEmpty`:**

You have manually uploaded files to the bucket that are not tracked in
Terraform state. Manually delete all objects from the bucket in the Console
(S3 → bucket → select all → Delete) then re-run `terraform destroy`.

**`Error: duplicate resource identifier`:**

Two `aws_s3_object` resources have the same local name. Each resource block
must have a unique `<resource_type>.<local_name>` combination.

---

## Common Commands Reference

| Command | Description |
|---|---|
| `terraform init` | Initialize project and download providers |
| `terraform fmt` | Format all `.tf` files to canonical style |
| `terraform validate` | Validate configuration syntax |
| `terraform plan` | Show planned changes |
| `terraform apply -auto-approve` | Apply without confirmation prompt |
| `terraform destroy` | Destroy all managed resources |
| `terraform output` | Show all output values |
| `terraform output <name>` | Show a specific output value |
| `terraform state list` | List all resources tracked in state |
| `terraform state show <resource>` | Show full details of a specific resource |