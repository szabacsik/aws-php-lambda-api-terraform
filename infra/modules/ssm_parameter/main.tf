terraform {
  required_version = ">= 1.13.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.13.0"
    }
  }
}

locals {
  default_tags = {
    Project     = var.project_name
    Environment = var.app_env
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }
  parameter_tags = merge(local.default_tags, var.tags)
}

resource "aws_ssm_parameter" "this" {
  name        = var.name
  description = var.description
  type        = "String"
  tier        = "Standard"
  data_type   = "text"
  value       = var.value
  overwrite   = var.overwrite
  tags        = local.parameter_tags
}
