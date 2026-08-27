variable "name_prefix" {
  description = "Prefixo dos repositorios. Vira toggle-master/auth-service, etc."
  type        = string
  default     = "toggle-master"
}

variable "repository_names" {
  description = "Um repositorio ECR por item. O desafio pede 5."
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

variable "image_tag_mutability" {
  description = "IMMUTABLE impede sobrescrever tags. Recomendado para GitOps."
  type        = string
  default     = "IMMUTABLE"
}

variable "keep_last_images" {
  description = "Quantas imagens manter por repositorio"
  type        = number
  default     = 10
}

variable "force_delete" {
  description = "true permite destroy mesmo com imagens dentro"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
