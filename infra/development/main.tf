locals {
  project_name = "aws-php-lambda-api-terraform"
  environment  = "development"
  owner        = "John Doe"
  common_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
    Owner       = local.owner
  }
}

module "api" {
  source          = "../modules/api"
  project_name    = local.project_name
  app_env         = local.environment
  aws_region      = var.aws_region
  lambda_zip_path = var.lambda_zip_path

  # Bref layer ARN (see: https://bref.sh/docs/runtimes/runtimes-details)
  bref_layer_arn = var.bref_layer_arn

  # Per-environment architecture ("x86_64" or "arm64")
  architecture = var.architecture

  # Other tunables
  memory_size        = 128
  timeout            = 10
  log_retention_days = 7

  # Enable CORS to test from localhost during development if needed
  enable_cors = true

  # Attach Lambda to the DB VPC (no NAT / no internet required)
  enable_vpc      = true
  vpc_id          = module.db.vpc_id
  vpc_subnet_ids  = module.db.private_subnet_ids

  # Provide DB connection details for PDO
  db_host = module.db.writer_endpoint
  db_name = module.db.database_name

  env_vars = {
    APP_TZ      = "Europe/Budapest"
    LOG_LEVEL   = "debug"
    DB_SSLMODE  = "require"
    DB_USER     = var.db_username
    DB_PASSWORD = var.db_password
  }

  tags = local.common_tags
}

output "api_base_url" {
  value = module.api.api_base_url
}

output "hello_url" {
  value = module.api.hello_url
}

output "lambda_function_name" {
  value = module.api.lambda_function_name
}

module "db" {
  source       = "../modules/aurora_dataapi"
  project_name = local.project_name
  app_env      = local.environment
  aws_region   = var.aws_region

  engine_version = var.aurora_engine_version

  # Development capacity: min 0.5 to 2 ACUs (Aurora Serverless v2)
  min_acu = 0.5
  max_acu = 2

  database_name             = "aurora_postgresql_db"
  master_username           = var.db_username
  master_password           = var.db_password
  create_final_snapshot     = false
  tags                  = local.common_tags
}

# Allow Lambda to connect to the DB on 5432 inside the VPC
resource "aws_security_group_rule" "lambda_to_db" {
  type                     = "ingress"
  description              = "Allow Lambda to connect to Aurora on 5432"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.db.db_security_group_id
  source_security_group_id = module.api.lambda_security_group_id
}
