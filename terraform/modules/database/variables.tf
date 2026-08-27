variable "name" {
  description = "Prefixo de nome dos recursos"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC (output do modulo network)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde os bancos vao ficar"
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "SG dos nos do EKS - so ele tera acesso aos bancos"
  type        = string
}

# ---- PostgreSQL ----

variable "postgres_databases" {
  description = "Um RDS por item da lista. O desafio pede 3."
  type        = list(string)
  default     = ["auth", "flag", "targeting"]
}

variable "postgres_version" {
  description = "Versao do PostgreSQL"
  type        = string
  default     = "16.4"
}

variable "postgres_instance_class" {
  description = "db.t3.micro = elegivel no free tier, ~US$13/mes fora dele"
  type        = string
  default     = "db.t3.micro"
}

variable "postgres_username" {
  description = "Usuario master. Nao use 'admin' nem 'postgres' (reservados)."
  type        = string
  default     = "toggleadmin"
}

variable "backup_retention_period" {
  description = "Dias de retencao de backup. 0 desliga (mais barato, ok em dev)."
  type        = number
  default     = 1
}

# ---- Redis ----

variable "redis_version" {
  type    = string
  default = "7.1"
}

variable "redis_node_type" {
  description = "cache.t4g.micro = ~US$12/mes, o menor disponivel"
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_num_nodes" {
  description = "1 = sem replica (dev). 2+ habilita failover automatico."
  type        = number
  default     = 1
}

# ---- DynamoDB ----

variable "dynamodb_table_name" {
  description = "Nome exato pedido pelo desafio"
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "dynamodb_pitr_enabled" {
  description = "Point-in-time recovery. Custa a mais; false em dev."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
