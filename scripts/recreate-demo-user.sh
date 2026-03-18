#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./stack-lifecycle-common.sh
source "$SCRIPT_DIR/stack-lifecycle-common.sh"

export AWS_PAGER="${AWS_PAGER:-}"

USERNAME="${AWS_DEMO_USERNAME:-demo-user}"
PASSWORD="${AWS_DEMO_PASSWORD:-DemoPassw0rd!}"
EMAIL="${AWS_DEMO_EMAIL:-demo-user@example.com}"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Creates or updates the Cognito demo user after terraform apply.

Environment overrides:
  AWS_PROFILE
  AWS_DEFAULT_REGION / AWS_REGION
  AWS_DEMO_USERNAME
  AWS_DEMO_PASSWORD
  AWS_DEMO_EMAIL
EOF
}

wait_for_user_pool_id() {
  local attempt user_pool_id

  for attempt in $(seq 1 30); do
    user_pool_id="$(terraform_output_raw cognito_user_pool_id)"
    if [[ -n "$user_pool_id" ]]; then
      printf '%s\n' "$user_pool_id"
      return 0
    fi
    sleep 5
  done

  return 1
}

user_exists() {
  aws_cli cognito-idp admin-get-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$USERNAME" \
    >/dev/null 2>&1
}

create_or_update_user() {
  if user_exists; then
    aws_cli cognito-idp admin-update-user-attributes \
      --user-pool-id "$USER_POOL_ID" \
      --username "$USERNAME" \
      --user-attributes \
        "Name=email,Value=$EMAIL" \
        "Name=email_verified,Value=true" \
      >/dev/null
    return 0
  fi

  aws_cli cognito-idp admin-create-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$USERNAME" \
    --message-action SUPPRESS \
    --user-attributes \
      "Name=email,Value=$EMAIL" \
      "Name=email_verified,Value=true" \
    >/dev/null
}

set_password() {
  aws_cli cognito-idp admin-set-user-password \
    --user-pool-id "$USER_POOL_ID" \
    --username "$USERNAME" \
    --password "$PASSWORD" \
    --permanent \
    >/dev/null
}

enable_user_if_needed() {
  aws_cli cognito-idp admin-enable-user \
    --user-pool-id "$USER_POOL_ID" \
    --username "$USERNAME" \
    >/dev/null 2>&1 || true
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_command terraform
  require_command aws
  require_command jq
  terraform_init

  USER_POOL_ID="$(wait_for_user_pool_id)" || {
    log "Could not resolve Cognito user pool ID from terraform outputs."
    return 1
  }

  retry_command 12 5 create_or_update_user
  enable_user_if_needed
  retry_command 12 5 set_password
  retry_command 12 5 user_exists

  cat <<EOF
Recreated Cognito demo user.
username=$USERNAME
email=$EMAIL
userPoolId=$USER_POOL_ID
EOF
}

main "$@"
