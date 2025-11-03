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



# Attach Lambda to a VPC to connect to the DB over private subnets (no NAT required)
variable "enable_vpc" {
  type        = bool
  default     = false
  description = "When true, attach the Lambda function to the provided VPC subnets using a dedicated security group."
}

variable "vpc_id" {
  type        = string
  default     = ""
  description = "VPC ID where the Lambda security group will be created (required when enable_vpc=true)"
}

variable "vpc_subnet_ids" {
  type        = list(string)
  default     = []
  description = "List of private subnet IDs for the Lambda ENIs (required when enable_vpc=true)"
}

# DB connection details exposed to the Lambda for PDO connections
variable "db_host" {
  type        = string
  default     = ""
  description = "Database hostname (e.g., Aurora cluster writer endpoint)"
}

variable "db_port" {
  type        = number
  default     = 5432
  description = "Database port (default 5432 for PostgreSQL)"
}

variable "db_name" {
  type        = string
  default     = ""
  description = "Logical database name for PDO connections"
}

# Allow Lambda to read a secret (username/password) from Secrets Manager
variable "enable_db_secret_access" {
  type        = bool
  default     = false
  description = "When true, attach IAM permissions to read the provided db_secret_arn and expose it as an env var."
}

variable "db_secret_arn" {
  type        = string
  default     = ""
  description = "Secrets Manager secret ARN containing DB credentials (e.g., the RDS-managed master secret)"
}

# Additional environment variables to inject into the Lambda function
variable "env_vars" {
  type        = map(string)
  default     = {}
  description = "Additional environment variables passed to the Lambda function (string values only)."
}

variable "ssm_parameter_arns" {
  type        = list(string)
  default     = []
  description = "List of SSM Parameter Store ARNs the Lambda function may read."
}
