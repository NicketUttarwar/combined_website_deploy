#!/usr/bin/env bash
# Run repository checks: shell syntax, Terraform fmt/validate, combined/ HTTP smoke test.
# Optional: RUN_TERRAFORM_PLAN=1 ./scripts/run-tests.sh — runs terraform plan (needs valid AWS credentials).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/terraform-common.sh"

cd "$REPO_ROOT"

tf_log "======== run-tests: repository verification ========"
tf_log "Repository root: $REPO_ROOT"

tf_log "Step 1/4: bash -n (syntax) on all scripts under scripts/"
while IFS= read -r -d '' f; do
  bash -n "$f"
  tf_log "  OK $(basename "$f")"
done < <(find "$SCRIPT_DIR" -maxdepth 1 -name '*.sh' -print0; find "$SCRIPT_DIR/lib" -name '*.sh' -print0 2>/dev/null)

tf_log "Step 2/4: terraform fmt --check + validate (./scripts/tf-fmt-validate.sh --check)"
export TF_VAR_s3_bucket_name="${TF_VAR_s3_bucket_name:-run-tests-placeholder-bucket}"
./scripts/tf-fmt-validate.sh --check

tf_log "Step 3/4: combined/ static site — HTTP 200 checks (python3 test_site.py)"
PORT="${TEST_HTTP_PORT:-8765}"
tf_log "Starting temporary http.server on 127.0.0.1:${PORT} (serving combined/)"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$REPO_ROOT/combined" >/dev/null 2>&1 &
HTTP_PID=$!
cleanup() { kill "$HTTP_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 0.5
BASE="http://127.0.0.1:${PORT}" python3 "$REPO_ROOT/combined/test_site.py"
tf_log "HTTP checks passed."

tf_log "Step 4/4: optional terraform plan (RUN_TERRAFORM_PLAN=1)"
if [[ "${RUN_TERRAFORM_PLAN:-}" == "1" ]]; then
  if [[ -f "$REPO_ROOT/config/aws.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$REPO_ROOT/config/aws.env"
    set +a
  fi
  if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -z "${AWS_PROFILE:-}" ]] && [[ -z "${AWS_CONTAINER_CREDENTIALS_RELATIVE_URI:-}" ]] && [[ -z "${AWS_WEB_IDENTITY_TOKEN_FILE:-}" ]]; then
    tf_log "Skipping terraform plan: no AWS credentials (config/aws.env or standard AWS env vars)."
  else
    tf_log "Running ./scripts/tf-plan.sh -input=false -refresh=false"
    ./scripts/tf-plan.sh -input=false -refresh=false
  fi
else
  tf_log "Skipping terraform plan (set RUN_TERRAFORM_PLAN=1 to include; needs AWS credentials)."
fi

tf_log "======== run-tests: all steps completed successfully ========"
