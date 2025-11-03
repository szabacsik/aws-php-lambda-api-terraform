locals {
  project_name = "aws-php-lambda-api-terraform"
  environment  = "production"
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

  memory_size        = 10240
  timeout            = 10
  log_retention_days = 14

  # Attach Lambda to the DB VPC (no NAT / no internet required)
  enable_vpc      = true
  vpc_id          = module.db.vpc_id
  vpc_subnet_ids  = module.db.private_subnet_ids

  # Provide DB connection details and secret access for PDO
  db_host                   = module.db.writer_endpoint
  db_name                   = module.db.database_name
  enable_db_secret_access   = true
  db_secret_arn             = module.db.secret_arn

  env_vars = {
    APP_TZ                      = "Europe/Budapest"
    LOG_LEVEL                   = "info"
    AWS_SM_HTTP_CONNECT_TIMEOUT = "2"
    AWS_SM_HTTP_TIMEOUT         = "2"
    DB_SSLMODE                  = "require"
  }

  ssm_parameter_arns = [module.example_parameter.parameter_arn]
  tags               = local.common_tags
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

output "db_secret_arn" {
  value       = module.db.secret_arn
  description = "RDS-managed master secret ARN"
}

module "db" {
  source       = "../modules/aurora_dataapi"
  project_name = local.project_name
  app_env      = local.environment
  aws_region   = var.aws_region

  engine_version = var.aurora_engine_version

  # Production capacity: min 0.5 to 8 ACUs (Aurora Serverless v2)
  min_acu = 0.5
  max_acu = 8

  database_name             = "aurora_postgresql_db"
  create_final_snapshot     = true
  final_snapshot_identifier = "aws-php-lambda-api-terraform-production-aurora-pg-final"
  tags                      = local.common_tags
}

# Provide a baseline SSM Parameter Store entry for cross-environment testing.
module "example_parameter" {
  source       = "../modules/ssm_parameter"
  project_name = local.project_name
  app_env      = local.environment
  name         = "EXAMPLE_PARAMETER"
  value        = "Lorem Ipsum Dolor Sit Amet"
  description  = "Example parameter provisioned by Terraform."
  owner        = local.owner
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

# VPC Interface Endpoint SG for Secrets Manager
resource "aws_security_group" "vpc_endpoints" {
  name   = "aws-php-lambda-api-terraform-production-vpce-sg"
  vpc_id = module.db.vpc_id

  ingress {
    description     = "HTTPS from Lambda to interface endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.api.lambda_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Secrets Manager Interface VPC Endpoint (private DNS enabled)
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = module.db.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.db.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.common_tags, { Name = "${local.project_name}-${local.environment}-vpce-secretsmanager" })
}

# Systems Manager Parameter Store Interface VPC Endpoint (private DNS enabled)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = module.db.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.db.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = merge(local.common_tags, { Name = "${local.project_name}-${local.environment}-vpce-ssm" })
}
