# AWS PHP Lambda API - Terraform Starter

A compact, **learning-first** starter for running a PHP API on **AWS Lambda** behind **API Gateway (HTTP API v2)** using **Terraform**.
It favors reproducible builds, minimal IAM, structured access logs, and a clean Makefile workflow. Use it as a foundation and extend later. It now includes an Amazon Aurora PostgreSQL Serverless v2 database (private subnets, TLS enforced, PDO over VPC, no NAT & no Data API).

---

## Quick Start

```bash
# Choose target environment (default: development)
export ENV=development
export AWS_REGION=eu-central-1
# Optional: store Terraform state in a separate slug/region when forking
# export TF_STATE_PROJECT=my-php-api
# export TF_STATE_REGION=eu-west-1

# One-time: create the remote Terraform state bucket + DynamoDB lock table
make bootstrap-remote-state

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
* **Database**: Amazon Aurora PostgreSQL **Serverless v2** (private subnets, TLS enforced, min 0.5 ACU, **PDO over VPC**, **no NAT**, **no Data API**)

---

## Database (Aurora PostgreSQL Serverless v2)

**What we use (and why):**
- **Engine**: Amazon **Aurora PostgreSQL Serverless v2** in **private subnets**, no Internet exposure.
- **Connectivity**: The Lambda talks to the cluster via **PDO** (TCP) inside the VPC. **No RDS Data API**.
- **Cost/scaling**: v2 auto-scales between **0.5–4 ACU** (configurable). v2 does **not** scale to zero, but 0.5 ACU is the lowest floor in eu-central-1.
- **Security**: **TLS required** (`rds.force_ssl=1`), the app connects with `sslmode=require`. DB credentials are in **AWS Secrets Manager**.
- **No NAT**: The Lambda reaches Secrets Manager via a **VPC Interface Endpoint** (private DNS). No NAT Gateway is created.

**Pros (why this fits the goals):**
- Minimal ops: fully managed, auto-scaling capacity; credentials in Secrets Manager.
- Lower idle cost: 0.5 ACU minimum floor; pay more only under load.
- Private by default: no public ingress to the DB; traffic stays inside the VPC.

**Trade-offs / Cons:**
- Not scale-to-zero (there is always a 0.5 ACU baseline).
- Connection storms from Lambda can hurt cold-path latency under spikes (RDS Proxy can help later).
- Engine version pinned for now (17.4); can be made dynamic per region in a future iteration.

### Where and how to configure

- **Terraform — DB module**: `infra/modules/aurora_dataapi/`
  - `main.tf` — Aurora cluster + parameter group (`rds.force_ssl=1`), private subnets, SGs.
  - `variables.tf` — `aurora_engine_version`, `min_acu`, `max_acu`.
  - `outputs.tf` — `writer_endpoint`, `reader_endpoint`, `secret_arn`, `database_name`, `vpc_id`, `private_subnet_ids`, `db_security_group_id`.
- **Terraform — API module**: `infra/modules/api/`
  - Attaches Lambda to VPC; injects env vars: `DB_HOST`, `DB_PORT` (5432), `DB_NAME`, `DB_SECRET_ARN`.
  - IAM inline policy allows `secretsmanager:GetSecretValue` (account-scoped).
- **Terraform — per environment**: `infra/<env>/main.tf`
  - Wires the DB and API modules together; creates the **Secrets Manager VPC endpoint**.
- **Application code**:
  - `app/src/Presentation/Http/Action/DefaultAction.php` — sample PDO connection + two queries (`now()` & `SHOW server_version`), TLS via `sslmode=require`.
  - **PDO_PGSQL** is enabled via `app/php/conf.d/php.ini` and must be included in the ZIP (Makefile does this).

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

## Local development (infra/local)

A minimal, prod-like local stack to work fast without AWS:
- HTTP: Bref dev web server (image: bref/php-84-fpm-dev:2.3.34) on http://localhost:8000
- DB: PostgreSQL 17.4 (official image)
- AWS emulation: LocalStack (Secrets Manager only)
- Code mount: your ./app is mounted read-only into /var/task (Lambda-like layout)

Why it matches production closely:
- Same PHP runtime lineage (Bref FPM) and filesystem shape (/var/task)
- Same Secrets Manager flow (the app uses AWS_SM_ENDPOINT to talk to LocalStack)
- DB version parity: PostgreSQL 17.4; database name: aurora_postgresql_db

Quick start
```bash
cd infra/local
make up
make ping     # http://localhost:8000/hello
make app-logs # or: make logs / make php-logs
```

Available Make targets (local only)
- up, down, restart
- logs, app-logs (alias: php-logs)
- ping (GET /hello), curl (GET /)
- db-cli (psql into the container)
- secret-get (dump the LocalStack secret)

Services (docker-compose.yml)
- api: bref/php-84-fpm-dev:2.3.34
  - Exposes 8000
  - Env for AWS SDK → LocalStack: AWS_SM_ENDPOINT=http://php-lambda-api-localstack:4566
  - DB env: DB_HOST=php-lambda-api-db, DB_PORT=5432, DB_NAME=aurora_postgresql_db, DB_SECRET_ARN=local/db/master
  - TLS locally: DB_SSLMODE=disable (keep require in prod)
- db: postgres:17.4 (user: app_user, pass: app_pass, db: aurora_postgresql_db)
- localstack: localstack/localstack:stable (service enabled: secretsmanager)
  - Init script: infra/local/localstack/create-secret.sh → creates secret local/db/master

Xdebug (enabled)
- The dev image ships with Xdebug enabled. Extra tweaks live in app/php/conf.d/xdebug.ini
  - mode=debug, start_with_request=yes, discover_client_host=1, port=9003
- IDE tips:
  - Listen on 9003
  - Map project root → /var/task
  - If connections don’t arrive on Linux, set xdebug.client_host=host.docker.internal in app/php/conf.d/xdebug.ini and restart containers

Local workflow
1) Start the stack: make up
2) Edit code under ./app — changes are hot‑reloaded (no rebuild needed)
3) Hit http://localhost:8000 (make ping / make curl)
4) Watch logs: make app-logs
5) Inspect DB: make db-cli; Inspect secret: make secret-get

Troubleshooting (local)
- LocalStack init script “Permission denied”
  - chmod +x infra/local/localstack/create-secret.sh
  - make restart
- Check LocalStack health
  - curl -s http://localhost:4566/_localstack/health | jq .
  - Expect secretsmanager to be "running" and version shown
- Secret not found / AWS errors
  - Ensure AWS_SM_ENDPOINT points to LocalStack (compose sets it)
  - make secret-get should print the JSON with username/password
- DB SSL / connection errors
  - Locally sslmode=disable is used; ensure the db container is healthy (docker compose ps)
- Xdebug not hitting IDE
  - Verify port 9003, path mapping to /var/task, and optionally set client_host as above

Note: These local Make targets are intentionally not part of the root Makefile to keep concerns separate.

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
- tflint — Terraform linting (requires tflint)
- tfsec — Terraform security scanning (requires tfsec)

---

## Runtime Behavior & Observability

* **Lambda logs**: Monolog writes JSON lines to **stderr** (picked up by CloudWatch).
* **Access logs**: API Gateway `$default` stage emits structured JSON to CloudWatch.
* **Routes**: `/hello` returns a greeting with a timestamp; `/ping` returns `{ "pong": true }`; unknown routes return JSON 404.

---

## Reproducibility & State

* **Composer**: `composer.lock` is versioned → repeatable PHP builds.
* **Terraform providers**: commit `.terraform.lock.hcl` per environment for provider pinning.
* **Remote state**: Terraform state lives in S3 with DynamoDB-backed locking for every environment.

### Remote Terraform State (S3 + DynamoDB)

Set `TF_STATE_PROJECT` to your fork's slug (default: `aws-php-lambda-api-terraform`). The Makefile derives the bucket name, DynamoDB table, and state keys from that value, so renaming keeps everything in sync.

1. **Bootstrap once per AWS account/region**  
   Run `make bootstrap-remote-state` (override `TF_STATE_REGION` when it differs from `AWS_REGION`). The target checks that the AWS CLI is installed and authenticated, then creates `<slug>-tf-state-<account>-<region>` with SSE-S3 encryption, TLS-only bucket policy, bucket-owner-enforced ACLs, versioning, and a lifecycle rule that retires non-current versions after 90 days. It also provisions `<slug>-tf-locks` in DynamoDB with on-demand billing, point-in-time recovery, and shared tags. Re-running the target is idempotent; adjust tags via `TF_STATE_TAG_*`.
2. **Backend configuration per environment**  
   The Makefile injects `bucket`, `region`, `key=<slug>/<env>/terraform.tfstate`, `dynamodb_table=<slug>-tf-locks`, and `encrypt=true` during `make tf-init`. The `infra/<env>/backend.hcl` files remain optional stubs—extend them only if you need extra backend parameters.
3. **Initialize Terraform with the remote backend**  
   Use `make tf-init` (or `ENV=staging make tf-init`) after bootstrap. No manual edits to the Terraform code are required; the backend binds automatically based on the current environment and slug.
4. **Apply normally**  
   Run `make deploy`, `make update`, or ad-hoc Terraform commands as before—state now lives in S3 and locking is handled by DynamoDB, preventing concurrent applies.
5. **Smoke-test locking & versioning**  
   Open two terminals, run `ENV=development make tf-plan` in one, and trigger a second plan/apply in the other. The second command should block with a lock message. After the first command completes, list S3 object versions for your prefix (for example: `aws s3api list-object-versions --bucket <slug>-tf-state-<account>-<region> --prefix <slug>/<env>/`)—a fresh `VersionId` confirms versioning is active.

State migration tips:
- If `TF_STATE_PROJECT` or `TF_STATE_REGION` changes, run `RECONFIGURE=1 make tf-init` so Terraform re-reads the backend settings.
- When relocating existing state data (bucket or key changes), run `MIGRATE=1 make tf-init` to move the stored state to the new location.

Operational helpers:
- `make state-info` prints the derived bucket, table, and key for the current `ENV`, slug, and AWS account.
- `make tf-force-unlock ID=<lock-id>` releases a stuck DynamoDB lock (only after confirming no other apply is running).
- Terraform CLI invocations default to `-input=false` and wait up to `LOCK_TIMEOUT` (default: `5m`) to acquire the state lock.
- Applies/destroys run with `-auto-approve` unless `ENV=production`; override with `AUTO_APPROVE=1 make tf-apply` when automation is intentional.

Minimal IAM for Terraform state access (substitute your bucket ARN, account ID, and region):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3StateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetObjectVersion",
        "s3:DeleteObjectVersion",
        "s3:ListBucketVersions"
      ],
      "Resource": [
        "arn:aws:s3:::aws-php-lambda-api-terraform-tf-state-123456789012-eu-central-1",
        "arn:aws:s3:::aws-php-lambda-api-terraform-tf-state-123456789012-eu-central-1/*"
      ]
    },
    {
      "Sid": "DynamoStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:eu-central-1:123456789012:table/aws-php-lambda-api-terraform-tf-locks"
    }
  ]
}
```

