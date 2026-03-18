#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
TERRAFORM_DIR=${TERRAFORM_DIR:-"$ROOT_DIR/infra/terraform"}
DEMO_STATE_FILE=${DEMO_STATE_FILE:-"$ROOT_DIR/.demo-day-state.env"}
PROJECT_NAME=${PROJECT_NAME:-aws-modernized-demo}
AWS_REGION=${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-2}}

SERVICES=("order-service" "inventory-service" "notification-service")

log() {
  printf '%s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1" >&2
    exit 1
  fi
}

aws_cli() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    aws --profile "$AWS_PROFILE" --region "$AWS_REGION" "$@"
  else
    aws --region "$AWS_REGION" "$@"
  fi
}

terraform_output_raw() {
  local name=$1

  if ! command -v terraform >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -d "$TERRAFORM_DIR" ]]; then
    return 0
  fi

  terraform -chdir="$TERRAFORM_DIR" output -raw "$name" 2>/dev/null || true
}

resolve_cluster_name() {
  local cluster_name=${ECS_CLUSTER_NAME:-}

  if [[ -n "$cluster_name" ]]; then
    printf '%s\n' "$cluster_name"
    return
  fi

  cluster_name=$(terraform_output_raw ecs_cluster_name)
  if [[ -n "$cluster_name" ]]; then
    printf '%s\n' "$cluster_name"
    return
  fi

  printf '%s\n' "${PROJECT_NAME}-cluster"
}

resolve_db_instance_identifier() {
  local db_identifier=${DB_INSTANCE_IDENTIFIER:-}

  if [[ -n "$db_identifier" ]]; then
    printf '%s\n' "$db_identifier"
    return
  fi

  db_identifier=$(terraform_output_raw db_instance_identifier)
  if [[ -n "$db_identifier" ]]; then
    printf '%s\n' "$db_identifier"
    return
  fi

  printf '%s\n' "${PROJECT_NAME}-postgres"
}

desired_key_for_service() {
  local service_name=$1
  printf '%s_DESIRED\n' "$(printf '%s' "$service_name" | tr '[:lower:]-' '[:upper:]_')"
}

print_service_counts() {
  local cluster_name=$1
  aws_cli ecs describe-services \
    --cluster "$cluster_name" \
    --services "${SERVICES[@]}" \
    --query 'services[].[serviceName,desiredCount,runningCount,pendingCount]' \
    --output table
}

save_current_service_state() {
  local cluster_name=$1
  local db_identifier=$2
  local state_file=$3

  {
    printf 'AWS_REGION=%s\n' "$AWS_REGION"
    printf 'ECS_CLUSTER_NAME=%s\n' "$cluster_name"
    printf 'DB_INSTANCE_IDENTIFIER=%s\n' "$db_identifier"
  } > "$state_file"

  while IFS=$'\t' read -r service_name desired_count; do
    [[ -z "$service_name" ]] && continue
    printf '%s=%s\n' "$(desired_key_for_service "$service_name")" "$desired_count" >> "$state_file"
  done < <(
    aws_cli ecs describe-services \
      --cluster "$cluster_name" \
      --services "${SERVICES[@]}" \
      --query 'services[].[serviceName,desiredCount]' \
      --output text
  )
}

load_saved_state() {
  local state_file=$1

  if [[ -f "$state_file" ]]; then
    # shellcheck disable=SC1090
    source "$state_file"
    return 0
  fi

  return 1
}
