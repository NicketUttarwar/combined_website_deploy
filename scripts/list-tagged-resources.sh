#!/usr/bin/env bash
set -euo pipefail

# Lists resources tagged with TAG_KEY=TAG_VALUE via Resource Groups Tagging API.
# Default region: us-east-1 (single region for this stack).
# Optional: set LIST_TAG_REGIONS to scan additional regions.
# Defaults: TAG_KEY=Project, TAG_VALUE from terraform output project_tag_value if state exists.
# If aws CLI is missing, prints a notice and runs terraform state list.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/terraform-common.sh"

# Optional: USE_LATEST_SESSION=1 — align live state with rolling backup before reading outputs
terraform_common_filter_session_args "$@"
terraform_common_maybe_restore_session

TAG_KEY="${TAG_KEY:-Project}"
TAG_VALUE="${TAG_VALUE:-}"

tf_log "Listing AWS resources by tag (Resource Groups Tagging API)"
tf_log "TAG_KEY=${TAG_KEY} (override with TAG_KEY=...)"

if [[ -z "$TAG_VALUE" ]]; then
  tf_log "TAG_VALUE unset — trying terraform output project_tag_value (quiet, no full wrapper log)..."
  if command -v terraform >/dev/null 2>&1; then
    TAG_VALUE="$(cd "$REPO_ROOT" && terraform -chdir="$TF_DIR" output -raw project_tag_value 2>/dev/null || true)"
  else
    tf_warn "terraform not in PATH; cannot read output"
  fi
fi
# Matches terraform/variables.tf default project_name when state/outputs are unavailable.
if [[ -z "$TAG_VALUE" ]]; then
  TAG_VALUE="combined-site"
  tf_log "Using default TAG_VALUE=${TAG_VALUE}"
else
  tf_log "TAG_VALUE=${TAG_VALUE}"
fi

if ! command -v aws >/dev/null 2>&1; then
  tf_warn "aws CLI not found — falling back to terraform state list"
  terraform_common_exec_local state list
  exit 0
fi

LIST_TAG_REGIONS="${LIST_TAG_REGIONS:-us-east-1}"
tf_log "Regions: ${LIST_TAG_REGIONS} (set LIST_TAG_REGIONS to add more)"

for region in $LIST_TAG_REGIONS; do
  tf_log "Querying ${region}..."
  echo "=== Resource Groups Tagging API (${region}) — ${TAG_KEY}=${TAG_VALUE} ===" >&2
  aws resourcegroupstaggingapi get-resources \
    --region "$region" \
    --tag-filters "Key=${TAG_KEY},Values=${TAG_VALUE}" \
    --output table
done

tf_log "Done."
