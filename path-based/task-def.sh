#!/bin/bash

# ==========================================================
# Bulk Delete ECS Task Definitions
# Reads task definition ARNs from stdin
# For each:
#   - Describe
#   - Deregister
#   - Delete permanently
# ==========================================================

set -euo pipefail

if [ -t 0 ]; then
  echo "No input detected."
  echo "Usage:"
  echo "aws ecs list-task-definitions --status ACTIVE --query 'taskDefinitionArns[]' --output text | \\"
  echo "  tr '\t' '\n' | ./bulk-delete-ecs-taskdefs.sh"
  exit 1
fi

while read -r TASK_DEF_ARN; do
  if [ -z "$TASK_DEF_ARN" ]; then
    continue
  fi

  echo "===================================================="
  echo "Processing: $TASK_DEF_ARN"
  echo "===================================================="

  echo "Describing..."
  DESCRIBE_OUTPUT=$(aws ecs describe-task-definition \
    --task-definition "$TASK_DEF_ARN" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text 2>/dev/null || true)

  if [ -z "$DESCRIBE_OUTPUT" ] || [ "$DESCRIBE_OUTPUT" == "None" ]; then
    echo "Skipping (not found)."
    continue
  fi

  echo "Deregistering..."
  aws ecs deregister-task-definition \
    --task-definition "$TASK_DEF_ARN"

  echo "Deleting permanently..."
  aws ecs delete-task-definitions \
    --task-definitions "$TASK_DEF_ARN"

  echo "Done."
  echo

done

echo "All task definitions processed."