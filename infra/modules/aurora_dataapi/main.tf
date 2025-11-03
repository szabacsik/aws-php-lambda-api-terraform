terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.13.0"
    }
  }
  required_version = ">= 1.13.2"
}

locals {
  name_prefix       = "${var.project_name}-${var.app_env}"
  # If caller doesn’t pass a name, fall back to a stable, readable default:
  final_snapshot_id = coalesce(var.final_snapshot_identifier, "${var.project_name}-${var.app_env}-aurora-pg-final")

  # Ensure project_name and app_env use lowercase letters, digits, and hyphens.
  base_name           = "${var.project_name}-${var.app_env}"
  cluster_identifier  = "${var.cluster_name_prefix}-${local.base_name}"
  instance_identifier = "${var.instance_name_prefix}-${local.base_name}-01"
}

# Isolated VPC for DB only (no IGW, no NAT)
resource "aws_vpc" "db" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(var.tags, { Name = "${local.name_prefix}-db-vpc" })
}

# Two private subnets in distinct AZs
data "aws_availability_zones" "this" {
  state = "available"
}

resource "aws_subnet" "db_a" {
  vpc_id                  = aws_vpc.db.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.this.names[0]
  map_public_ip_on_launch = false
  tags = merge(var.tags, { Name = "${local.name_prefix}-db-a" })
}

resource "aws_subnet" "db_b" {
  vpc_id                  = aws_vpc.db.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.this.names[1]
  map_public_ip_on_launch = false
  tags = merge(var.tags, { Name = "${local.name_prefix}-db-b" })
}

# Route table with local routes only (no 0.0.0.0/0)
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.db.id
  tags   = merge(var.tags, { Name = "${local.name_prefix}-db-rt" })
}

resource "aws_route_table_association" "a" {
  route_table_id = aws_route_table.db.id
  subnet_id      = aws_subnet.db_a.id
}
resource "aws_route_table_association" "b" {
  route_table_id = aws_route_table.db.id
  subnet_id      = aws_subnet.db_b.id
}

# Subnet group for Aurora
resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]
  tags       = var.tags
}

# Security group for cluster (no inbound rules required for Data API only)
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "Aurora cluster SG (private)"
  vpc_id      = aws_vpc.db.id

  # Allow all egress to VPC (cluster internal behavior). No IGW/NAT attached.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Enforce TLS: cluster parameter group
resource "aws_rds_cluster_parameter_group" "pg_tls" {
  name   = "${var.project_name}-${var.app_env}-pg17"
  family = "aurora-postgresql17"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = var.tags
}

# Aurora PostgreSQL Serverless v2 cluster (Data API optional)
resource "aws_rds_cluster" "pg" {
  cluster_identifier = local.cluster_identifier
  engine         = "aurora-postgresql"
  engine_mode    = "provisioned" # Serverless v2 uses 'provisioned' with db.serverless
  engine_version = var.engine_version

  database_name   = var.database_name
  # Master credentials are provisioned via Terraform variables so Lambda can receive them as env vars.
  master_username = var.master_username
  master_password = var.master_password

  # Network
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.db.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.pg_tls.name


  # Serverless v2 scaling
  serverlessv2_scaling_configuration {
    min_capacity = var.min_acu
    max_capacity = var.max_acu
  }

  storage_encrypted = true

  # Deletion protection: keep ON in production, OFF in lower envs (set via caller).
  deletion_protection = var.app_env == "production"

  skip_final_snapshot       = var.create_final_snapshot ? false : true
  final_snapshot_identifier = var.create_final_snapshot ? local.final_snapshot_id : null

  tags = var.tags
}

# One Serverless v2 writer instance
resource "aws_rds_cluster_instance" "writer" {
  identifier         = local.instance_identifier
  cluster_identifier = aws_rds_cluster.pg.id
  engine             = aws_rds_cluster.pg.engine
  engine_version     = aws_rds_cluster.pg.engine_version
  instance_class     = "db.serverless"
  publicly_accessible = false
  tags               = var.tags
}
