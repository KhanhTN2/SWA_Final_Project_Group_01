#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

WAIT_FOR_SERVICES=true
RUN_SMOKE_TEST=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [--no-wait] [--smoke-test]

Destroys the current AWS demo stack, reapplies it with the same image URIs,
and recreates the Cognito demo user.

Options:
  --no-wait     Do not wait for ECS services to stabilize after terraform apply
  --smoke-test  Run scripts/run-aws-demo.py after the stack and demo user are ready

Environment overrides:
  AWS_PROFILE
  AWS_DEFAULT_REGION / AWS_REGION
  AWS_DEMO_USERNAME
  AWS_DEMO_PASSWORD
  ORDER_SERVICE_IMAGE
  INVENTORY_SERVICE_IMAGE
  NOTIFICATION_SERVICE_IMAGE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-wait)
      WAIT_FOR_SERVICES=false
      ;;
    --smoke-test)
      RUN_SMOKE_TEST=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

main() {
  local -a apply_args=()
  local correlation_id=""

  "$SCRIPT_DIR/destroy-demo-stack.sh"

  if [[ "$WAIT_FOR_SERVICES" == false ]]; then
    apply_args+=(--no-wait)
  fi

  if ((${#apply_args[@]} > 0)); then
    "$SCRIPT_DIR/apply-demo-stack.sh" "${apply_args[@]}"
  else
    "$SCRIPT_DIR/apply-demo-stack.sh"
  fi
  "$SCRIPT_DIR/recreate-demo-user.sh"

  if [[ "$RUN_SMOKE_TEST" == true ]]; then
    correlation_id="demo-rebuild-$(date +%s)"
    python3 "$SCRIPT_DIR/run-aws-demo.py" --correlation-id "$correlation_id"
  fi
}

main "$@"
