output "vpc_id" {
  description = "ID da VPC criada"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR da VPC (util para regras de security group)"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas - e aqui que o EKS e os bancos vao"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ips" {
  description = "IPs publicos de saida. Util se algum servico externo exigir allowlist de IP."
  value       = aws_eip.nat[*].public_ip
}
