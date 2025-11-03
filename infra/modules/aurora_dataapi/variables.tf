# IMPORTANT: For all name-related variables in this project, prefer simple, safe characters.
# Recommended for RDS identifiers: lowercase letters a–z, digits 0–9, and hyphens (-).
# Keep the overall rendered identifier <= 63 chars (RDS limit).

variable "project_name" {
  type        = string
  description = "Project short name. Use lowercase letters, digits, and hyphens only."
}

variable "app_env" {
  type        = string
  description = "Environment name (e.g., development, staging, production). Use lowercase letters, digits, and hyphens only."
}

variable "aws_region"   { type = string }

# Database logical name (schema/db name)
variable "database_name" {
  type        = string
  default     = "aurora_postgresql_db"
  description = "Logical database name to create with the cluster"
}

variable "master_username" {
  type        = string
  default     = "postgres"
  description = "Master username for the Aurora cluster."
}

variable "master_password" {
  type        = string
  sensitive   = true
  description = "Master password for the Aurora cluster."
}

# Aurora PostgreSQL engine version. Prefer PG 17.x (latest in region).
# Tip: resolve exact version at deploy time; see README notes.
variable "engine_version" {
  type        = string
  default     = "17.4"
  description = "Aurora PostgreSQL engine version (e.g. 17.4)."
}

# Serverless v2 scaling per environment
variable "min_acu" {
  type        = number
  default     = 0.5
  description = "Minimum ACUs for Aurora Serverless v2 (cannot be 0)."
}

variable "max_acu" {
  type        = number
  default     = 4
  description = "Maximum ACUs for this environment."
}




variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags"
}

variable "create_final_snapshot" {
  type        = bool
  default     = false
  description = "If true, create a final snapshot when destroying the cluster."
}

variable "final_snapshot_identifier" {
  type        = string
  default     = null
  description = "Final snapshot identifier (required if create_final_snapshot = true). Lowercase letters, numbers, hyphens only."
}

# Human-friendly naming prefixes (overridable if ever needed)
variable "cluster_name_prefix" {
  description = "Prefix for Aurora cluster identifiers"
  type        = string
  default     = "aurora-pg-cluster"
}

variable "instance_name_prefix" {
  description = "Prefix for Aurora instance identifiers"
  type        = string
  default     = "aurora-pg-instance"
}

# Optional hard overrides (useful to avoid replacement in prod while migrating names)
variable "db_cluster_identifier_override" {
  description = "Explicit cluster identifier; if set, overrides the generated one"
  type        = string
  default     = null
}

variable "db_instance_identifier_override" {
  description = "Explicit instance identifier for the first instance; if set, overrides the generated one"
  type        = string
  default     = null
}
