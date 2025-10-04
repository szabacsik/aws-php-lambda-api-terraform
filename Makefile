SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# ---------- PHONY ----------
.PHONY: help clean build deps tf-init tf-plan tf-apply tf-destroy tf-output deploy update down url hello-url hello ping logs validate composer-audit fmt

# ---------- Config ----------
ENV ?= development
AWS_REGION ?= eu-central-1
LOG_SINCE ?= 5m

TF_DIR := infra/$(ENV)
APP_DIR := app
BUILD_DIR := build
ZIP := $(BUILD_DIR)/app.zip              # Zip path relative to project root
ZIP_ABS := $(abspath $(ZIP))

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
	echo ""; \
	echo "Quality tools (optional, recommended to run manually before commits):"; \
	echo "  validate            - Composer validate, PHP lint, Terraform fmt -check & validate (requires init)"; \
	echo "  composer-audit      - Composer security audit against composer.lock"; \
	echo "  fmt                 - Terraform fmt recursively under infra/"; \
	echo ""; \
	echo "Environment selection:"; \
	echo "  Use ENV=<env> to target an environment (default: development)."; \
	echo "  Example: make deploy ENV=staging";

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
	terraform -chdir=$(TF_DIR) init

tf-plan:
	terraform -chdir=$(TF_DIR) plan -var="aws_region=$(AWS_REGION)" -var="lambda_zip_path=$(ZIP_ABS)"

tf-apply:
	@test -f $(ZIP) || (echo "ERROR: $(ZIP) is missing. Run 'make build'."; exit 1)
	terraform -chdir=$(TF_DIR) apply -auto-approve -var="aws_region=$(AWS_REGION)" -var="lambda_zip_path=$(ZIP_ABS)"

tf-destroy:
	terraform -chdir=$(TF_DIR) destroy -auto-approve -var="aws_region=$(AWS_REGION)" -var="lambda_zip_path=$(ZIP_ABS)"

tf-output:
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
