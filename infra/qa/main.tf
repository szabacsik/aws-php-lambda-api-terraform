module "api" {
  source          = "../modules/api"
  project_name    = "aws-php-lambda-api-terraform"
  app_env         = "qa"
  aws_region      = var.aws_region
  lambda_zip_path = var.lambda_zip_path

  # Bref layer ARN (see: https://bref.sh/docs/runtimes/runtimes-details)
  bref_layer_arn = var.bref_layer_arn

  # Per-environment architecture ("x86_64" or "arm64")
  architecture = var.architecture

  # Resource sizing (minimal for QA)
  memory_size = 128

  # Attach Lambda to the DB VPC (no NAT / no internet required)
  enable_vpc      = true
  vpc_id          = module.db.vpc_id
  vpc_subnet_ids  = module.db.private_subnet_ids

  # Provide DB connection details and secret access for PDO
  db_host                   = module.db.writer_endpoint
  db_name                   = module.db.database_name
  enable_db_secret_access   = true
  db_secret_arn             = module.db.secret_arn

  tags = {
    Project = "aws-php-lambda-api-terraform"
    Env     = "qa"
  }
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
  project_name = "aws-php-lambda-api-terraform"
  app_env      = "qa"
  aws_region   = var.aws_region

  engine_version = var.aurora_engine_version

  # Capacity: min 0.5 to 2 ACUs in QA (Aurora Serverless v2)
  min_acu = 0.5
  max_acu = 2

  database_name             = "aurora_postgresql_db"
  create_final_snapshot     = false
  tags                      = { Project = "aws-php-lambda-api-terraform", Env = "qa" }
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


output "db_secret_arn" {
  value       = module.db.secret_arn
  description = "RDS-managed master secret ARN"
}

# VPC Interface Endpoint SG for Secrets Manager
resource "aws_security_group" "vpc_endpoints" {
  name   = "aws-php-lambda-api-terraform-qa-vpce-sg"
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

  tags = {
    Project = "aws-php-lambda-api-terraform"
    Env     = "qa"
  }
}

# Secrets Manager Interface VPC Endpoint (private DNS enabled)
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = module.db.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.db.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "aws-php-lambda-api-terraform-qa-vpce-secretsmanager" }
}
