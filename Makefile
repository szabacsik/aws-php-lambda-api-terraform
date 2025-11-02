SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# ---------- PHONY ----------
.PHONY: help clean build deps tf-init tf-plan tf-apply tf-destroy tf-output deploy update down url hello-url hello ping logs validate composer-audit fmt bootstrap-remote-state tflint tfsec state-info tf-force-unlock

# ---------- Config ----------
ENV ?= development
AWS_REGION ?= eu-central-1
LOG_SINCE ?= 5m

TF_DIR := infra/$(ENV)
APP_DIR := app
BUILD_DIR := build
ZIP := $(BUILD_DIR)/app.zip              # Zip path relative to project root
ZIP_ABS := $(abspath $(ZIP))

TF_STATE_PROJECT ?= aws-php-lambda-api-terraform
TF_STATE_REGION ?= $(AWS_REGION)
TF_STATE_TAG_PROJECT ?= $(TF_STATE_PROJECT)
TF_STATE_TAG_ENVIRONMENT ?= shared
TF_STATE_TAG_PURPOSE ?= terraform-remote-state
TF_STATE_TAG_MANAGED_BY ?= make-bootstrap
TF_STATE_LOCK_TABLE := $(TF_STATE_PROJECT)-tf-locks
TF_STATE_KEY := $(TF_STATE_PROJECT)/$(ENV)/terraform.tfstate
TF_BACKEND_CONFIG := $(TF_DIR)/backend.hcl
LOCK_TIMEOUT ?= 5m
AUTO_APPROVE ?= 1
ifeq ($(ENV),production)
  AUTO_APPROVE := 0
endif

APPLY_FLAGS := -lock-timeout=$(LOCK_TIMEOUT)
DESTROY_FLAGS := -lock-timeout=$(LOCK_TIMEOUT)
ifeq ($(AUTO_APPROVE),1)
  APPLY_FLAGS += -auto-approve
  DESTROY_FLAGS += -auto-approve
endif

PHP := php
COMPOSER := composer
CURL := curl
JQ ?= jq

# ---------- Help ----------
help:
	@echo "Available commands:"; \
	echo ""; \
	echo "  help                - Show this help and common usage examples"; \
	echo "  clean               - Remove build artifacts (build)"; \
	echo "  deps                - Install PHP dependencies for production (--no-dev)"; \
	echo "  build               - Build production ZIP (composer deps + deterministic zip -> $(ZIP))"; \
	echo "  deploy              - Build + terraform init + apply for the selected ENV (no validation here)"; \
	echo "  update              - Rebuild ZIP + terraform init + apply (no validation here)"; \
	echo "  down                - Destroy all resources for the selected ENV"; \
	echo "  url                 - Print the API base URL for the selected ENV"; \
	echo "  hello-url           - Print the /hello URL for the selected ENV"; \
	echo "  hello               - Call /hello once and print the response (pretty if jq exists)"; \
	echo "  ping                - Call /ping once and print the raw response (no formatting)"; \
	echo "  logs                - Show Lambda logs from the last $(LOG_SINCE) (no tail)"; \
	echo ""; \
	echo "Terraform helpers:"; \
	echo "  tf-init             - Run 'terraform init' for the selected ENV"; \
	echo "  tf-plan             - Run 'terraform plan' for the selected ENV"; \
	echo "  tf-apply            - Run 'terraform apply' for the selected ENV"; \
	echo "  tf-destroy          - Run 'terraform destroy' for the selected ENV"; \
	echo "  tf-output           - Show all Terraform outputs for the selected ENV"; \
	echo "  tf-force-unlock     - Force-unlock Terraform state (provide ID=<lock-id>)"; \
	echo ""; \
	echo "Quality tools (optional, recommended to run manually before commits):"; \
	echo "  validate            - Composer validate, PHP lint, Terraform fmt -check & validate (requires init)"; \
	echo "  composer-audit      - Composer security audit against composer.lock"; \
	echo "  fmt                 - Terraform fmt recursively under infra/"; \
	echo "  tflint              - Terraform linting (requires tflint)"; \
	echo "  tfsec               - Terraform security scanning (requires tfsec)"; \
	echo ""; \
	echo "Environment selection:"; \
	echo "  Use ENV=<env> to target an environment (default: development)."; \
	echo "  Example: make deploy ENV=staging"; \
	echo "  Override TF_STATE_REGION to place Terraform state in a different region.";
	@echo ""; \
	echo "Remote state bootstrap:"; \
	echo "  bootstrap-remote-state - Create/verify S3 bucket and DynamoDB lock table for Terraform state"; \
	echo "  state-info             - Print derived remote state resources for the current context";

# ---------- App build ----------
clean:
	rm -rf $(BUILD_DIR)

deps:
	cd $(APP_DIR) && \
	$(COMPOSER) install --no-dev --prefer-dist --no-interaction --optimize-autoloader --classmap-authoritative

