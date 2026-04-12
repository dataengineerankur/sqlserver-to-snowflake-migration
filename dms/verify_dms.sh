#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DMS_TASK_ID:-}" ]]; then
  echo "Set DMS_TASK_ID to the replication task id."
  exit 1
fi

if [[ -z "${DMS_BUCKET:-}" ]]; then
  echo "Set DMS_BUCKET to the S3 bucket name."
  exit 1
fi

echo "Checking DMS task status..."
aws dms describe-replication-tasks \
  --filters "Name=replication-task-id,Values=${DMS_TASK_ID}" \
  --query "ReplicationTasks[0].{Status:Status,LastFailure:LastFailureMessage}" \
  --output table

echo "Listing recent S3 objects..."
aws s3 ls "s3://${DMS_BUCKET}/dms/sales/" --recursive | tail -n 20
