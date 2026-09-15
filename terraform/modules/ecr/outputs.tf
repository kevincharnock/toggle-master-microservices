output "repository_urls" {
  description = "URL de cada repositorio, por servico. Use no CI para taggear a imagem."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  value = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "registry_id" {
  description = "ID da conta AWS que hospeda o registry"
  value       = values(aws_ecr_repository.this)[0].registry_id
}
