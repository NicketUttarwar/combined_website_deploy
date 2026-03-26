# Static website deploy (Terraform + S3 + CloudFront)

This repository deploys **one static website**: a **single S3 bucket**, **one CloudFront distribution**, and **TLS from AWS Certificate Manager** for **nicketuttarwar.com** with **apex and `www`** by default. Site files live under **`combined/`** in this repo (synced to the bucket root). **DNS stays at your registrar**—this guide uses **Network Solutions** as the example; the same record types apply at any DNS host.

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
   - [Steps 5–6 — Terraform init and plan](#step-5--initialize-terraform)  
   - [Steps 7–10 — Terraform: phase 1 apply, ACM DNS, check script, full apply](#step-7--first-terraform-apply-phase-1-s3--acm-request-no-dns-wait)  
   - [Steps 11–12 — Network Solutions: site DNS + content](#step-11--point-your-site-dns-at-cloudfront-network-solutions)  
   - [Steps 13–14 — Invalidate and verify](#step-13--invalidate-cloudfront-caches-after-uploads)
7. [Network Solutions: detailed DNS guide](#network-solutions-detailed-dns-guide)
8. [Quick reference: scripts](#quick-reference-scripts)
9. [Troubleshooting](#troubleshooting-short)
10. [Related docs and summary checklist](#related-docs-in-this-repo)

---

## How this fits together

| Piece | Role |
|--------|------|
| **Your AWS account** | Hosts S3, ACM (TLS), CloudFront, IAM usage for Terraform |
| **Network Solutions (or other DNS)** | You create **two kinds** of records: (1) **ACM validation** CNAMEs so AWS can issue the certificate, (2) **website** CNAMEs so visitors reach CloudFront |
| **This repo** | Terraform defines one website’s infrastructure; static files live under **`combined/`** |

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

**Everything in this stack uses one region:** **`us-east-1`**. That includes the **S3 bucket**, **ACM** certificate, **CloudFront** distribution, **Origin Access Control**, and the bucket policy. **`var.aws_region`** defaults to **`us-east-1`** and is validated so it cannot be changed without editing `terraform/variables.tf`. Set **`AWS_DEFAULT_REGION=us-east-1`** in `config/aws.env` so the CLI matches Terraform.

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
| 3 | **Domain** | Defaults in `terraform/variables.tf`: **`nicketuttarwar.com`** and **`www.nicketuttarwar.com`** as one site’s hostnames; override `domain_names` only if yours differ |
| 4 | **DNS hosted at Network Solutions** | You can log in and edit **Advanced DNS** (or equivalent) for that zone |
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
   - **`domain_names`** — only if your hostnames differ from the defaults in **`terraform/variables.tf`** (list of strings for the **same** site; first entry is the ACM primary domain).  
   - Optional: **`project_name`** (default **`website`**), **`environment`**, **`common_tags`** — for resource names and AWS tags (see **`config/terraform.tfvars.example`**).

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

Inspect the planned resources: S3 bucket, ACM certificate, CloudFront distribution, bucket policy, etc.

---

### Step 7 — First Terraform apply (phase 1): S3 + ACM request — no DNS wait

Use the **phase 1** script so Terraform **does not** sit on `aws_acm_certificate_validation` while you work in your DNS provider (Network Solutions). It creates the **S3 bucket**, **ACM certificate request**, and **CloudFront Origin Access Control**, then **exits**.

```bash
./scripts/tf-apply-phase1.sh
```

Optional: **`./scripts/tf-apply-phase1.sh -auto-approve`** if you already reviewed a plan.

**What to expect**

- The command finishes shortly after AWS creates the certificate in **Pending validation** state.
- You are **not** waiting for DNS propagation in this step — that happens **after** you add records (Step 8) and verify (Step 9).

If you **already** have a full apply from an older workflow, routine updates use **`./scripts/tf-apply.sh`** as usual.

---

### Step 8 — ACM DNS validation at Network Solutions (required for HTTPS)

Terraform creates **one** ACM certificate covering **`domain_names`**. Add **DNS validation** CNAMEs in the DNS zone for those hostnames (e.g. **nicketuttarwar.com** when using the defaults).

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

- **`acm_validation_records`** — **`name`**, **`type`**, **`record`** for the DNS zone that hosts those hostnames.

**Option B — AWS console** (same data as Terraform): **ACM** → **us-east-1** → open each certificate → **Domains** → copy each **CNAME name** and **CNAME value**.

Each hostname on the certificate (often **apex** + **`www`**) usually has **its own** validation CNAME.

#### 8b — Add records at Network Solutions

1. Log in to **[Network Solutions](https://www.networksolutions.com/)** with the account that controls the domain.
2. Go to **My Account** → **My Domain Names** → select the domain → **DNS** / **Manage Advanced DNS** / **Advanced DNS** (labels vary).
3. Add a **CNAME** row for **each** validation record AWS shows (see [Network Solutions: detailed DNS guide](#network-solutions-detailed-dns-guide) for Host vs Points-to).
4. **Save**.
5. Wait for DNS propagation (often minutes; sometimes longer).

**Official AWS:** [DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html).  
**Network Solutions:** [Manage Advanced DNS records](https://www.networksolutions.com/support/how-to-manage-advanced-dns-records/).

#### 8c — Confirm records are saved (Issued comes next)

After saving at Network Solutions, **do not** stare at Terraform — use **Step 9** to check whether ACM has picked up DNS yet.

---

### Step 9 — Check ACM status (`check-acm-dns.sh` or the console)

**After** you have added the ACM validation CNAMEs, open **AWS Certificate Manager** in **`us-east-1`** and refresh until the certificate shows **Issued** (this can take a few minutes).

Optional: run the helper — it does **not** call AWS; it prints the console link and reminders:

```bash
./scripts/check-acm-dns.sh
```

When the cert is **Issued**, proceed to **Step 10**.

**Official AWS:** [DNS validation](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html).

---

### Step 10 — Second Terraform apply (`tf-apply.sh`): CloudFront + validation

When **ACM** shows the certificate **Issued**, apply the rest of the stack (ACM validation resource, CloudFront, bucket policy). Terraform may wait briefly while it **confirms** validation — usually **seconds** if DNS is already correct.

```bash
./scripts/tf-apply.sh
```

If this step fails, read the error, fix DNS or ACM if needed, then run **`./scripts/tf-apply.sh`** again.

---

### Step 11 — Point your **site** DNS at CloudFront (Network Solutions)

This is **separate** from ACM validation (Steps 8–9). Here you send **real visitors** to CloudFront using the distribution’s **`*.cloudfront.net`** domain name—not the ACM validation hostnames.

**Requires Step 10** so **`cloudfront_domain_name`** exists in **`./scripts/tf-output.sh`**.

#### 11a — Get CloudFront target hostnames

```bash
./scripts/tf-output.sh
```

Note:

- **`cloudfront_domain_name`** — e.g. `d111111abcdef8.cloudfront.net` (one CloudFront hostname for all paths on this site).

#### 11b — Create **website** records

Point **`www`** (and optionally apex) at this distribution.

| Goal | Typical record | Points to (value) |
|------|----------------|-------------------|
| `www.nicketuttarwar.com` | **CNAME** | **`cloudfront_domain_name`** (full `dxxx.cloudfront.net`) |

**Apex (bare domain, e.g. `example.com` without `www`)**

CloudFront does **not** give you a static IP for an **A** record. Common approaches:

- **URL forwarding** at Network Solutions: forward **`https://example.com`** → **`https://www.example.com`** (or HTTP→HTTPS per their product).  
- Or use a DNS feature that supports **ALIAS/ANAME** at apex to a hostname, **if** your plan includes it—check Network Solutions’ current docs.

**Do not** remove **ACM validation** CNAMEs unless AWS documentation says it is safe (often you can leave them).

---

### Step 12 — Upload your static files to S3

Your bucket layout should mirror the **`combined/`** directory: upload so the bucket root matches that tree (same paths as locally under **`combined/`**).

With AWS CLI configured (same credentials as Terraform):

```bash
aws s3 sync combined/ s3://combined-personal-website-s3-bucket-nvu/ --delete
```

Replace **`YOUR_BUCKET_NAME`** with the value from **`./scripts/tf-output.sh`** → **`s3_bucket_id`** (or **`-raw s3_bucket_id`**).

---

### Step 13 — Invalidate CloudFront caches (after uploads)

When you change files already cached at the edge, create an invalidation:

```bash
aws cloudfront create-invalidation --distribution-id E3MF2QW17YDNP4 --paths "/*"
```

Use **`cloudfront_distribution_id`** from **`./scripts/tf-output.sh`**. Narrower paths (e.g. `/index.html` or `/uttarwarart/index.html`) reduce invalidation scope if you prefer.

---

### Step 14 — Verify end-to-end

1. Open **`https://nicketuttarwar.com/`** and **`https://www.nicketuttarwar.com/`** (or your **`domain_names`**) and spot-check important paths.  
2. Try **http://** URLs—they should **redirect to HTTPS** as configured.  
3. In the browser, inspect the certificate—issuer should be **Amazon** (ACM).

---

## Network Solutions: detailed DNS guide

Use this section together with **Step 8** (validation) and **Step 11** (website traffic).

### Accounts and access

- You need a **Network Solutions account** that can manage **DNS** for **nicketuttarwar.com** (or your chosen zone in **`domain_names`**).
- If someone else bought the domain, ensure you have **login access** or ask them to add the records you send them.

### Two different jobs (do not mix them up)

| Job | Purpose | Where the values come from | Record type |
|-----|---------|----------------------------|-------------|
| **A — ACM validation** | Prove to AWS that you control the domain so **TLS** can issue | **`acm_validation_records`** or ACM console (**Pending validation**) | **CNAME** (usually) |
| **B — Website traffic** | Send **visitors** to **CloudFront** | **`cloudfront_domain_name`** output | **CNAME** for `www`; apex uses forwarding or ALIAS-style feature |

Using a **CloudFront** hostname in job A is wrong. Using **ACM validation** hostnames in job B is wrong.

### Adding a CNAME in Network Solutions (typical UI)

Wording varies; you usually see fields similar to:

- **Host** / **Alias** / **Name** — Often the **left-hand** part only, e.g. `www` for `www.example.com`, or a long **`_hash`** string for ACM validation. **Paste exactly** what AWS shows; do not add your domain twice if the UI auto-appends it.
- **Points to** / **Target** / **Value** — The **hostname** AWS gives (validation target ending in **`acm-validations.aws.`** or similar, or the **`dxxx.cloudfront.net`** for site CNAMEs).
- **TTL** — Default (e.g. 1 hour) is fine.

If validation fails for hours, double-check: **wrong DNS zone**, **typo** in the **value**, or **extra** `.` / missing dot—compare character-for-character with ACM.

### Apex (`@`) and `www`

- **`www.example.com` → CloudFront:** add a **CNAME** for host **`www`** pointing to **`cloudfront_domain_name`**.  
- **`example.com` (apex):** prefer **URL forwarding** (Network Solutions) from apex to **`https://www.example.com`**, or use an **ALIAS/ANAME**-style record if your product supports pointing the apex to a **hostname**.

### After certificates issue

Keep monitoring **ACM** until the cert is **Issued** (or run **`./scripts/check-acm-dns.sh`** for the console link), then ensure **Step 11** site DNS is in place. Use **`./scripts/tf-output.sh`** whenever you need IDs, bucket name, or CloudFront domain name.

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
| `./scripts/tf-apply-phase1.sh` | **First `apply` on a new stack:** S3 + ACM certificate request + OAC only — **returns immediately** (no wait for DNS validation); see README Step 7 |
| `./scripts/check-acm-dns.sh` | After ACM validation CNAMEs exist: prints the **ACM console** link and reminders (does not query AWS) |
| `./scripts/tf-apply.sh` | Full **`terraform apply`** (use after phase 1 + DNS; creates CloudFront, validation, bucket policy) |
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
| Certificate stuck **Pending validation** | ACM validation CNAME **name and value** match Terraform/ACM exactly; records are in the **correct** zone for **`domain_names`**. |
| CloudFront **403** from S3 | Bucket policy allows the distribution ARN; origin uses **Origin Access Control**; objects exist at the paths you request under **`combined/`** after sync. |
| Wrong site on a hostname | DNS **CNAME** for **`www`** points to **`cloudfront_domain_name`**. |
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
3. Copy **`config/terraform.tfvars.example`** → **`config/terraform.tfvars`**; set **unique `s3_bucket_name`** and **`domain_names`** if needed (defaults: **nicketuttarwar.com** + **www**).  
4. **`./scripts/tf-init.sh`** → **`./scripts/tf-plan.sh`** → **`./scripts/tf-apply-phase1.sh`** (ends without waiting on DNS).  
5. In **Network Solutions**, add **ACM validation** CNAMEs; in **ACM** (us-east-1), wait until the cert is **Issued** (or run **`./scripts/check-acm-dns.sh`** for the console link); then **`./scripts/tf-apply.sh`** to create CloudFront and the rest.  
6. In **Network Solutions**, add **website** CNAMEs (`www` → **`cloudfront_domain_name`**) and handle **apex** (forwarding or ALIAS-style).  
7. **`aws s3 sync`** your **`combined/`** tree; **invalidate** CloudFront; test **HTTPS** in the browser.  
8. To tear everything down: **`./scripts/destroy-stack.sh`** (or **`./scripts/tf-destroy.sh`**).

**Legacy state:** If you previously used older Terraform in this repo with differently named resources, see **`terraform/moved.tf`** for address migrations. After changing **`project_name`** from an earlier default (e.g. to **`website`**), run **`terraform plan`** and update tags in AWS if you rely on the **Project** tag for scripts such as **`list-tagged-resources.sh`**.

You can add credentials and run the steps in order; no Certbot or manual TLS key generation is required for this AWS setup.
