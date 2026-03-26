#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/terraform-common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--check]

Run terraform fmt and terraform validate.
Does not load config/aws.env (not required for syntax checks).

terraform validate does not accept -var-file; it checks configuration without applying variable files.
If no tfvars file exists, a placeholder TF_VAR_s3_bucket_name is set so validate can succeed.

  --check        Run fmt in check mode only (non-zero exit if changes needed)
  --use-session  Restore live state from session backup before fmt/validate (or set USE_LATEST_SESSION=1)
EOF
}

FMT_ARGS=()
CHECK_MODE=false
for arg in "$@"; do
  case "$arg" in
    -h | --help)
      usage
      exit 0
      ;;
    --check)
      CHECK_MODE=true
      ;;
    --use-session)
      export USE_LATEST_SESSION=1
      tf_log "USE_LATEST_SESSION=1 (restore from latest session backup before fmt/validate)"
      ;;
    *)
      FMT_ARGS+=("$arg")
      ;;
  esac
done

tf_log "terraform fmt + validate (syntax only; config/aws.env not loaded)"
if [[ "$CHECK_MODE" == true ]]; then
  tf_log "fmt mode: -check (non-zero if files need reformatting)"
fi

if [[ "$CHECK_MODE" == true ]]; then
  if [[ ${#FMT_ARGS[@]} -eq 0 ]]; then
    terraform_common_exec_local fmt -check -recursive
  else
    terraform_common_exec_local fmt -check -recursive "${FMT_ARGS[@]}"
  fi
else
  if [[ ${#FMT_ARGS[@]} -eq 0 ]]; then
    terraform_common_exec_local fmt -recursive
  else
    terraform_common_exec_local fmt -recursive "${FMT_ARGS[@]}"
  fi
fi

if ! terraform_common_effective_var_file_path >/dev/null 2>&1; then
  export TF_VAR_s3_bucket_name="${TF_VAR_s3_bucket_name:-terraform-fmt-validate-placeholder-bucket}"
  tf_log "validate: no terraform.tfvars — using TF_VAR_s3_bucket_name=${TF_VAR_s3_bucket_name}"
fi
terraform_common_warn_if_terraform_cli_not_native_arm64
terraform_common_warn_if_aws_provider_arch_mismatch
terraform_common_exec_local validate
tf_log "fmt + validate finished."
