#!/usr/bin/env bash

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${ROOT_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd)}"
TERRAFORM_DIR="${TERRAFORM_DIR:-"$ROOT_DIR/infra/terraform"}"
BACKUP_STATE_FILE="${BACKUP_STATE_FILE:-"$TERRAFORM_DIR/terraform.tfstate.backup"}"
IMAGE_ENV_FILE="${IMAGE_ENV_FILE:-"$ROOT_DIR/.destroy-demo-images.env"}"
PROJECT_NAME="${PROJECT_NAME:-aws-modernized-demo}"

SERVICES=("order-service" "inventory-service" "notification-service")

if [[ -z "${AWS_PROFILE:-}" && -n "${WS_PROFILE:-}" ]]; then
  export AWS_PROFILE="$WS_PROFILE"
fi

log() {
  printf '%s\n' "$*" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing required command: $1"
    exit 1
  fi
}

current_region() {
  printf '%s\n' "${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-2}}"
}

aws_cli() {
  local region
  region="$(current_region)"

  if [[ -n "${AWS_PROFILE:-}" ]]; then
    aws --profile "$AWS_PROFILE" --region "$region" --no-cli-pager "$@"
  else
    aws --region "$region" --no-cli-pager "$@"
  fi
}

aws_account_id() {
  if [[ -n "${AWS_ACCOUNT_ID_CACHE:-}" ]]; then
    printf '%s\n' "$AWS_ACCOUNT_ID_CACHE"
    return 0
  fi

  AWS_ACCOUNT_ID_CACHE="$(aws_cli sts get-caller-identity --query 'Account' --output text 2>/dev/null || true)"
  printf '%s\n' "$AWS_ACCOUNT_ID_CACHE"
}

terraform_init() {
  terraform -chdir="$TERRAFORM_DIR" init -input=false >/dev/null
}

terraform_output_raw() {
  local output_name="$1"
  local outputs_json=""

  outputs_json="$(terraform -chdir="$TERRAFORM_DIR" output -json 2>/dev/null || true)"
  [[ -n "$outputs_json" ]] || return 0

  printf '%s' "$outputs_json" | jq -r --arg output_name "$output_name" '.[$output_name].value // empty'
}

tf_state_has() {
  terraform -chdir="$TERRAFORM_DIR" state list 2>/dev/null | grep -qx "$1"
}

tf_state_attr() {
  local resource="$1"
  local attribute="$2"

  terraform -chdir="$TERRAFORM_DIR" state show -no-color "$resource" 2>/dev/null \
    | awk -F' = ' -v key="$attribute" '$1 ~ "^[[:space:]]*" key "$" {gsub(/"/, "", $2); print $2; exit}'
}

backup_task_image() {
  local task_name="$1"
  local container_name="$2"

  [[ -f "$BACKUP_STATE_FILE" ]] || return 1

  jq -r \
    --arg task_name "$task_name" \
    --arg container_name "$container_name" \
    '.resources[]
      | select(.type=="aws_ecs_task_definition" and .name==$task_name)
      | .instances[0].attributes.container_definitions' \
    "$BACKUP_STATE_FILE" \
    | jq -r --arg container_name "$container_name" '.[] | select(.name==$container_name) | .image' \
    | head -n 1
}

latest_ecr_image() {
  local repository_name="$1"
  local image_json="" image_digest="" image_tag="" account_id="" region=""

  image_json="$(aws_cli ecr describe-images \
    --repository-name "$repository_name" \
    --query 'sort_by(imageDetails,& imagePushedAt)[-1]' \
    --output json 2>/dev/null || true)"
  [[ -n "$image_json" && "$image_json" != "null" ]] || return 1

  image_digest="$(printf '%s' "$image_json" | jq -r '.imageDigest // empty')"
  image_tag="$(printf '%s' "$image_json" | jq -r '.imageTags[0] // empty')"
  account_id="$(aws_account_id)"
  region="$(current_region)"

  if [[ -n "$image_digest" ]]; then
    printf '%s.dkr.ecr.%s.amazonaws.com/%s@%s\n' "$account_id" "$region" "$repository_name" "$image_digest"
    return 0
  fi

  if [[ -n "$image_tag" ]]; then
    printf '%s.dkr.ecr.%s.amazonaws.com/%s:%s\n' "$account_id" "$region" "$repository_name" "$image_tag"
    return 0
  fi

  return 1
}

