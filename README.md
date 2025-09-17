# AWS PHP Lambda API - Terraform Starter

A compact, **learning-first** starter for running a PHP API on **AWS Lambda** behind **API Gateway (HTTP API v2)** using **Terraform**.
It favors reproducible builds, minimal IAM, structured access logs, and a clean Makefile workflow. Use it as a foundation and extend later.

---

## Quick Start

```bash
# Choose target environment (default: development)
export ENV=development
export AWS_REGION=eu-central-1

# Build PHP artifact (composer install + deterministic ZIP)
make build

# Create/Update infrastructure and deploy Lambda for the selected ENV
make deploy

# Get URL(s) and try the sample endpoints
make url
make hello-url
make hello
make ping

# Show recent logs for the Lambda function
make logs

# Update Lambda + infra after code/config change
make update

# Destroy all resources for the selected ENV
make down
```

> Run `make help` to see all available targets.

---

## Goals & Non-Goals

**Goals**

* Minimal, framework-free PHP handler (`app/public/index.php`) for Lambda via **Bref**.
* Reproducible builds (Composer lock + deterministic ZIP).
* Clear separation of **environments** (`infra/<env>`) and a reusable Terraform **module** (`infra/modules/api`).
* Useful observability out of the box (structured API Gateway access logs, Lambda logs).

**Non-Goals (now)**

* Full framework, CORS/auth middleware, or advanced error handling.
  This is intentionally simple and meant for learning and as a seed project.

---

## Stack Overview

* **Compute**: AWS Lambda (PHP via **Bref** layer)
* **Ingress**: API Gateway **HTTP API v2**
* **IaC**: Terraform (module under `infra/modules/api` + per-env configs under `infra/<env>`)
* **Packaging**: Composer + ZIP artifact
* **Logging**: CloudWatch Logs (Lambda + API Gateway access logs)
* **Language**: PHP 8.x (CLI for build, FPM at runtime via Bref)

---

## Directory Layout

```
build/
  app.zip            # Build artifact (generated; ignored by Git)

app/
  public/
    index.php        # Single-file PHP handler (Hello, Ping, 404)
  vendor/            # Composer deps (generated)
  composer.json
  composer.lock

infra/
  development/       # Example environment (Terraform runs with -chdir here)
    main.tf          # Wires env variables to the module (timeout, memory, layer ARN, etc.)
    variables.tf     # Optional env-level vars
  staging/ …
  qa/ …
  production/ …
  modules/
    api/
      main.tf        # Lambda + API Gateway + permissions + log groups
      variables.tf   # Module inputs (timeout, memory_size, ephemeral_storage, bref_layer_arn, etc.)
      outputs.tf     # Module outputs (API URLs, function name, etc.)

Makefile             # Build & deploy workflow
```

---

## Prerequisites

* **Terraform** `>= 1.13.x`
* **AWS CLI** (configured credentials/profile)
* **PHP** + **Composer**
* **zip** (for packaging), **jq** (optional; used by `make hello`)
* Network access to AWS for your selected region

---

## Configuration & Environments

### Switching environments

Each environment has its own folder under `infra/`:

```bash
# default is development
make deploy                # uses ENV=development
make deploy ENV=staging    # switches to infra/staging
```

Terraform is executed with `-chdir=infra/$(ENV)`, so each env keeps its own state and outputs.

### Important Makefile variables

* `ENV` — target environment folder (default: `development`)
* `AWS_REGION` — e.g., `eu-central-1` (overridable)
* `LOG_SINCE` — how far back to fetch logs with `make logs` (default: `5m`)

### Key module inputs (set in `infra/<env>/main.tf`)

* `memory_size` (default **128** MB)
* `timeout` (default **10** seconds)
* `ephemeral_storage` (default **512** MB)
* `provisioned_concurrency` (default **0**; when `> 0`, a provisioned concurrency config is applied)
* `bref_layer_arn` (match **region** + **architecture**)
* `architecture` (`x86_64` or `arm64`; keep consistent with the layer)
* `log_retention_days` (CloudWatch retention for Lambda and API Gateway logs)

### API Gateway access logs

The module configures a `$default` stage with **structured JSON** access logs in CloudWatch (request ID, route key, HTTP status, source IP, user agent, time/timeEpoch, protocol, response length, integration errors). Great for tracing and debugging.

### IAM

The Lambda execution role attaches **`AWSLambdaBasicExecutionRole`** and the Lambda invoke permission is restricted to your API execution ARN (`source_arn`). Extend with additional **narrow** policies only when required.

---

