module "api" {
  source          = "../modules/api"
  project_name    = "aws-php-lambda-api-terraform"
  app_env         = "development"
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

  tags = {
    Project = "aws-php-lambda-api-terraform"
    Env     = "development"
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
