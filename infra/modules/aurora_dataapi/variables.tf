variable "project_name" { type = string }
variable "app_env"      { type = string }
variable "aws_region"   { type = string }

# Database logical name (schema/db name)
variable "database_name" {
  type        = string
  default     = "aurora_postgresql_db"
  description = "Logical database name to create with the cluster"
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
