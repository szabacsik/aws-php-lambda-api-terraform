variable "project_name" {
  type        = string
  description = "Project name used for tagging."
}

variable "app_env" {
  type        = string
  description = "Environment name (e.g., development, staging, qa, production)."
}

variable "name" {
  type        = string
  description = "SSM parameter name."
}

variable "value" {
  type        = string
  description = "SSM parameter value (numbers should be provided as strings, matching Parameter Store capabilities)."
}

variable "owner" {
  type        = string
  description = "Owner tag value used for standard tagging."
  validation {
    condition     = length(trimspace(var.owner)) > 0
    error_message = "owner cannot be empty."
  }
}

variable "description" {
  type        = string
  default     = ""
  description = "Optional description for the parameter."
}

variable "overwrite" {
  type        = bool
  default     = true
  description = "Allow Terraform to overwrite existing parameter values."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to merge with the default project/environment tags."
}
