#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./demo-day-common.sh
source "$SCRIPT_DIR/demo-day-common.sh"

WAIT_FOR_RDS=true
SKIP_RDS=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--no-wait-for-rds] [--skip-rds]

Starts the RDS instance if needed and restores the ECS demo services to the
desired counts captured by pause-demo.sh. If no saved state exists, each
service is resumed at desired count 1.

Environment overrides:
  AWS_PROFILE
  AWS_DEFAULT_REGION / AWS_REGION
  ECS_CLUSTER_NAME
  DB_INSTANCE_IDENTIFIER
  DEMO_STATE_FILE
  PROJECT_NAME
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-wait-for-rds)
      WAIT_FOR_RDS=false
      ;;
    --skip-rds)
      SKIP_RDS=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

require_command aws

if load_saved_state "$DEMO_STATE_FILE"; then
  log "Loaded saved state from $DEMO_STATE_FILE"
else
  log "No saved state found at $DEMO_STATE_FILE. Falling back to desired count 1 for each service."
fi

CLUSTER_NAME=${ECS_CLUSTER_NAME:-$(resolve_cluster_name)}
DB_IDENTIFIER=${DB_INSTANCE_IDENTIFIER:-$(resolve_db_instance_identifier)}

if [[ "$SKIP_RDS" == false ]]; then
  DB_STATUS=$(aws_cli rds describe-db-instances \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  case "$DB_STATUS" in
    available)
      log "RDS instance $DB_IDENTIFIER is already available."
      ;;
    starting)
      log "RDS instance $DB_IDENTIFIER is already starting."
      ;;
    stopped)
      log "Starting RDS instance $DB_IDENTIFIER"
      aws_cli rds start-db-instance --db-instance-identifier "$DB_IDENTIFIER" >/dev/null
      ;;
    *)
      log "RDS instance $DB_IDENTIFIER is in status $DB_STATUS. Continuing without a new start request."
      ;;
  esac

  if [[ "$WAIT_FOR_RDS" == true ]]; then
    log "Waiting for RDS instance $DB_IDENTIFIER to become available"
    aws_cli rds wait db-instance-available --db-instance-identifier "$DB_IDENTIFIER"
  fi
else
  log "Skipping RDS start request."
fi

log "Restoring ECS services in cluster $CLUSTER_NAME"
for service_name in "${SERVICES[@]}"; do
  desired_key=$(desired_key_for_service "$service_name")
  desired_count=${!desired_key:-1}

  aws_cli ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$service_name" \
    --desired-count "$desired_count" \
    >/dev/null
done

aws_cli ecs wait services-stable --cluster "$CLUSTER_NAME" --services "${SERVICES[@]}"
print_service_counts "$CLUSTER_NAME"

log "Resume complete."
