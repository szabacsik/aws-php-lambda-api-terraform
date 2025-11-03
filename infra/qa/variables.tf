# Common variables across environments
variable "aws_region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS region (all environments use the same region)"
}

variable "lambda_zip_path" {
  type        = string
  description = "Absolute path to app ZIP (passed from Makefile)"
}

# Per-environment tunables
# Architecture options: "x86_64" or "arm64". Ensure the Bref layer matches the selected architecture.
variable "architecture" {
  type        = string
  default     = "x86_64"
  description = "Lambda architecture (x86_64 or arm64)"
  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be either x86_64 or arm64."
  }
}

# Bref layer ARN must correspond to the chosen architecture.
# Examples for eu-central-1 (check latest: https://bref.sh/docs/runtimes/runtimes-details):
#   x86_64: arn:aws:lambda:eu-central-1:534081306603:layer:php-84-fpm:32
#   arm64 : arn:aws:lambda:eu-central-1:534081306603:layer:arm-php-84-fpm:32
variable "bref_layer_arn" {
  type        = string
  default     = "arn:aws:lambda:eu-central-1:534081306603:layer:php-84-fpm:32"
  description = "Full ARN of the Bref PHP FPM layer for this region/runtime"
}


variable "aurora_engine_version" {
  type        = string
  default     = "17.4"
  description = "Aurora PostgreSQL engine version to use (e.g. 17.4 or later supported in region)"
}

variable "db_username" {
  type        = string
  description = "Database master username passed to the Lambda environment."
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Database master password passed to the Lambda environment."
}

