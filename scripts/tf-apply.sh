#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/terraform-common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options to terraform apply...]

Apply changes. Loads config/aws.env when present.

For a new stack, run ./scripts/tf-apply-phase1.sh first (add ACM DNS CNAMEs, then
./scripts/check-acm-dns.sh), then use this script to finish — see README.

Examples:
  $(basename "$0")
  $(basename "$0") -auto-approve
  $(basename "$0") tfplan
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

tf_log "→ terraform apply (full stack; after phase 1 + DNS, completes validation and CloudFront)"
terraform_common_exec apply "$@"