## Build & Deploy Lifecycle

### Build (deterministic ZIP)

```bash
make build
```

* Runs `composer install` with production flags.
* Creates a **deterministic** ZIP at the project root: `build/app.zip`.

### Deploy / Update / Destroy

```bash
make deploy   # build + terraform init + apply
make update   # build + terraform init + apply
make down     # terraform destroy
```

Note: Validation steps are intentionally not part of deploy/update. Run 'make validate' manually if you want to lint Composer/PHP/Terraform.

**Outputs**

```bash
make url          # base URL
make hello-url    # /hello URL
make hello        # GET /hello (pretty prints via jq if available)
make ping         # GET /ping
```

**Logs**

```bash
make logs         # recent Lambda logs from CloudWatch
```

### Make targets (full list)

High-level:
- help — Show help and common usage examples
- clean — Remove build artifacts (build/)
- deps — Install PHP dependencies for production (--no-dev)
- build — Build production ZIP at build/app.zip
- deploy — Build + terraform init + apply (no validation)
- update — Rebuild ZIP + terraform init + apply (no validation)
- down — Destroy all resources for the selected ENV
- url — Print the API base URL for the selected ENV
- hello-url — Print the /hello URL for the selected ENV
- hello — Call /hello (pretty-prints via jq if available)
- ping — Call /ping (raw)
- logs — Show Lambda logs from the last LOG_SINCE (no tail)

Terraform helpers:
- tf-init — Run "terraform init" for the selected ENV
- tf-plan — Run "terraform plan" for the selected ENV
- tf-apply — Run "terraform apply" for the selected ENV (requires build/app.zip)
- tf-destroy — Run "terraform destroy" for the selected ENV
- tf-output — Show all Terraform outputs for the selected ENV

Quality tools (optional):
- validate — Composer validate, PHP lint, Terraform fmt -check & validate (requires init)
- composer-audit — Composer security audit against composer.lock
- fmt — Terraform fmt recursively under infra/

---

## Runtime Behavior & Observability

* **Lambda logs**: Monolog writes JSON lines to **stderr** (picked up by CloudWatch).
* **Access logs**: API Gateway `$default` stage emits structured JSON to CloudWatch.
* **Routes**: `/hello` returns a greeting with a timestamp; `/ping` returns `{ "pong": true }`; unknown routes return JSON 404.

---

## Reproducibility & State

* **Composer**: `composer.lock` is versioned → repeatable PHP builds.
* **Terraform**: commit `.terraform.lock.hcl` per environment for provider pinning.
* **Remote state (recommended for teams)**: switch to S3 + DynamoDB lock (example):

```hcl
terraform {
  backend "s3" {
    bucket         = "my-tfstate-bucket"
    key            = "aws-php-lambda-api-terraform/development/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "my-tf-locks"
    encrypt        = true
  }
}
```

For learning, local state is OK—avoid concurrent applies from multiple machines.

---

## Customization Notes

* **Runtime & Layers**: adjust `bref_layer_arn` and `architecture` per environment.
* **Sizing**: tune `memory_size`, `timeout`, `ephemeral_storage`, `provisioned_concurrency`.
* **Routes & Logic**: the demo uses a tiny, single-file `index.php`. Later you can introduce PSR-7/15, DI container, and routing.

---

## Costs & Cleanup

This project provisions billable AWS resources (API Gateway, Lambda, CloudWatch).
Run `make down` when done to avoid ongoing charges.

---

## Troubleshooting

* **`hello_url` not found** → Run `make deploy` first; outputs exist after a successful apply.
* **HTTP 404** → Only `/hello` and `/ping` exist. Unknown routes return JSON 404.
* **Access denied** → Check AWS credentials/profile/region and IAM policy attachments.
* **Layer/Arch mismatch** → Ensure `bref_layer_arn` matches your selected `architecture` and region.

---

## References

* Bref (PHP on Lambda) — [https://bref.sh/](https://bref.sh/)
* AWS Lambda — [https://docs.aws.amazon.com/lambda/](https://docs.aws.amazon.com/lambda/)
* API Gateway HTTP API (v2) — [https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api.html)
* Terraform AWS Provider — [https://registry.terraform.io/providers/hashicorp/aws/latest](https://registry.terraform.io/providers/hashicorp/aws/latest)
* Terraform Backends — [https://developer.hashicorp.com/terraform/language/settings/backends/s3](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
* Monolog — [https://github.com/Seldaek/monolog](https://github.com/Seldaek/monolog)

---

## License

**Do anything you want with this code. No warranties of any kind.**