load_image_env_file() {
  if [[ -f "$IMAGE_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$IMAGE_ENV_FILE"
  fi
}

is_valid_image_ref() {
  local value="$1"

  [[ -n "$value" ]] || return 1
  [[ "$value" != *$'\n'* ]] || return 1
  [[ "$value" != *$'\r'* ]] || return 1
  [[ "$value" != *$'\033'* ]] || return 1
  [[ "$value" != *'Warning:'* ]] || return 1
  [[ "$value" == */* ]] || return 1
  [[ "$value" == *:* || "$value" == *@sha256:* ]] || return 1

  return 0
}

image_ref_exists() {
  local value="$1"
  local rest repo digest tag

  if [[ "$value" != *.amazonaws.com/* ]]; then
    return 0
  fi

  rest="${value#*.amazonaws.com/}"

  if [[ "$rest" == *"@sha256:"* ]]; then
    repo="${rest%@*}"
    digest="${rest#*@}"
    aws_cli ecr describe-images \
      --repository-name "$repo" \
      --image-ids "imageDigest=$digest" \
      >/dev/null 2>&1
    return $?
  fi

  repo="${rest%:*}"
  tag="${rest##*:}"
  aws_cli ecr describe-images \
    --repository-name "$repo" \
    --image-ids "imageTag=$tag" \
    >/dev/null 2>&1
}

resolve_image() {
  local env_name="$1"
  local output_name="$2"
  local task_name="$3"
  local container_name="$4"
  local value=""

  if is_valid_image_ref "${!env_name:-}" && image_ref_exists "${!env_name:-}"; then
    printf '%s\n' "${!env_name}"
    return 0
  fi

  load_image_env_file
  if is_valid_image_ref "${!env_name:-}" && image_ref_exists "${!env_name:-}"; then
    printf '%s\n' "${!env_name}"
    return 0
  fi

  value="$(terraform_output_raw "$output_name")"
  if is_valid_image_ref "$value" && image_ref_exists "$value"; then
    printf '%s\n' "$value"
    return 0
  fi

  value="$(backup_task_image "$task_name" "$container_name" || true)"
  if is_valid_image_ref "$value" && image_ref_exists "$value"; then
    printf '%s\n' "$value"
    return 0
  fi

  value="$(latest_ecr_image "$container_name" || true)"
  if is_valid_image_ref "$value"; then
    printf '%s\n' "$value"
    return 0
  fi

  return 1
}

write_image_env_file() {
  local region="$1"
  local order_image="$2"
  local inventory_image="$3"
  local notification_image="$4"

  cat >"$IMAGE_ENV_FILE" <<EOF
export AWS_DEFAULT_REGION='$region'
export ORDER_SERVICE_IMAGE='$order_image'
export INVENTORY_SERVICE_IMAGE='$inventory_image'
export NOTIFICATION_SERVICE_IMAGE='$notification_image'
EOF

  log "Saved image variables to $IMAGE_ENV_FILE"
}

purge_secret_if_scheduled_for_deletion() {
  local secret_name="$1"
  local deleted_date=""
  local attempt

  deleted_date="$(aws_cli secretsmanager describe-secret \
    --secret-id "$secret_name" \
    --query 'DeletedDate' \
    --output text 2>/dev/null || true)"

  if [[ -z "$deleted_date" || "$deleted_date" == "None" ]]; then
    return 0
  fi

  log "Secret $secret_name is scheduled for deletion. Restoring and force deleting it to release the name."

  aws_cli secretsmanager restore-secret \
    --secret-id "$secret_name" \
    >/dev/null 2>&1 || true

  aws_cli secretsmanager delete-secret \
    --secret-id "$secret_name" \
    --force-delete-without-recovery \
    >/dev/null

  for attempt in $(seq 1 30); do
    if ! aws_cli secretsmanager describe-secret --secret-id "$secret_name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  log "Secret $secret_name still exists after force delete."
  return 1
}

resolve_cluster_name() {
  local cluster_name="${ECS_CLUSTER_NAME:-}"

  if [[ -n "$cluster_name" ]]; then
    printf '%s\n' "$cluster_name"
    return 0
  fi

  cluster_name="$(terraform_output_raw ecs_cluster_name)"
  if [[ -n "$cluster_name" ]]; then
    printf '%s\n' "$cluster_name"
    return 0
  fi

  printf '%s\n' "${PROJECT_NAME}-cluster"
}

wait_for_services_stable() {
  local cluster_name="$1"

  aws_cli ecs wait services-stable --cluster "$cluster_name" --services "${SERVICES[@]}"
}

print_service_counts() {
  local cluster_name="$1"

  aws_cli ecs describe-services \
    --cluster "$cluster_name" \
    --services "${SERVICES[@]}" \
    --query 'services[].[serviceName,desiredCount,runningCount,pendingCount]' \
    --output table
}

retry_command() {
  local attempts="$1"
  local delay_seconds="$2"
  shift 2

  local attempt
  for attempt in $(seq 1 "$attempts"); do
    if "$@"; then
      return 0
    fi

    if [[ "$attempt" -lt "$attempts" ]]; then
      sleep "$delay_seconds"
    fi
  done

  return 1
}
