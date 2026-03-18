#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./stack-lifecycle-common.sh
source "$SCRIPT_DIR/stack-lifecycle-common.sh"

export AWS_PAGER="${AWS_PAGER:-}"

WAIT_FOR_SERVICES=true

usage() {
  cat <<EOF
Usage: $(basename "$0") [--no-wait]

Applies the AWS demo stack using image URIs resolved from:
  1. exported ORDER_SERVICE_IMAGE / INVENTORY_SERVICE_IMAGE / NOTIFICATION_SERVICE_IMAGE
  2. .destroy-demo-images.env
  3. terraform outputs
  4. terraform.tfstate.backup

Environment overrides:
  AWS_PROFILE
  AWS_DEFAULT_REGION / AWS_REGION
  ORDER_SERVICE_IMAGE
  INVENTORY_SERVICE_IMAGE
  NOTIFICATION_SERVICE_IMAGE
  ECS_CLUSTER_NAME
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-wait)
      WAIT_FOR_SERVICES=false
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
  shift
done

main() {
  local order_image inventory_image notification_image region cluster_name
  local db_password_secret_name="${PROJECT_NAME}/db/password"

  require_command terraform
  require_command aws
  require_command jq
  terraform_init

  region="$(current_region)"
  order_image="$(resolve_image ORDER_SERVICE_IMAGE order_service_image order order-service)" || {
    log "Could not resolve order-service image. Export ORDER_SERVICE_IMAGE or run destroy-demo-stack.sh first."
    return 1
  }
  inventory_image="$(resolve_image INVENTORY_SERVICE_IMAGE inventory_service_image inventory inventory-service)" || {
    log "Could not resolve inventory-service image. Export INVENTORY_SERVICE_IMAGE or run destroy-demo-stack.sh first."
    return 1
  }
  notification_image="$(resolve_image NOTIFICATION_SERVICE_IMAGE notification_service_image notification notification-service)" || {
    log "Could not resolve notification-service image. Export NOTIFICATION_SERVICE_IMAGE or run destroy-demo-stack.sh first."
    return 1
  }

  write_image_env_file "$region" "$order_image" "$inventory_image" "$notification_image"

  purge_secret_if_scheduled_for_deletion "$db_password_secret_name"

  terraform -chdir="$TERRAFORM_DIR" apply -auto-approve -lock-timeout=5m \
    -var "aws_region=$region" \
    -var "order_service_image=$order_image" \
    -var "inventory_service_image=$inventory_image" \
    -var "notification_service_image=$notification_image"

  if [[ "$WAIT_FOR_SERVICES" == true ]]; then
    cluster_name="$(resolve_cluster_name)"
    log "Waiting for ECS services in cluster $cluster_name to stabilize."
    wait_for_services_stable "$cluster_name"
    print_service_counts "$cluster_name"
  fi

  log "Terraform apply completed."
}

main "$@"
