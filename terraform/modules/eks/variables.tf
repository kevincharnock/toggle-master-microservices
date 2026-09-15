variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "kubernetes_version" {
  description = "Versao do Kubernetes. Confira as suportadas: aws eks describe-addon-versions"
  type        = string
  default     = "1.33"
}

variable "vpc_id" {
  description = "ID da VPC (vem do modulo network)"
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde os nos vao rodar"
  type        = list(string)
}

variable "instance_types" {
  description = "Tipos de instancia dos nos. t3.medium = 2 vCPU / 4GB, ~US$30/mes cada."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "ON_DEMAND (estavel) ou SPOT (ate 70% mais barato, mas pode ser encerrado)"
  type        = string
  default     = "ON_DEMAND"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "tags" {
  description = "Tags comuns"
  type        = map(string)
  default     = {}
}
