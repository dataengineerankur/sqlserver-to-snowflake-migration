#!/usr/bin/env bash
# After SQL Server secret has a reachable host/user/password, test both endpoints and start CDC task.
set -euo pipefail
: "${AWS_PROFILE:?Set AWS_PROFILE}"
REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$REGION"

RI_ARN="$(aws dms describe-replication-instances --query 'ReplicationInstances[0].ReplicationInstanceArn' --output text)"
SQL_ARN="$(aws dms describe-endpoints --filters Name=engine-name,Values=sqlserver --query 'Endpoints[0].EndpointArn' --output text)"
S3_ARN="$(aws dms describe-endpoints --filters Name=engine-name,Values=s3 --query 'Endpoints[0].EndpointArn' --output text)"
TASK_ARN="$(aws dms describe-replication-tasks --without-settings --query 'ReplicationTasks[0].ReplicationTaskArn' --output text)"

echo "Replication instance: $RI_ARN"
echo "Starting connection tests..."
aws dms test-connection --replication-instance-arn "$RI_ARN" --endpoint-arn "$S3_ARN" >/dev/null
aws dms test-connection --replication-instance-arn "$RI_ARN" --endpoint-arn "$SQL_ARN" >/dev/null

for _ in $(seq 1 36); do
  s3="$(aws dms describe-connections --query "Connections[?EndpointArn=='${S3_ARN}'].Status | [0]" --output text)"
  sql="$(aws dms describe-connections --query "Connections[?EndpointArn=='${SQL_ARN}'].Status | [0]" --output text)"
  echo "S3: $s3  SQL: $sql"
  if [[ "$s3" == "successful" && "$sql" == "successful" ]]; then
    echo "Both tests successful. Starting replication task..."
    aws dms start-replication-task \
      --replication-task-arn "$TASK_ARN" \
      --start-replication-task-type start-replication \
      --query 'ReplicationTask.Status' --output text
    exit 0
  fi
  if [[ "$s3" == "failed" || "$sql" == "failed" ]]; then
    echo "A connection test failed. Check DMS console or:"
    aws dms describe-connections --query "Connections[?EndpointArn=='${SQL_ARN}' || EndpointArn=='${S3_ARN}'].[EndpointIdentifier,Status,LastFailureMessage]" --output table
    exit 1
  fi
  sleep 10
done

echo "Timed out waiting for connection tests."
exit 1
