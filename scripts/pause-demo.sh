#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./demo-day-common.sh
source "$SCRIPT_DIR/demo-day-common.sh"

WAIT_FOR_RDS=false
SKIP_RDS=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--wait-for-rds] [--skip-rds]

Scales the ECS demo services to zero and optionally stops the RDS instance.

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
    --wait-for-rds)
      WAIT_FOR_RDS=true
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

CLUSTER_NAME=$(resolve_cluster_name)
DB_IDENTIFIER=$(resolve_db_instance_identifier)

log "Saving current desired counts to $DEMO_STATE_FILE"
save_current_service_state "$CLUSTER_NAME" "$DB_IDENTIFIER" "$DEMO_STATE_FILE"

log "Scaling ECS services in cluster $CLUSTER_NAME to zero"
for service_name in "${SERVICES[@]}"; do
  aws_cli ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$service_name" \
    --desired-count 0 \
    >/dev/null
done

aws_cli ecs wait services-stable --cluster "$CLUSTER_NAME" --services "${SERVICES[@]}"
print_service_counts "$CLUSTER_NAME"

if [[ "$SKIP_RDS" == true ]]; then
  log "Skipping RDS stop request."
else
  DB_STATUS=$(aws_cli rds describe-db-instances \
    --db-instance-identifier "$DB_IDENTIFIER" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text)

  case "$DB_STATUS" in
    stopped|stopping)
      log "RDS instance $DB_IDENTIFIER is already $DB_STATUS."
      ;;
    available)
      log "Stopping RDS instance $DB_IDENTIFIER"
      aws_cli rds stop-db-instance --db-instance-identifier "$DB_IDENTIFIER" >/dev/null
      if [[ "$WAIT_FOR_RDS" == true ]]; then
        log "Waiting for RDS instance $DB_IDENTIFIER to stop"
        aws_cli rds wait db-instance-stopped --db-instance-identifier "$DB_IDENTIFIER"
      else
        log "RDS stop requested. Use --wait-for-rds if you want the script to block until fully stopped."
      fi
      ;;
    *)
      log "RDS instance $DB_IDENTIFIER is in status $DB_STATUS. No stop request submitted."
      ;;
  esac
fi

log "Pause complete."
log "MSK Serverless is still running and still billable. Use 'terraform destroy' if you need to remove Kafka cost entirely."
