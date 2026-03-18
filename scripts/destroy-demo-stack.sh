#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./stack-lifecycle-common.sh
source "$SCRIPT_DIR/stack-lifecycle-common.sh"

export AWS_PAGER="${AWS_PAGER:-}"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Safely destroys the AWS demo stack. The script:
  1. resolves the current image URIs
  2. saves them into .destroy-demo-images.env
  3. runs terraform destroy
  4. cleans up AppConfig and Cloud Map leftovers if the provider hits known AWS edge cases

Environment overrides:
  AWS_PROFILE
  AWS_DEFAULT_REGION / AWS_REGION
  ORDER_SERVICE_IMAGE
  INVENTORY_SERVICE_IMAGE
  NOTIFICATION_SERVICE_IMAGE
EOF
}

has_appconfig_state() {
  tf_state_has aws_appconfig_application.runtime \
    || tf_state_has aws_appconfig_environment.demo \
    || tf_state_has aws_appconfig_configuration_profile.runtime
}

run_destroy() {
  local order_image inventory_image notification_image region

  region="$(current_region)"
  order_image="$(resolve_image ORDER_SERVICE_IMAGE order_service_image order order-service)" || {
    log "Could not resolve order-service image. Export ORDER_SERVICE_IMAGE and retry."
    return 1
  }
  inventory_image="$(resolve_image INVENTORY_SERVICE_IMAGE inventory_service_image inventory inventory-service)" || {
    log "Could not resolve inventory-service image. Export INVENTORY_SERVICE_IMAGE and retry."
    return 1
  }
  notification_image="$(resolve_image NOTIFICATION_SERVICE_IMAGE notification_service_image notification notification-service)" || {
    log "Could not resolve notification-service image. Export NOTIFICATION_SERVICE_IMAGE and retry."
    return 1
  }

  write_image_env_file "$region" "$order_image" "$inventory_image" "$notification_image"

  terraform -chdir="$TERRAFORM_DIR" destroy -auto-approve -lock-timeout=5m \
    -var "aws_region=$region" \
    -var "order_service_image=$order_image" \
    -var "inventory_service_image=$inventory_image" \
    -var "notification_service_image=$notification_image"
}

state_rm_if_present() {
  local resource

  for resource in "$@"; do
    if tf_state_has "$resource"; then
      terraform -chdir="$TERRAFORM_DIR" state rm "$resource" >/dev/null
    fi
  done
}

cleanup_appconfig() {
  local application_id environment_id configuration_profile_id

  application_id="$(tf_state_attr aws_appconfig_application.runtime id || true)"
  environment_id="$(tf_state_attr aws_appconfig_environment.demo environment_id || true)"
  configuration_profile_id="$(tf_state_attr aws_appconfig_configuration_profile.runtime configuration_profile_id || true)"

  [[ -n "$application_id" ]] || return 0

  log "Cleaning up AppConfig resources with deletion protection bypass."

  if [[ -n "$configuration_profile_id" ]]; then
    aws_cli appconfig delete-configuration-profile \
      --application-id "$application_id" \
      --configuration-profile-id "$configuration_profile_id" \
      --deletion-protection-check BYPASS \
      >/dev/null 2>&1 || true
  fi

  if [[ -n "$environment_id" ]]; then
    aws_cli appconfig delete-environment \
      --application-id "$application_id" \
      --environment-id "$environment_id" \
      --deletion-protection-check BYPASS \
      >/dev/null 2>&1 || true
  fi

  aws_cli appconfig delete-application \
    --application-id "$application_id" \
    >/dev/null 2>&1 || true

  if [[ -n "$configuration_profile_id" ]] \
    && ! aws_cli appconfig get-configuration-profile \
      --application-id "$application_id" \
      --configuration-profile-id "$configuration_profile_id" \
      >/dev/null 2>&1; then
    state_rm_if_present aws_appconfig_configuration_profile.runtime
  fi

  if [[ -n "$environment_id" ]] \
    && ! aws_cli appconfig get-environment \
      --application-id "$application_id" \
      --environment-id "$environment_id" \
      >/dev/null 2>&1; then
    state_rm_if_present aws_appconfig_environment.demo
  fi

  if ! aws_cli appconfig get-application --application-id "$application_id" >/dev/null 2>&1; then
    state_rm_if_present aws_appconfig_application.runtime
    state_rm_if_present aws_appconfig_deployment.runtime aws_appconfig_hosted_configuration_version.runtime
  fi
}

wait_for_namespace_delete() {
  local operation_id="$1"
  local status=""
  local attempt

  for attempt in $(seq 1 24); do
    status="$(aws_cli servicediscovery get-operation \
      --operation-id "$operation_id" \
      --query 'Operation.Status' \
      --output text 2>/dev/null || true)"

    case "$status" in
      SUCCESS)
        return 0
        ;;
      FAIL)
        return 1
        ;;
      PENDING|SUBMITTED|"")
        sleep 5
        ;;
      *)
        sleep 5
        ;;
    esac
  done

  return 1
}

cleanup_cloud_map() {
  local namespace_id service_ids delete_result operation_id

  namespace_id="$(tf_state_attr aws_service_discovery_private_dns_namespace.services id || true)"
  [[ -n "$namespace_id" ]] || return 0

  log "Cleaning up Cloud Map namespace leftovers."

  service_ids="$(aws_cli servicediscovery list-services \
    --filters "Name=NAMESPACE_ID,Values=$namespace_id,Condition=EQ" \
    --query 'Services[].Id' \
    --output text 2>/dev/null || true)"

  for service_id in $service_ids; do
    [[ -n "$service_id" ]] || continue
    aws_cli servicediscovery delete-service --id "$service_id" >/dev/null 2>&1 || true
  done

  sleep 5

  delete_result="$(aws_cli servicediscovery delete-namespace --id "$namespace_id" 2>/dev/null || true)"
  operation_id="$(printf '%s' "$delete_result" | jq -r '.OperationId // empty')"

  if [[ -n "$operation_id" ]]; then
    if wait_for_namespace_delete "$operation_id"; then
      state_rm_if_present aws_service_discovery_private_dns_namespace.services
    else
      log "Cloud Map namespace delete is still pending; terraform retry will handle the remainder."
    fi
    return 0
  fi

  if ! aws_cli servicediscovery get-namespace --id "$namespace_id" >/dev/null 2>&1; then
    state_rm_if_present aws_service_discovery_private_dns_namespace.services
  fi
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

  if has_appconfig_state; then
    log "Pre-cleaning AppConfig resources to avoid the known terraform provider deletion-protection failure."
    cleanup_appconfig
  fi

  if run_destroy; then
    log "Terraform destroy completed cleanly."
    return 0
  fi

  log "Terraform destroy hit AWS cleanup edge cases. Running manual AppConfig and Cloud Map cleanup, then retrying."

  cleanup_appconfig
  cleanup_cloud_map

  run_destroy
}

main "$@"
