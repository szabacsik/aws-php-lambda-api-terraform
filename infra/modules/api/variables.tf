variable "project_name" {
  type        = string
  description = "Project name, used as a prefix in resource names"
}

variable "app_env" {
  type        = string
  description = "Environment name (development|staging|qa|production)"
}

variable "aws_region" {
  type        = string
  description = "AWS region (e.g., eu-central-1)"
}

variable "architecture" {
  type        = string
  description = "Lambda architecture: arm64 or x86_64"
  default     = "x86_64"
  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "architecture must be arm64 or x86_64."
  }
}

variable "lambda_zip_path" {
  type        = string
  description = "Relative or absolute path to the built application zip (e.g., build/app.zip)"
}

variable "memory_size" {
  type        = number
  default     = 128
  description = "Lambda memory in MB (default 128 MB; CPU scales with memory)"
}


# Preferred timeout variable
variable "timeout" {
  type        = number
  default     = 10
  description = "Lambda timeout in seconds (default 10)"
}

# Ephemeral storage for /tmp in MB (512–10240)
variable "ephemeral_storage" {
  type        = number
  default     = 512
  description = "Amount of ephemeral storage (/tmp) in MB (default 512)"
}

# Provisioned concurrency (0 disables it)
variable "provisioned_concurrency" {
  type        = number
  default     = 0
  description = "Number of provisioned concurrent executions (0 to disable)"
}

variable "log_retention_days" {
  type        = number
  default     = 7
  description = "CloudWatch Logs retention for Lambda"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags"
}

variable "bref_layer_arn" {
  type        = string
  description = "Full ARN of the Bref PHP FPM layer for this region/runtime (see https://bref.sh/docs/runtimes/runtimes-details)"
}

# Enable CORS configuration on the API Gateway HTTP API
variable "enable_cors" {
  type        = bool
  default     = false
  description = "Enable CORS on the HTTP API. When true, allows GET/POST/OPTIONS from any origin with content-type and authorization headers."
}
