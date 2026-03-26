#!/usr/bin/env bash
# One-shot check: ACM certificate status + optional public DNS lookups for validation CNAMEs.
# Default does not loop — run again when you expect propagation to have progressed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/terraform-common.sh"

TF_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
ACM_REGION="${ACM_REGION:-us-east-1}"
WAIT_ATTEMPTS="${WAIT_ATTEMPTS:-30}"
WAIT_INTERVAL_SEC="${WAIT_INTERVAL_SEC:-10}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--wait]

After ./scripts/tf-apply-phase1.sh and adding ACM validation CNAMEs at your DNS host:

  - Reads certificate state from AWS (ground truth for whether the cert is ready).
  - Optionally runs dig (if installed) against public DNS for each validation record.

Default: one check, then exit (0 = certificate Issued; 1 = not issued yet).

  --wait    Retry up to WAIT_ATTEMPTS times every WAIT_INTERVAL_SEC seconds (default:
            ${WAIT_ATTEMPTS} × ${WAIT_INTERVAL_SEC}s). Prints each attempt; stop anytime with Ctrl+C.

Environment: ACM_REGION (default ${ACM_REGION}), WAIT_ATTEMPTS, WAIT_INTERVAL_SEC
EOF
}

DO_WAIT=0
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--wait" ]]; then
  DO_WAIT=1
fi

terraform_common_require
terraform_common_source_aws_env

if ! command -v aws >/dev/null 2>&1; then
  tf_warn "aws CLI not found — install AWS CLI v2 to use this script"
  exit 127
fi

CERT_ARN=""
if ! CERT_ARN="$(cd "$REPO_ROOT" && terraform -chdir="$TF_DIR" output -raw acm_certificate_arn 2>/dev/null)" || [[ -z "$CERT_ARN" ]]; then
  tf_warn "Could not read acm_certificate_arn from Terraform state."
  tf_warn "Run ./scripts/tf-apply-phase1.sh first (or ensure state exists and outputs are available)."
  exit 2
fi

describe_validation_pairs() {
  aws acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --region "$ACM_REGION" \
    --output json \
    | python3 -c "
import json, sys
j = json.load(sys.stdin)
opts = j.get('Certificate', {}).get('DomainValidationOptions') or []
for o in opts:
    rr = o.get('ResourceRecord') or {}
    n, v = rr.get('Name'), rr.get('Value')
    if n and v:
        print(n.strip() + chr(9) + v.strip())
"
}

check_once() {
  local status
  status="$(aws acm describe-certificate \
    --certificate-arn "$CERT_ARN" \
    --region "$ACM_REGION" \
    --query 'Certificate.Status' \
    --output text 2>/dev/null || true)"

  if [[ -z "$status" ]]; then
    tf_warn "Failed to describe certificate $CERT_ARN in $ACM_REGION (credentials / region?)."
    return 1
  fi

  tf_log "ACM certificate status: $status"

  if [[ "$status" == "ISSUED" ]]; then
    tf_log "Certificate is Issued — run ./scripts/tf-apply.sh to create CloudFront and complete Terraform."
    return 0
  fi

  tf_log "Not Issued yet ($status). Compare records at your DNS host to ./scripts/tf-output.sh (acm_validation_records) or the ACM console."

  if command -v dig >/dev/null 2>&1; then
    tf_log "Public DNS (dig) for ACM validation names — values should match ACM (often *.acm-validations.aws.):"
    local line name expected
    while IFS=$'\t' read -r name expected; do
      [[ -z "$name" ]] && continue
      dig_out=""
      dig_out="$(dig +short "$name" CNAME 2>/dev/null | head -1 || true)"
      dig_out="${dig_out%.}"
      expected="${expected%.}"
      if [[ -n "$dig_out" ]]; then
        tf_log "  $name → $dig_out"
        if [[ "$dig_out" == "$expected" ]] || [[ "$dig_out" == "${expected}." ]]; then
          tf_log "    (matches expected value)"
        fi
      else
        tf_log "  $name → (no CNAME from this resolver yet)"
      fi
    done < <(describe_validation_pairs)
  else
    tf_log "Install dig (bind-tools / dnsutils) to see resolver checks here, or use the ACM console."
  fi

  return 1
}

attempt=1
while true; do
  if check_once; then
    exit 0
  fi
  if [[ "$DO_WAIT" -ne 1 ]]; then
    tf_log "Re-run this script after a few minutes, or use: $(basename "$0") --wait"
    exit 1
  fi
  if [[ "$attempt" -ge "$WAIT_ATTEMPTS" ]]; then
    tf_warn "Still not Issued after $((WAIT_ATTEMPTS * WAIT_INTERVAL_SEC))s of --wait. Fix DNS or wait longer, then run again."
    exit 1
  fi
  tf_log "Waiting ${WAIT_INTERVAL_SEC}s before attempt $((attempt + 1))/${WAIT_ATTEMPTS} (--wait) ..."
  sleep "$WAIT_INTERVAL_SEC"
  attempt=$((attempt + 1))
done
