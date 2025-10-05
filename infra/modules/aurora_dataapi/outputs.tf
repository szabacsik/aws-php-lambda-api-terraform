
output "database_name" {
  value       = aws_rds_cluster.pg.database_name
  description = "Logical database name"
}

# When manage_master_user_password = true, AWS creates a managed secret.
# Access pattern in recent providers: master_user_secret is a list with one item.
output "secret_arn" {
  description = "Secrets Manager ARN for the master user (managed by RDS)"
  value       = try(aws_rds_cluster.pg.master_user_secret[0].secret_arn, null)
}

# Network outputs for attaching Lambda into the VPC
output "vpc_id" {
  value       = aws_vpc.db.id
  description = "VPC ID hosting the database"
}

output "private_subnet_ids" {
  value       = [aws_subnet.db_a.id, aws_subnet.db_b.id]
  description = "Private subnet IDs for Lambda attachment"
}

output "db_security_group_id" {
  value       = aws_security_group.db.id
  description = "Security group ID attached to the Aurora cluster"
}

# Endpoints for direct connections (PDO)
output "writer_endpoint" {
  value       = aws_rds_cluster.pg.endpoint
  description = "Cluster writer endpoint hostname"
}

output "reader_endpoint" {
  value       = aws_rds_cluster.pg.reader_endpoint
  description = "Cluster reader endpoint hostname"
}

output "cluster_identifier" {
  description = "Aurora cluster identifier"
  value       = aws_rds_cluster.pg.cluster_identifier
}

output "instance_identifier" {
  description = "Aurora primary instance identifier"
  value       = aws_rds_cluster_instance.writer.id
}
