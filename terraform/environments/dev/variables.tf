# ---- Identificacao ----

variable "project" {
  type    = string
  default = "toggle-master"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# ---- GitHub (OBRIGATORIO preencher no terraform.tfvars) ----

variable "github_org" {
  description = "Seu usuario/org no GitHub, ex: kevincharnock"
  type        = string
}

variable "github_repo" {
  description = "Nome do repositorio, ex: toggle-master-microservices"
  type        = string
}

# ---- Rede ----

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Minimo 2 - o EKS exige subnets em pelo menos 2 AZs"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.32.0/20", "10.0.48.0/20"]
}

# ---- EKS ----

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

# ---- Aplicacao ----

variable "services" {
  description = "Os 5 microsservicos. Vira 1 repositorio ECR para cada."
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

variable "postgres_databases" {
  description = "3 RDS, conforme o desafio"
  type        = list(string)
  default     = ["auth", "flag", "targeting"]
}

variable "postgres_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "redis_node_type" {
  type    = string
  default = "cache.t4g.micro"
}
