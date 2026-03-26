#!/usr/bin/env bash
# Prints where and how to check ACM certificate status in the AWS Console (no AWS CLI required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/terraform-common.sh"

TF_SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
ACM_REGION="${ACM_REGION:-us-east-1}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

After ./scripts/tf-apply-phase1.sh and adding ACM validation CNAMEs at your DNS host:

  Open AWS Certificate Manager in region ${ACM_REGION} (required for CloudFront) and
  refresh the certificate page periodically until Status is Issued.

  This script does not call AWS; it only prints the console link and next steps.

Optional:

  --wait    Accepted for compatibility; same message (check ACM periodically yourself).

Environment: ACM_REGION (default ${ACM_REGION})
EOF
}

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "--wait" ]]; then
  tf_log "Note: --wait does not poll AWS from this script — check the ACM console periodically until Issued."
fi

tf_log "After your validation CNAMEs are saved at your DNS host, check certificate status in the AWS Console:"
tf_log "  Certificate Manager — region: ${ACM_REGION} (CloudFront certificates must use us-east-1)"
tf_log "  https://console.aws.amazon.com/acm/home?region=${ACM_REGION}#/certificates"
tf_log ""
tf_log "Refresh the page every few minutes until Status is Issued."
tf_log "Validation record details: ./scripts/tf-output.sh (output acm_validation_records)."
tf_log "When Issued, run: ./scripts/tf-apply.sh"

exit 0
