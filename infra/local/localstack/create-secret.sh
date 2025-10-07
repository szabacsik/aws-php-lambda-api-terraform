#!/usr/bin/env bash
# Create the local DB secret in LocalStack to mimic AWS Secrets Manager
set -euo pipefail
echo "[LocalStack] Creating Secrets Manager secret: local/db/master"
awslocal secretsmanager create-secret --name local/db/master --secret-string '{"username":"app_user","password":"app_pass"}' >/dev/null 2>&1 || true
echo "[LocalStack] Done."