> Bootstrap requires additional permissions (`s3:CreateBucket`, `s3:PutBucket*`, `s3:PutEncryptionConfiguration`, `dynamodb:CreateTable`, etc.). Run it with elevated credentials once, then grant Terraform the narrower policy above for day-to-day work.
> Update the bucket/table ARNs to match the resources generated from your `TF_STATE_PROJECT` slug and AWS account.

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

## Future improvements (Database)

- **Public access “switch” (rarely needed)**  
  Default remains **private only**. If one-off SQL client access is required, prefer **SSM Session Manager port-forward** or **Client VPN**. As a last resort, introduce **public subnets + IGW** and a conditional DB subnet group — but this increases blast radius and cost.
- **Separate application DB user**  
  Create a least-privileged app user (own Secret) instead of using the master. Reduces risk and aligns with the principle of least privilege.
- **Engine version management (not hard-coded)**  
  Discover the latest supported Aurora PG 17.x per region (e.g., data source or script) and set via variables. Avoids drift when new minor versions land.
- **RDS Proxy**  
  Smooths out connection storms from Lambda, reduces cold-path latency, and improves throughput under spiky load. Comes with extra cost — enable when needed.
- **VPC Flow Logs**  
  Helpful for diagnosing network issues (SGs, subnets, routes). Enable selectively to avoid noise and cost.
- **AWS RDS HTTP API (Data API)**  
  Intentionally **not used** here. Could be enabled for non-VPC clients or when eliminating drivers is desirable — but it adds a different auth and runtime model. For this project, **PDO over VPC** is the explicit choice.

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

# AWS PHP Lambda API with Terraform

This project deploys a PHP API on AWS Lambda behind API Gateway using Terraform.




## Security and networking notes

- **Database security & networking**: see the **Database** section above for TLS, Secrets Manager, and VPC endpoint details.
- **Logging**: CloudWatch receives both Lambda logs and structured API Gateway access logs for easy tracing.
