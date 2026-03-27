#!/usr/bin/env bash
# Phase 1 of a new deploy: create S3 (including static website settings), ACM certificate request.
# Does NOT create CloudFront, bucket policy, or aws_acm_certificate_validation — so Terraform
# returns as soon as AWS accepts the certificate request (you add DNS next; no long wait here).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/terraform-common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options forwarded to terraform apply]

First-time deploy (before ACM DNS validation):

  Creates only: S3 bucket + public access block, S3 static website configuration (index/error
  documents), ACM certificate (Pending validation).

  Stops here on purpose — you add ACM validation CNAMEs at your DNS host next, wait until ACM
  shows Issued (see AWS Console us-east-1; optional ./scripts/check-acm-dns.sh for the link), then
  ./scripts/tf-apply.sh to finish (validation + CloudFront + public read bucket policy).

Do not use this if you already completed a full apply; use ./scripts/tf-apply.sh for routine updates.

Examples:
  $(basename "$0")
  $(basename "$0") -auto-approve
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tf_log "→ terraform apply (phase 1: S3 + website config + ACM request only — no wait for DNS validation)"
terraform_common_exec apply \
  -target=aws_s3_bucket.site \
  -target=aws_s3_bucket_public_access_block.site \
  -target=aws_s3_bucket_website_configuration.site \
  -target=aws_acm_certificate.site \
  "$@" &&
  tf_log "Phase 1 finished. Next: add ACM validation CNAMEs (see README Step 8), wait until ACM is Issued (console or ./scripts/check-acm-dns.sh), then ./scripts/tf-apply.sh"