build: clean deps
	mkdir -p $(BUILD_DIR)
	cd $(APP_DIR) && \
	rm -f $(ZIP_ABS) && \
	zip -X -9 -qr $(ZIP_ABS) public src vendor php composer.json composer.lock
	@echo "Built $(ZIP)"

# ---------- Terraform lifecycle ----------
tf-init:
	@set -euo pipefail; \
	if [[ ! "$(TF_STATE_PROJECT)" =~ ^[a-z0-9-]+$$ ]]; then \
		echo "Invalid TF_STATE_PROJECT: only lowercase letters, digits and hyphens are allowed."; \
		exit 1; \
	fi; \
	if ! command -v aws >/dev/null 2>&1; then \
		echo "AWS CLI is required. Install it from https://aws.amazon.com/cli/"; \
		exit 1; \
	fi; \
	if ! command -v terraform >/dev/null 2>&1; then \
		echo "Terraform is required. Install from https://developer.hashicorp.com/terraform/downloads"; \
		exit 1; \
	fi; \
	STATE_REGION="$(TF_STATE_REGION)"; \
	export AWS_DEFAULT_REGION="$$STATE_REGION"; \
	if ! aws sts get-caller-identity >/dev/null 2>&1; then \
		echo "AWS CLI credentials not found. Run 'aws configure', export AWS_PROFILE, or supply env vars."; \
		exit 1; \
	fi; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	STATE_BUCKET="$(TF_STATE_PROJECT)-tf-state-$$ACCOUNT_ID-$$STATE_REGION"; \
	BACKEND_FILE_FLAG=""; \
	if [ -f "$(TF_BACKEND_CONFIG)" ]; then \
		if grep -q '^[[:space:]]*[^#[:space:]]' "$(TF_BACKEND_CONFIG)"; then \
			BACKEND_FILE_FLAG="-backend-config=$(TF_BACKEND_CONFIG)"; \
		fi; \
	fi; \
	INIT_ARGS=("-input=false"); \
	if [ "${RECONFIGURE:-}" = "1" ]; then \
		INIT_ARGS+=("-reconfigure"); \
	fi; \
	if [ "${MIGRATE:-}" = "1" ]; then \
		INIT_ARGS+=("-migrate-state"); \
	fi; \
	if [ -n "$$BACKEND_FILE_FLAG" ]; then \
		INIT_ARGS+=("$${BACKEND_FILE_FLAG}"); \
	fi; \
	echo "Initializing Terraform backend with bucket $$STATE_BUCKET in $$STATE_REGION"; \
	terraform -chdir=$(TF_DIR) init \
		"$${INIT_ARGS[@]}" \
		-backend-config="bucket=$$STATE_BUCKET" \
		-backend-config="region=$$STATE_REGION" \
		-backend-config="key=$(TF_STATE_KEY)" \
		-backend-config="dynamodb_table=$(TF_STATE_LOCK_TABLE)" \
		-backend-config="encrypt=true"

tf-plan:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required. Install from https://developer.hashicorp.com/terraform/downloads"; exit 1; }
	terraform -chdir=$(TF_DIR) plan -input=false -lock-timeout=$(LOCK_TIMEOUT) -var="aws_region=$(AWS_REGION)" -var="lambda_zip_path=$(ZIP_ABS)"

tf-apply:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required. Install from https://developer.hashicorp.com/terraform/downloads"; exit 1; }
	@test -f $(ZIP) || (echo "ERROR: $(ZIP) is missing. Run 'make build'."; exit 1)
	terraform -chdir=$(TF_DIR) apply -input=false $(APPLY_FLAGS) -var="aws_region=$(AWS_REGION)" -var="lambda_zip_path=$(ZIP_ABS)"

tf-destroy:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required. Install from https://developer.hashicorp.com/terraform/downloads"; exit 1; }
	terraform -chdir=$(TF_DIR) destroy -input=false $(DESTROY_FLAGS) -var="aws_region=$(AWS_REGION)" -var="lambda_zip_path=$(ZIP_ABS)"

tf-output:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required. Install from https://developer.hashicorp.com/terraform/downloads"; exit 1; }
	terraform -chdir=$(TF_DIR) output

# ---------- High-level commands ----------
# Note: we intentionally keep validation OUT of these flows to keep deploys fast and simple.
deploy: build tf-init tf-apply
update: build tf-init tf-apply
down: tf-destroy

url:
	@terraform -chdir=$(TF_DIR) output -raw api_base_url

hello-url:
	@terraform -chdir=$(TF_DIR) output -raw hello_url

