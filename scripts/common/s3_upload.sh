#!/usr/bin/env bash
set -euo pipefail

# Generic S3 / Cloudflare R2 / Aliyun OSS uploader using AWS CLI
# Required environment variables:
# - S3_BUCKET: Name of the bucket (e.g., my-updates-bucket)
# - S3_ENDPOINT_URL: (Optional) Custom endpoint for R2 or OSS (e.g., https://<account_id>.r2.cloudflarestorage.com)
# - AWS_ACCESS_KEY_ID: S3 access key
# - AWS_SECRET_ACCESS_KEY: S3 secret key

LOCAL_FILE="${1:-}"
REMOTE_PATH="${2:-}"

if [ -z "$LOCAL_FILE" ] || [ -z "$REMOTE_PATH" ]; then
  echo "Usage: $0 <local_file> <remote_path>" >&2
  exit 1
fi

if [ -z "${S3_BUCKET:-}" ]; then
  echo "Error: S3_BUCKET environment variable is required" >&2
  exit 1
fi

ENDPOINT_ARG=""
if [ -n "${S3_ENDPOINT_URL:-}" ]; then
  ENDPOINT_ARG="--endpoint-url=$S3_ENDPOINT_URL"
fi

DEST_URI="s3://${S3_BUCKET}/${REMOTE_PATH}"

echo "==> Uploading $LOCAL_FILE to $DEST_URI ..."
aws s3 cp "$LOCAL_FILE" "$DEST_URI" $ENDPOINT_ARG --acl public-read || \
aws s3 cp "$LOCAL_FILE" "$DEST_URI" $ENDPOINT_ARG

echo "==> Upload completed: $DEST_URI"
