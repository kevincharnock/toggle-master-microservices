variable "name" {
  type = string
}

variable "github_org" {
  description = "Seu usuario ou organizacao no GitHub"
  type        = string
}

variable "github_repo" {
  description = "Nome do repositorio"
  type        = string
}

variable "create_oidc_provider" {
  description = "false se ja existe um provider OIDC do GitHub na conta"
  type        = bool
  default     = true
}

variable "existing_oidc_provider_arn" {
  description = "Usado quando create_oidc_provider = false"
  type        = string
  default     = ""
}

variable "ecr_repository_arns" {
  description = "ARNs dos repositorios ECR onde a role pode dar push"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
