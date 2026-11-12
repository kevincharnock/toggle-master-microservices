variable "name" {
  description = "Prefixo dos recursos, ex: toggle-master-dev"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do provider OIDC do cluster EKS (output do modulo eks)"
  type        = string
}

variable "namespace" {
  description = "Namespace onde ficam as ServiceAccounts dos servicos"
  type        = string
  default     = "default"
}

variable "sqs_queue_arn" {
  description = "ARN da fila de eventos"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN da tabela de analytics"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
