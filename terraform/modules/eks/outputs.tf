output "cluster_name" {
  description = "Nome do cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do Kubernetes"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "CA do cluster, usado pelo kubeconfig"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "node_security_group_id" {
  description = "SG dos nos. GUARDE ISTO: e o que voce vai liberar nos security groups do RDS e do Redis."
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN do provider OIDC do cluster, necessario para IRSA (pods assumindo roles IAM)"
  value       = module.eks.oidc_provider_arn
}
