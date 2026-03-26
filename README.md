# Combined website deploy (Terraform + S3 + CloudFront)

This repository deploys a **single static site** in **one S3 bucket** with **two CloudFront distributions** (portfolio domain + art domain) and **TLS from AWS Certificate Manager**. **DNS stays at your registrar**—this guide uses **Network Solutions** as the example; the same record types apply at any DNS host.

---

## Table of contents

1. [How this fits together](#how-this-fits-together)
2. [Terraform state in Git](#terraform-state-in-git)
3. [Regions: single region (us-east-1)](#regions-single-region-us-east-1-n-virginia)
4. [TLS certificates: ACM only](#tls-certificates-acm-only-no-certbot-no-keys-on-your-mac)
5. [Prerequisites checklist](#prerequisites-checklist)
6. [End-to-end deployment (step by step)](#end-to-end-deployment-step-by-step)  
   - [Step 0 — Clone the repo and install tools](#step-0--clone-the-repo-and-install-tools)  
   - [Steps 1–4 — AWS credentials and Terraform config](#step-1--create-aws-access-keys-for-terraform-on-your-machine)  
   - [Steps 5–7 — Terraform init, plan, first apply](#step-5--initialize-terraform)  
   - [Steps 8–9 — Network Solutions: ACM validation + site DNS](#step-8--acm-dns-validation-at-network-solutions-required-for-https)  
   - [Steps 10–12 — Content, invalidation, verify](#step-10--upload-your-static-files-to-s3)
7. [Network Solutions: detailed DNS guide](#network-solutions-detailed-dns-guide)
8. [Quick reference: scripts](#quick-reference-scripts)
9. [Troubleshooting](#troubleshooting-short)
10. [Related docs and summary checklist](#related-docs-in-this-repo)

---

## How this fits together

| Piece | Role |
|--------|------|
| **Your AWS account** | Hosts S3, ACM (TLS), CloudFront, IAM usage for Terraform |
| **Network Solutions (or other DNS)** | You create **two kinds** of records: (1) **ACM validation** CNAMEs so AWS can issue certificates, (2) **website** CNAMEs so visitors reach CloudFront |
| **This repo** | Terraform defines infrastructure; static files live under **`combined/`** |

You will log into **two different systems**: the **AWS console** (in **`us-east-1`**) and your **registrar/DNS** (e.g. Network Solutions). Nothing in this stack moves your DNS to Route 53 unless you choose to.

---

## Terraform state in Git

Terraform uses a **local backend** with state stored at **`terraform/state/terraform.tfstate`** (see **`terraform/backend.tf`**). That file is **intended to be committed** so infrastructure state is versioned with the repo.

**What must never be committed (already in `.gitignore`):**

- **`config/aws.env`** — IAM access keys or session tokens  
- **`config/terraform.tfvars`** — your bucket name and any overrides (copy from **`config/terraform.tfvars.example`**)  
- **`*.auto.tfvars`**, **`.env`** files — often used for secrets or `TF_VAR_*`  
- **State backups** — patterns like **`*.tfstate.*`** (e.g. `terraform.tfstate.backup`) stay ignored; only **`terraform/state/terraform.tfstate`** is tracked  
- **Rolling session backup** — **`terraform/state/session/latest.tfstate`** (gitignored) holds one local copy of live state, refreshed after **every successful** Terraform run from the **`tf-*.sh`** wrappers (written with an **atomic replace** so the file is never half-written). Older session files in that directory are removed so only the **latest** copy remains. Use **`USE_LATEST_SESSION=1`** or **`--use-session`** on a wrapper to **restore** live state from that file before Terraform runs (e.g. after a bad edit or to match a teammate’s saved session).

This stack does **not** put AWS credentials in Terraform variables; credentials load at runtime from **`config/aws.env`** or your environment. State still holds **resource IDs and ARNs** (normal for Terraform)—treat the repo as **private** if those details are sensitive for your org.

**If you already had state at `terraform/terraform.tfstate`** (default path) before this layout: run **`./scripts/tf-init.sh -migrate-state`** once and confirm the prompt so Terraform moves state into **`terraform/state/terraform.tfstate`**.

**Merge conflicts** on state: `.gitattributes` marks the state file as **binary** so Git does not auto-merge it; resolve by choosing one side or re-running Terraform against AWS as your source of truth.

---

## Regions: single region (us-east-1, N. Virginia)

**Everything in this stack uses one region:** **`us-east-1`**. That includes the **S3 bucket**, **ACM** certificates, **CloudFront** distributions, **Origin Access Control**, and the bucket policy. **`var.aws_region`** defaults to **`us-east-1`** and is validated so it cannot be changed without editing `terraform/variables.tf`. Set **`AWS_DEFAULT_REGION=us-east-1`** in `config/aws.env` so the CLI matches Terraform.

**Why `us-east-1`:** CloudFront viewer certificates must use public ACM certs in **`us-east-1`**. Placing the bucket and all other resources there avoids splitting the deployment across regions.

**Upgrading from an older two-provider layout** (`cloudfront_acm` or `us_east_1` alias): run **`terraform init -upgrade`**, then **`terraform plan`**. If Terraform plans to **destroy and recreate** ACM or CloudFront because the provider block changed, back up state and use Terraform’s **[state](https://developer.hashicorp.com/terraform/cli/commands/state)** tooling or **[replace-provider](https://developer.hashicorp.com/terraform/cli/commands/state/replace-provider)** guidance so resources stay mapped to the default provider. Greenfield applies need no migration.

---

## TLS certificates: ACM only (no Certbot, no keys on your Mac)

**Industry standard for CloudFront** is **AWS Certificate Manager (ACM)** in **`us-east-1` (N. Virginia)**:

- CloudFront **only** accepts ACM public certificates from **`us-east-1`**.
- You **do not** run **Certbot**, **OpenSSL**, or upload `.pem` / `.crt` files from your laptop for this setup.
- You **do not** “generate a private key” for the public HTTPS cert—ACM issues and stores the certificate; you attach it to CloudFront via Terraform.

**How validation works:** Terraform requests certificates with **DNS validation**. AWS shows **CNAME** records you must create at **Network Solutions** (or your DNS host). When DNS propagates, ACM marks the certificate **Issued**, and CloudFront can use it.

---

## Prerequisites checklist

Before starting the numbered steps, confirm:

| # | Requirement | Notes |
|---|----------------|--------|
| 1 | **AWS account** | Billing enabled if required; ability to create S3, ACM, CloudFront in **`us-east-1`** |
| 2 | **IAM user (or role)** you can create access keys for | For personal projects, attaching **`AdministratorAccess`** is simplest; production teams often use a scoped custom policy |
| 3 | **Domains you own** | Example defaults in `terraform/variables.tf`: portfolio + art zones (e.g. `nicketuttarwar.com`, `uttarwarart.com`) |
| 4 | **DNS hosted at Network Solutions** | You can log in and edit **Advanced DNS** (or equivalent) for **each** domain |
| 5 | **Globally unique S3 bucket name** | You will set **`s3_bucket_name`** in **`config/terraform.tfvars`** |
| 6 | **Terraform** **`~> 1.14.7`** | Matches **`required_version`** in `terraform/versions.tf` |
| 7 | **Optional: AWS CLI v2** | For `aws s3 sync` and CloudFront invalidations |

---

## End-to-end deployment (step by step)

Follow these in order. **Network Solutions–specific detail** (field names, apex, two DNS phases) is expanded in [Network Solutions: detailed DNS guide](#network-solutions-detailed-dns-guide).

### Step 0 — Clone the repo and install tools

1. Clone this repository to your machine and `cd` into the project root (the directory that contains **`terraform/`**, **`scripts/`**, **`config/`**).
2. Install **Terraform**: [Install Terraform](https://developer.hashicorp.com/terraform/install). Confirm:

   ```bash
   terraform version
   ```

   Use a version that satisfies **`required_version`** in `terraform/versions.tf` (currently **`~> 1.14.7`** — same **1.14.7** minor line with newer patches).
3. **Optional — AWS CLI:** [Installing the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), then `aws --version`.

---

### Step 1 — Create AWS access keys (for Terraform on your machine)

1. Sign in to the [AWS Management Console](https://console.aws.amazon.com/).
2. Open **IAM** → **Users** → your user (or create a dedicated user for deployments, e.g. `terraform-deploy`).
3. **Security credentials** → **Create access key** → choose a use case such as **Command Line Interface (CLI)**.
4. Save the **Access key ID** and **Secret access key** somewhere safe (password manager). You will not see the secret again.
5. Ensure the user can manage this stack’s services in **`us-east-1`** (S3, ACM, CloudFront, IAM for OAC-related reads, etc.).

**Security:** Do not commit keys. Do not paste them into Terraform files that are tracked by git.

---

### Step 2 — Configure local credentials (`config/aws.env`)

1. Copy the example file:

   ```bash
   cp config/aws.env.example config/aws.env
   ```

2. Edit **`config/aws.env`** and set:

   - **`AWS_ACCESS_KEY_ID`** — from Step 1  
   - **`AWS_SECRET_ACCESS_KEY`** — from Step 1  
   - **`AWS_DEFAULT_REGION=us-east-1`** — keeps CLI/Terraform defaults aligned with this repo (always **`us-east-1`**).  
   - If you use **temporary credentials** (e.g. SSO or assumed role), also set **`AWS_SESSION_TOKEN`**.

3. Confirm **`config/aws.env`** is **not** committed (it is listed in `.gitignore`).

The helper scripts under **`scripts/`** automatically **source** `config/aws.env` when that file exists.

---

### Step 3 — Configure Terraform variables (`config/terraform.tfvars`)

1. Copy the example:

   ```bash
   cp config/terraform.tfvars.example config/terraform.tfvars
   ```

2. Edit **`config/terraform.tfvars`**:

   - **`s3_bucket_name`** — **globally unique** (lowercase, no spaces; follow [S3 bucket naming rules](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucketnamingrules.html)).  
   - **`portfolio_domain_names`** / **`art_domain_names`** — only if your hostnames differ from the defaults in **`terraform/variables.tf`** (list of strings; first entry is the certificate primary domain).  
   - Optional: **`project_name`**, **`environment`**, **`common_tags`** — for resource names and AWS tags (see **`config/terraform.tfvars.example`**).

`config/terraform.tfvars` is **gitignored** (via **`*.tfvars`**) so environment-specific values stay local.

**How wrappers use this file:** **`scripts/lib/terraform-common.sh`** appends **`-var-file=…`** (pointing at the resolved path below) for Terraform subcommands that **accept variable files** — **`plan`**, **`apply`**, **`destroy`**, **`refresh`** (implemented as **`apply -refresh-only`**), **`console`**, **`import`**, **`graph`**, and **`test`**. It does **not** pass **`-var-file`** to **`validate`**, **`fmt`**, **`init`**, **`output`**, **`state`**, **`version`**, etc., because either the CLI does not support it (e.g. **`validate`** in Terraform **1.14**) or variables are not used.

**Resolution order** for the var file path: **`TF_VAR_FILE`** (if that path exists), else **`config/terraform.tfvars`**, else legacy **`terraform/terraform.tfvars`** (with a one-time warning to move to **`config/`**).

---

### Step 4 — (Optional) Formatting and `terraform validate`

From the repo root:

```bash
./scripts/tf-fmt-validate.sh
```

This runs **`terraform fmt`** then **`terraform validate`**. It does **not** load **`config/aws.env`**. **`terraform validate`** does **not** read **`.tfvars`** files in Terraform **1.14**; if you have **no** tfvars file yet, the script sets a placeholder **`TF_VAR_s3_bucket_name`** so **`validate`** can succeed. To verify the stack with your real **`s3_bucket_name`** and other values, use **`./scripts/tf-plan.sh`** (after **`./scripts/tf-init.sh`**).

---

### Step 5 — Initialize Terraform

From the **repository root**:

```bash
./scripts/tf-init.sh
```

This runs **`terraform init`** in the **`terraform/`** directory with your environment loaded from **`config/aws.env`** if present.

---

### Step 6 — Review the plan (no changes yet)

```bash
./scripts/tf-plan.sh
```

Inspect the planned resources: S3 bucket, ACM certificates, CloudFront distributions, bucket policy, etc.

---

### Step 7 — First `terraform apply` (creates certs and waits on DNS validation)

```bash
./scripts/tf-apply.sh
```

**What to expect**

- Terraform creates ACM certificate **requests** and then **waits** until **DNS validation** succeeds (`aws_acm_certificate_validation`). That can take **minutes to much longer** if the **validation CNAMEs** are not in DNS yet.
- **Do not wait for a timeout if you already know what to do:** as soon as certificates appear in ACM as **Pending validation**, add the CNAME records (Step 8). You can read the exact names/values from the **[ACM console (us-east-1)](https://us-east-1.console.aws.amazon.com/acm/home?region=us-east-1#/certificates/list)** while **`apply` is still running.
- If **`apply`** fails or times out before validation completes, finish **Step 8**, wait until both certificates show **Issued** in ACM, then run **`./scripts/tf-apply.sh`** again.

---

### Step 8 — ACM DNS validation at Network Solutions (required for HTTPS)

Terraform creates **two** certificates (portfolio + art). Each needs **DNS validation** CNAMEs in the **correct DNS zone** (portfolio domain vs art domain).

#### 8a — Get the exact CNAME records

**Option A — Terraform output** (after resources exist in state):

```bash
./scripts/tf-output.sh
```

For machine-readable copy:

```bash
./scripts/tf-output.sh -json
```

Relevant outputs (see **`terraform/outputs.tf`**):

- **`acm_portfolio_validation_records`** — **`name`**, **`type`**, **`record`** for the **portfolio** zone.  
- **`acm_art_validation_records`** — same for the **art** zone.

**Option B — AWS console** (same data as Terraform): **ACM** → **us-east-1** → open each certificate → **Domains** → copy each **CNAME name** and **CNAME value**.

Each hostname on the certificate (often **apex** + **`www`**) usually has **its own** validation CNAME.

#### 8b — Add records at Network Solutions

1. Log in to **[Network Solutions](https://www.networksolutions.com/)** with the account that controls the domain.
2. Go to **My Account** → **My Domain Names** → select the domain → **DNS** / **Manage Advanced DNS** / **Advanced DNS** (labels vary).
3. Add a **CNAME** row for **each** validation record AWS shows (see [Network Solutions: detailed DNS guide](#network-solutions-detailed-dns-guide) for Host vs Points-to).
4. **Save**. Repeat for the **other** domain’s zone if you use two domains.
5. Wait for DNS propagation (often minutes; sometimes longer).

**Official AWS:** [DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html).  
**Network Solutions:** [Manage Advanced DNS records](https://www.networksolutions.com/support/how-to-manage-advanced-dns-records/).

#### 8c — Confirm certificates are Issued in AWS

1. Open **ACM** in **`us-east-1`**: [ACM us-east-1](https://us-east-1.console.aws.amazon.com/acm/home?region=us-east-1#/certificates/list).
2. Each certificate should move from **Pending validation** to **Issued**.

When both are **Issued**, run **`./scripts/tf-apply.sh`** again if anything failed earlier or CloudFront is still updating.

---

### Step 9 — Point your **site** DNS at CloudFront (Network Solutions)

This is **separate** from Step 8. Here you send **real visitors** to CloudFront using your distributions’ **`*.cloudfront.net`** domain names—not the ACM validation hostnames.

#### 9a — Get CloudFront target hostnames

```bash
./scripts/tf-output.sh
```

Note:

- **`cloudfront_portfolio_domain_name`** — e.g. `d111111abcdef8.cloudfront.net` (portfolio).  
- **`cloudfront_art_domain_name`** — different distribution (art).

#### 9b — Create **website** records

You need **`www`** (and optionally apex) for each brand to point to the **correct** distribution.

| Goal | Typical record | Points to (value) |
|------|----------------|-------------------|
| Portfolio `www` | **CNAME** | **`cloudfront_portfolio_domain_name`** (full `dxxx.cloudfront.net`) |
| Art `www` | **CNAME** | **`cloudfront_art_domain_name`** |

**Apex (bare domain, e.g. `example.com` without `www`)**

CloudFront does **not** give you a static IP for an **A** record. Common approaches:

- **URL forwarding** at Network Solutions: forward **`https://example.com`** → **`https://www.example.com`** (or HTTP→HTTPS per their product).  
- Or use a DNS feature that supports **ALIAS/ANAME** at apex to a hostname, **if** your plan includes it—check Network Solutions’ current docs.

**Do not** remove **ACM validation** CNAMEs unless AWS documentation says it is safe (often you can leave them).

---

### Step 10 — Upload your static files to S3

Your bucket layout should match this project’s **`combined/`** tree: portfolio files at the **bucket root**, art under **`uttarwarart/`** (or whatever you set as **`art_origin_path`** in `variables.tf` / overrides).

With AWS CLI configured (same credentials as Terraform):

```bash
aws s3 sync combined/ s3://YOUR_BUCKET_NAME/ --delete
```

Replace **`YOUR_BUCKET_NAME`** with the value from **`./scripts/tf-output.sh`** → **`s3_bucket_id`** (or **`-raw s3_bucket_id`**).

---

### Step 11 — Invalidate CloudFront caches (after uploads)

When you change files already cached at the edge, create an invalidation per distribution:

```bash
aws cloudfront create-invalidation --distribution-id PORTFOLIO_DIST_ID --paths "/*"
aws cloudfront create-invalidation --distribution-id ART_DIST_ID --paths "/*"
```

Use **`cloudfront_portfolio_distribution_id`** and **`cloudfront_art_distribution_id`** from **`./scripts/tf-output.sh`**. Narrower paths (e.g. `/index.html`) reduce invalidation scope if you prefer.

---

### Step 12 — Verify end-to-end

1. Open **`https://`** + your portfolio hostnames (apex and `www`)—portfolio content.  
2. Open **`https://`** + your art hostnames—art content (served from the art origin path prefix in the bucket).  
3. Try **http://** URLs—both should **redirect to HTTPS** as configured.  
4. In the browser, inspect the certificate—issuer should be **Amazon** (ACM).

---

## Network Solutions: detailed DNS guide

Use this section together with **Step 8** (validation) and **Step 9** (website traffic).

### Accounts and access

- You need a **Network Solutions account** that can manage **DNS** for **each** domain (portfolio and art if they are separate zones).
- If someone else bought the domain, ensure you have **login access** or ask them to add the records you send them.

### Two different jobs (do not mix them up)

| Job | Purpose | Where the values come from | Record type |
|-----|---------|----------------------------|-------------|
| **A — ACM validation** | Prove to AWS that you control the domain so **TLS certificates** can issue | **`acm_*_validation_records`** or ACM console (**Pending validation**) | **CNAME** (usually) |
| **B — Website traffic** | Send **visitors** to your **CloudFront** distributions | **`cloudfront_*_domain_name`** outputs | **CNAME** for `www`; apex uses forwarding or ALIAS-style feature |

Using a **CloudFront** hostname in job A is wrong. Using **ACM validation** hostnames in job B is wrong.

### Adding a CNAME in Network Solutions (typical UI)

Wording varies; you usually see fields similar to:

- **Host** / **Alias** / **Name** — Often the **left-hand** part only, e.g. `www` for `www.example.com`, or a long **`_hash`** string for ACM validation. **Paste exactly** what AWS shows; do not add your domain twice if the UI auto-appends it.
- **Points to** / **Target** / **Value** — The **hostname** AWS gives (validation target ending in **`acm-validations.aws.`** or similar, or the **`dxxx.cloudfront.net`** for site CNAMEs).
- **TTL** — Default (e.g. 1 hour) is fine.

If validation fails for hours, double-check: **wrong zone** (art CNAME on portfolio domain), **typo** in the **value**, or **extra** `.` / missing dot—compare character-for-character with ACM.

### Apex (`@`) and `www`

- **`www.example.com` → CloudFront:** add a **CNAME** for host **`www`** pointing to the **`cloudfront_*_domain_name`** for that site.  
- **`example.com` (apex):** prefer **URL forwarding** (Network Solutions) from apex to **`https://www.example.com`**, or use an **ALIAS/ANAME**-style record if your product supports pointing the apex to a **hostname**.

### After certificates issue

Keep monitoring **ACM** until both certs are **Issued**, then ensure **Step 9** DNS is in place. Use **`./scripts/tf-output.sh`** whenever you need IDs, bucket name, or CloudFront domain names.

---

## Quick reference: scripts

All **`tf-*.sh`** wrappers run Terraform from the repo root with **`-chdir=terraform`**, load **`config/aws.env`** when that file exists (**`tf-fmt-validate.sh`** and **`tf-version.sh`** skip it), append **`-var-file`** for **`config/terraform.tfvars`** when that file exists and the subcommand uses variables (see **`scripts/lib/terraform-common.sh`**; legacy **`terraform/terraform.tfvars`** is still honored if the config file is absent), and check that **`terraform`** is on your **`PATH`** and the **`terraform/`** module is present. Pass **`-h`** or **`--help`** on a wrapper for a short usage line; any other arguments are forwarded to Terraform.

**Running Terraform yourself** (without a wrapper), from the **repository root**, pass the var file after the subcommand, for example: **`terraform -chdir=terraform plan -var-file=config/terraform.tfvars`**.

Each run prints **`[script-name]`** lines to **stderr** (what is loading, the exact **`terraform -chdir=...`** command, and success or non-zero exit). **`TF_QUIET=1`** turns off those informational lines; **`TF_TRACE=1`** enables shell **`set -x`** for deep debugging.

**Session state (rolling backup):** After each successful Terraform invocation via **`terraform_common_exec`** / **`terraform_common_exec_local`**, the live file **`terraform/state/terraform.tfstate`** is updated to **`terraform/state/session/latest.tfstate`** using an atomic write; any other **`*.tfstate`** files under **`terraform/state/session/`** are removed so only one backup remains. To **start from that backup** instead of the current live file, use **`USE_LATEST_SESSION=1`** or pass **`--use-session`** (supported by all **`tf-*.sh`** scripts, **`tf-fmt-validate.sh`**, **`destroy-stack.sh`**; **`list-tagged-resources.sh`** honors **`USE_LATEST_SESSION=1`**).

| Script | Purpose |
|--------|---------|
| `./scripts/tf-init.sh` | `terraform init` |
| `./scripts/tf-plan.sh` | `terraform plan` |
| `./scripts/tf-apply.sh` | `terraform apply` |
| `./scripts/tf-destroy.sh` | `terraform destroy` |
| `./scripts/destroy-stack.sh` | **Full teardown:** **`tf-plan.sh -destroy`** (saved plan) → confirm → **`tf-apply.sh`** plan file. Plan stored at **`terraform/.destroy.tfplan`** (gitignored). **`./scripts/destroy-stack.sh -y`** skips the confirmation prompt |
| `./scripts/tf-output.sh` | `terraform output` (add **`-json`** or **`-raw NAME`**) |
| `./scripts/tf-show.sh` | `terraform show` (state or saved plan file) |
| `./scripts/tf-state.sh` | `terraform state …` (e.g. `list`, `mv`, `rm`) |
| `./scripts/tf-import.sh` | `terraform import …` |
| `./scripts/tf-refresh.sh` | `terraform apply -refresh-only` (sync state with AWS) |
| `./scripts/tf-console.sh` | `terraform console` |
| `./scripts/tf-graph.sh` | `terraform graph` |
| `./scripts/tf-workspace.sh` | `terraform workspace …` (if your backend uses workspaces) |
| `./scripts/tf-force-unlock.sh` | `terraform force-unlock <lock-id>` |
| `./scripts/tf-version.sh` | `terraform version` (does not require **`config/aws.env`**) |
| `./scripts/tf-fmt-validate.sh` | `terraform fmt -recursive` then **`validate`** (does not load **`config/aws.env`**). **`terraform validate`** does not read **`.tfvars`** files; use **`tf-plan.sh`** for a full check with **`config/terraform.tfvars`**. If no tfvars file exists, sets a placeholder **`TF_VAR_s3_bucket_name`** for validate. **`--check`** runs **`fmt -check`** only (fails if formatting is needed) |
| `./scripts/list-tagged-resources.sh` | Lists tagged resources (default region **`us-east-1`**). Override **`LIST_TAG_REGIONS`** if you use a forked multi-region setup |
| `./scripts/run-tests.sh` | Runs **`bash -n`** on scripts, **`tf-fmt-validate --check`**, and **`combined/test_site.py`** against a local server (optional **`RUN_TERRAFORM_PLAN=1`** for **`terraform plan`** when AWS credentials exist) |

Shared helpers live in **`scripts/lib/terraform-common.sh`**.

### Tear down all AWS resources (recovery)

If an apply failed partway or you need to remove everything this Terraform stack manages:

```bash
./scripts/destroy-stack.sh
```

This uses **`./scripts/tf-plan.sh`** with **`-destroy`** to write a plan file, asks you to type **`yes`** after reviewing the plan, then applies it with **`./scripts/tf-apply.sh`**. To skip the prompt (for example in automation you control): **`./scripts/destroy-stack.sh -y`**.

You can still run **`./scripts/tf-destroy.sh`** directly; **`destroy-stack.sh`** is the safer, two-step flow that reuses the same wrappers and logging.

### Automated checks

From the repo root:

```bash
./scripts/run-tests.sh
```

This verifies shell syntax, Terraform formatting and **`validate`**, and HTTP **`200`** responses for main pages and assets under **`combined/`** (uses **`python3 -m http.server`** on **`127.0.0.1`**; override port with **`TEST_HTTP_PORT`** if needed).

To include **`terraform plan`** when credentials are configured:

```bash
RUN_TERRAFORM_PLAN=1 ./scripts/run-tests.sh
```

If **`config/aws.env`** (or standard AWS environment variables) is missing, the plan step is skipped so local/CI runs without keys still pass.

To run the site test alone with your own server: **`BASE=http://127.0.0.1:8080 python3 combined/test_site.py`** (serve **`combined/`** first, e.g. **`./combined/run_web.sh`**).

---

## Troubleshooting (short)

| Issue | What to check |
|--------|----------------|
| Certificate stuck **Pending validation** | ACM validation CNAME **name and value** match Terraform/ACM exactly; correct **zone** (portfolio vs art domain). |
| CloudFront **403** from S3 | Bucket policy allows both distribution ARNs; origins use **Origin Access Control**; objects uploaded under expected prefixes (art under **`art_origin_path`**). |
| Wrong site on a hostname | DNS **CNAME** points to the **correct** `*.cloudfront.net` for that brand (two distributions = two targets). |
| `terraform` or AWS errors about region | Use **`AWS_DEFAULT_REGION=us-east-1`** and **`aws_region = "us-east-1"`** (default). This stack is single-region. |
| Wrong bucket name or missing **`s3_bucket_name`** in plans/applies | Edit **`config/terraform.tfvars`** (or **`TF_VAR_FILE`**). Ensure **`./scripts/tf-plan.sh`** shows the intended name. |
| Need to **remove all** stack resources after a bad run | **`./scripts/destroy-stack.sh`** (uses **`tf-plan.sh`** + **`tf-apply.sh`**); confirm the plan, or **`./scripts/destroy-stack.sh -y`** if you accept the risk |

---

## Related docs in this repo

- [`combined/README.md`](combined/README.md) — static site content and layout.

---

## Summary checklist

1. Clone repo; install Terraform (satisfies **`~> 1.14.7`** in `terraform/versions.tf`) and optional AWS CLI.  
2. Create IAM access keys; put them in **`config/aws.env`** (**never commit**); set **`AWS_DEFAULT_REGION=us-east-1`**.  
3. Copy **`config/terraform.tfvars.example`** → **`config/terraform.tfvars`**; set **unique `s3_bucket_name`** and correct **`portfolio_domain_names`** / **`art_domain_names`**.  
4. **`./scripts/tf-init.sh`** → **`./scripts/tf-plan.sh`** → **`./scripts/tf-apply.sh`**.  
5. In **Network Solutions**, add **ACM validation** CNAMEs for **both** domains; wait until certs are **Issued** in ACM (**us-east-1**); **`./scripts/tf-apply.sh`** again if needed.  
6. In **Network Solutions**, add **website** CNAMEs (`www` → correct **`cloudfront_*_domain_name`**) and handle **apex** (forwarding or ALIAS-style).  
7. **`aws s3 sync`** your **`combined/`** tree; **invalidate** both CloudFront distributions; test **HTTPS** in the browser.  
8. To tear everything down: **`./scripts/destroy-stack.sh`** (or **`./scripts/tf-destroy.sh`**).

You can add credentials and run the steps in order; no Certbot or manual TLS key generation is required for this AWS setup.