# Call /hello and pretty-print if jq is available
hello:
	@URL=$$(terraform -chdir=$(TF_DIR) output -raw hello_url 2>/dev/null || true); \
	if [ -z "$$URL" ]; then echo "hello_url output not found. Did you run 'make deploy'?"; exit 1; fi; \
	echo "GET $$URL"; \
	$(CURL) -sS "$$URL" | { $(JQ) . 2>/dev/null || cat; }

# Call /ping and print raw response (no formatting)
ping:
	@BASE=$$(terraform -chdir=$(TF_DIR) output -raw api_base_url 2>/dev/null || true); \
	if [ -z "$$BASE" ]; then echo "api_base_url output not found. Did you run 'make deploy'?"; exit 1; fi; \
	URL="$$BASE/ping"; \
	$(CURL) -sS "$$URL"

logs:
	@FUNC=$$(terraform -chdir=$(TF_DIR) output -raw lambda_function_name); \
	echo "Logs for $$FUNC (last $(LOG_SINCE)):"; \
	aws logs tail "/aws/lambda/$$FUNC" --since $(LOG_SINCE) --region $(AWS_REGION)

# ---------- Validation & audit (optional) ----------
validate:
	cd $(APP_DIR) && $(COMPOSER) validate --no-interaction
	$(PHP) -l $(APP_DIR)/public/index.php
	# Requires terraform init beforehand if providers/modules are not installed:
	terraform -chdir=$(TF_DIR) fmt -check
	terraform -chdir=$(TF_DIR) validate

composer-audit:
	cd $(APP_DIR) && composer audit --no-interaction --locked

fmt:
	terraform fmt -recursive infra

tflint:
	@set -euo pipefail; \
	if ! command -v tflint >/dev/null 2>&1; then \
		echo "tflint not found. Install from https://github.com/terraform-linters/tflint/releases."; \
		exit 1; \
	fi; \
	echo "Running tflint against $(TF_DIR)…"; \
	tflint --version >/dev/null 2>&1; \
	tflint --chdir=$(TF_DIR)

tfsec:
	@set -euo pipefail; \
	if ! command -v tfsec >/dev/null 2>&1; then \
		echo "tfsec not found. Install from https://github.com/aquasecurity/tfsec/releases."; \
		exit 1; \
	fi; \
	echo "Running tfsec recursively on infra/…"; \
	tfsec infra

