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
  name_prefix   = "${var.project_name}-${var.app_env}"
  layer_runtime = "provided.al2"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# IAM Role for Lambda
data "aws_iam_policy_document" "assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.name_prefix}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

# Basic execution policy (writes to CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# CloudWatch Log group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# Optional Security Group for Lambda when attaching to a VPC
resource "aws_security_group" "lambda" {
  count       = var.enable_vpc ? 1 : 0
  name        = "${local.name_prefix}-lambda-sg"
  description = "Lambda security group (no inbound; egress open)"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Lambda function
resource "aws_lambda_function" "this" {
  function_name    = local.name_prefix
  description      = "PHP ${var.project_name} (${var.app_env})"
  filename         = abspath(var.lambda_zip_path)
  source_code_hash = filebase64sha256(abspath(var.lambda_zip_path))

  handler     = "public/index.php"
  runtime     = local.layer_runtime
  role        = aws_iam_role.lambda_exec.arn
  memory_size = var.memory_size
  timeout     = var.timeout
  # Select the Lambda architecture for the function (x86_64 or arm64)
  architectures = [var.architecture]

  # Bref base layer only (pdo_pgsql is enabled via php/conf.d/php.ini; no extra layer)
  layers = [var.bref_layer_arn]

  # Ephemeral storage for /tmp
  ephemeral_storage {
    size = var.ephemeral_storage
  }

  # Publish a new version only when provisioned concurrency is enabled
  publish = var.provisioned_concurrency > 0

  # IMPORTANT: Do not pass reserved AWS Lambda environment variables (e.g., AWS_REGION, AWS_EXECUTION_ENV,
  # AWS_LAMBDA_FUNCTION_NAME). Lambda injects these automatically and they cannot be overridden.
  # Attempting to set them will cause InvalidParameterValueException during CreateFunction/UpdateFunctionConfiguration.
  # https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html

  environment {
    variables = merge(
      {
        APP_ENV = var.app_env,
      },
      var.db_host != "" ? {
        DB_HOST = var.db_host
        DB_PORT = tostring(var.db_port)
        DB_NAME = var.db_name
      } : {},
      var.env_vars
    )
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      condition     = fileexists(abspath(var.lambda_zip_path))
      error_message = "Lambda zip not found at ${abspath(var.lambda_zip_path)}. Ensure 'make build' ran and build/app.zip exists."
    }
  }
}

# API Gateway (HTTP API) with Lambda proxy integration
resource "aws_apigatewayv2_api" "http" {
  name          = "${local.name_prefix}-httpapi"
  protocol_type = "HTTP"

  dynamic "cors_configuration" {
    for_each = var.enable_cors ? [1] : []
    content {
      allow_origins  = ["*"]
      allow_methods  = ["GET", "POST", "OPTIONS"]
      allow_headers  = ["content-type", "authorization"]
      expose_headers = []
      max_age        = 86400
    }
  }

  tags = var.tags
}

resource "aws_apigatewayv2_integration" "lambda_proxy" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
}

# Routes: $default to Lambda, plus explicit / and /health
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_apigatewayv2_route" "hello" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /hello"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      routeKey       = "$context.routeKey"
      protocol       = "$context.protocol"
      path           = "$context.path"
      status         = "$context.status"
      responseLength = "$context.responseLength"

      "integration.status"            = "$context.integration.status"
      "integration.integrationStatus" = "$context.integration.integrationStatus"
      "integration.latency"           = "$context.integration.latency"
      "integration.error"             = "$context.integration.error"

      errorMessage = "$context.error.message"
    })
  }

  tags = var.tags
}

# Permission for API Gateway to invoke Lambda
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowInvokeFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# Outputs
output "api_base_url" {
  description = "Base URL for the HTTP API"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "hello_url" {
  description = "Hello URL"
  value       = "${aws_apigatewayv2_api.http.api_endpoint}/hello"
}

output "lambda_function_name" {
  value = aws_lambda_function.this.function_name
}

output "lambda_invoke_arn" {
  value = aws_lambda_function.this.invoke_arn
}

# CloudWatch Log group for API Gateway access logs
resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# Optional provisioned concurrency (enabled when provisioned_concurrency > 0)
resource "aws_lambda_provisioned_concurrency_config" "this" {
  count                             = var.provisioned_concurrency > 0 ? 1 : 0
  function_name                     = aws_lambda_function.this.function_name
  qualifier                         = aws_lambda_function.this.version
  provisioned_concurrent_executions = var.provisioned_concurrency
}

# Output the Lambda security group ID (when VPC is enabled)
output "lambda_security_group_id" {
  value       = try(aws_security_group.lambda[0].id, null)
  description = "Security group ID attached to the Lambda function (null when not in VPC)"
}

# VPC ENI permissions for Lambda role (required when Lambda is attached to a VPC)
resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
