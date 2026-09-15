# ============================================================================
# Rode `terraform output` depois do apply para pegar estes valores.
# Os marcados com (CI) voce vai precisar colar nos GitHub Secrets.
# ============================================================================

output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Rode este comando para conectar o kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "ecr_repository_urls" {
  description = "(CI) URLs dos repositorios ECR"
  value       = module.ecr.repository_urls
}

output "github_actions_role_arn" {
  description = "(CI) Cole em GitHub Secrets como AWS_ROLE_ARN"
  value       = module.github_oidc.role_arn
}

output "postgres_endpoints" {
  value = module.database.postgres_endpoints
}

output "redis_endpoint" {
  value = module.database.redis_endpoint
}

output "sqs_queue_url" {
  value = module.messaging.queue_url
}

output "dynamodb_table_name" {
  value = module.database.dynamodb_table_name
}