# ---------- Terraform backend bootstrap ----------
bootstrap-remote-state:
	@set -euo pipefail; \
	if [[ ! "$(TF_STATE_PROJECT)" =~ ^[a-z0-9-]+$$ ]]; then \
		echo "Invalid TF_STATE_PROJECT: only lowercase letters, digits and hyphens are allowed."; \
		exit 1; \
	fi; \
	if ! command -v aws >/dev/null 2>&1; then \
		echo "AWS CLI is required. Install it from https://aws.amazon.com/cli/"; \
		exit 1; \
	fi; \
	echo "Bootstrapping remote state in AWS…"; \
	STATE_REGION="$(TF_STATE_REGION)"; \
	export AWS_DEFAULT_REGION="$$STATE_REGION"; \
	if ! aws sts get-caller-identity >/dev/null 2>&1; then \
		echo "AWS CLI credentials not found. Run 'aws configure', export AWS_PROFILE, or supply env vars."; \
		exit 1; \
	fi; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text); \
	STATE_BUCKET="$(TF_STATE_PROJECT)-tf-state-$$ACCOUNT_ID-$$STATE_REGION"; \
	LOCK_TABLE="$(TF_STATE_LOCK_TABLE)"; \
	echo "Using S3 bucket: $$STATE_BUCKET"; \
	if aws s3api head-bucket --bucket "$$STATE_BUCKET" >/dev/null 2>&1; then \
		echo "Bucket already exists, updating configuration…"; \
	else \
		if [ "$$STATE_REGION" = "us-east-1" ]; then \
			aws s3api create-bucket --bucket "$$STATE_BUCKET" --region "$$STATE_REGION"; \
		else \
			aws s3api create-bucket --bucket "$$STATE_BUCKET" --region "$$STATE_REGION" --create-bucket-configuration LocationConstraint="$$STATE_REGION"; \
		fi; \
		echo "Created bucket $$STATE_BUCKET"; \
	fi; \
	aws s3api wait bucket-exists --bucket "$$STATE_BUCKET"; \
	aws s3api put-public-access-block --bucket "$$STATE_BUCKET" --public-access-block-configuration 'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'; \
	aws s3api put-bucket-ownership-controls --bucket "$$STATE_BUCKET" --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'; \
	aws s3api put-bucket-versioning --bucket "$$STATE_BUCKET" --versioning-configuration Status=Enabled; \
	aws s3api put-bucket-encryption --bucket "$$STATE_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'; \
	if command -v jq >/dev/null 2>&1; then \
		LIFECYCLE=$$(jq -n '{Rules:[{ID:"ExpireOldStateVersions",Status:"Enabled",Filter:{Prefix:""},NoncurrentVersionExpiration:{NoncurrentDays:90},AbortIncompleteMultipartUpload:{DaysAfterInitiation:7}}]}'); \
	else \
		LIFECYCLE='{"Rules":[{"ID":"ExpireOldStateVersions","Status":"Enabled","Filter":{"Prefix":""},"NoncurrentVersionExpiration":{"NoncurrentDays":90},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}'; \
	fi; \
	aws s3api put-bucket-lifecycle-configuration --bucket "$$STATE_BUCKET" --lifecycle-configuration "$$LIFECYCLE"; \
	aws s3api put-bucket-tagging --bucket "$$STATE_BUCKET" --tagging 'TagSet=[{Key=Project,Value=$(TF_STATE_TAG_PROJECT)},{Key=Environment,Value=$(TF_STATE_TAG_ENVIRONMENT)},{Key=ManagedBy,Value=$(TF_STATE_TAG_MANAGED_BY)},{Key=Purpose,Value=$(TF_STATE_TAG_PURPOSE)}]'; \
	if command -v jq >/dev/null 2>&1; then \
		POLICY=$$(jq -n --arg bucket "$$STATE_BUCKET" '{Version:"2012-10-17",Statement:[{Sid:"DenyInsecureTransport",Effect:"Deny",Principal:"*",Action:"s3:*",Resource:["arn:aws:s3:::"+$$bucket,"arn:aws:s3:::"+$$bucket+"/*"],Condition:{Bool:{"aws:SecureTransport":"false"}}}]}'); \
	else \
		POLICY=$$(printf '{"Version":"2012-10-17","Statement":[{"Sid":"DenyInsecureTransport","Effect":"Deny","Principal":"*","Action":"s3:*","Resource":["arn:aws:s3:::%s","arn:aws:s3:::%s/*"],"Condition":{"Bool":{"aws:SecureTransport":"false"}}}]}' "$$STATE_BUCKET" "$$STATE_BUCKET"); \
	fi; \
	aws s3api put-bucket-policy --bucket "$$STATE_BUCKET" --policy "$$POLICY"; \
	echo "Using DynamoDB table: $$LOCK_TABLE"; \
	if aws dynamodb describe-table --table-name "$$LOCK_TABLE" >/dev/null 2>&1; then \
		echo "Table already exists, updating configuration…"; \
	else \
		aws dynamodb create-table --table-name "$$LOCK_TABLE" \
			--attribute-definitions AttributeName=LockID,AttributeType=S \
			--key-schema AttributeName=LockID,KeyType=HASH \
			--billing-mode PAY_PER_REQUEST \
			--table-class STANDARD; \
		aws dynamodb wait table-exists --table-name "$$LOCK_TABLE"; \
		echo "Created table $$LOCK_TABLE"; \
	fi; \
	TABLE_ARN=$$(aws dynamodb describe-table --table-name "$$LOCK_TABLE" --query "Table.TableArn" --output text); \
	aws dynamodb tag-resource --resource-arn "$$TABLE_ARN" --tags Key=Project,Value=$(TF_STATE_TAG_PROJECT) Key=Environment,Value=$(TF_STATE_TAG_ENVIRONMENT) Key=ManagedBy,Value=$(TF_STATE_TAG_MANAGED_BY) Key=Purpose,Value=$(TF_STATE_TAG_PURPOSE); \
	aws dynamodb update-continuous-backups --table-name "$$LOCK_TABLE" --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true; \
	echo "Remote state bootstrap complete."; \
	echo "  Bucket     : $$STATE_BUCKET"; \
	echo "  Lock table : $$LOCK_TABLE"

state-info:
	@set -euo pipefail; \
	if ! command -v aws >/dev/null 2>&1; then \
		echo "AWS CLI is required. Install it from https://aws.amazon.com/cli/"; \
		exit 1; \
	fi; \
	STATE_REGION="$(TF_STATE_REGION)"; \
	ACCOUNT_ID=$$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo unknown); \
	STATE_BUCKET="$(TF_STATE_PROJECT)-tf-state-$$ACCOUNT_ID-$$STATE_REGION"; \
	echo "Bucket      : $$STATE_BUCKET"; \
	echo "Region      : $$STATE_REGION"; \
	echo "Lock table  : $(TF_STATE_LOCK_TABLE)"; \
	echo "State key   : $(TF_STATE_KEY)"; \
	echo "ENV         : $(ENV)"

tf-force-unlock:
	@command -v terraform >/dev/null 2>&1 || { echo "Terraform is required. Install from https://developer.hashicorp.com/terraform/downloads"; exit 1; }
	@if [ -z "$(ID)" ]; then echo "Provide ID=<LOCK_ID> (from error message)"; exit 1; fi
	terraform -chdir=$(TF_DIR) force-unlock -force $(ID)
