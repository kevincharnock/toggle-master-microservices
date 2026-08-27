output "postgres_endpoints" {
  description = "Endpoint de cada banco, por servico"
  value       = { for k, v in aws_db_instance.postgres : k => v.address }
}

output "postgres_secret_arns" {
  description = "ARNs dos secrets. O External Secrets Operator vai usar isto."
  value       = { for k, v in aws_secretsmanager_secret.postgres : k => v.arn }
}

output "postgres_security_group_id" {
  value = aws_security_group.postgres.id
}

output "redis_endpoint" {
  description = "Endpoint primario do Redis"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.analytics.name
}

output "dynamodb_table_arn" {
  description = "Necessario para a policy IAM do analytics-service (IRSA)"
  value       = aws_dynamodb_table.analytics.arn
}
