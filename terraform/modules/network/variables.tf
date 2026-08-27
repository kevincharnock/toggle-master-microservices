variable "name" {
  description = "Prefixo de nome para os recursos de rede"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster EKS (usado nas tags kubernetes.io/cluster/*)"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC. /16 da 65k IPs, folga suficiente."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs a usar. Minimo 2 - o EKS exige subnets em pelo menos 2 AZs."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets publicas (mesma ordem das AZs)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (mesma ordem das AZs)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "true = um NAT so para todas as AZs (barato). false = um por AZ (HA)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags comuns aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
