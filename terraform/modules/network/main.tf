# ============================================================================
# MODULO: NETWORK
#
# Escrito com recursos "crus" (sem usar o modulo pronto da comunidade) DE
# PROPOSITO: rede e o conceito que voce precisa entender de verdade para
# debugar EKS depois. Se o pod nao alcanca o RDS, o problema quase sempre
# esta aqui.
#
# Topologia criada:
#
#   Internet
#      |
#   [Internet Gateway]
#      |
#   Subnets PUBLICAS (uma por AZ)  -> aqui ficam os Load Balancers e o NAT
#      |
#   [NAT Gateway]                  -> deixa a rede privada SAIR, mas ninguem ENTRAR
#      |
#   Subnets PRIVADAS (uma por AZ)  -> aqui ficam os nos do EKS e os bancos
#
# A diferenca entre subnet publica e privada NAO e um checkbox: e para onde
# aponta a rota 0.0.0.0/0 na route table. Publica -> IGW. Privada -> NAT.
# ============================================================================

locals {
  az_count = length(var.availability_zones)

  common_tags = merge(var.tags, {
    Module = "network"
  })
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Os dois sao obrigatorios para EKS funcionar: os nos precisam resolver
  # nomes DNS internos e receber hostname privado.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-vpc"
  })
}

# ---------------------------------------------------------------------------
# INTERNET GATEWAY - a porta de entrada/saida da VPC para a internet
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-igw"
  })
}

# ---------------------------------------------------------------------------
# SUBNETS PUBLICAS
#
# A tag "kubernetes.io/role/elb" = 1 nao e decorativa: e assim que o
# AWS Load Balancer Controller descobre onde criar um Load Balancer publico
# quando voce cria um Service do tipo LoadBalancer no Kubernetes.
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = local.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name                                        = "${var.name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Tier                                        = "public"
  })
}

# ---------------------------------------------------------------------------
# SUBNETS PRIVADAS
#
# "internal-elb" = load balancers internos (nao expostos na internet).
# Os nos do EKS e os bancos vivem aqui.
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  count = local.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(local.common_tags, {
    Name                                        = "${var.name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Tier                                        = "private"
  })
}

# ---------------------------------------------------------------------------
# NAT GATEWAY
#
# ATENCAO AO CUSTO: cada NAT Gateway custa ~US$33/mes + trafego, MESMO PARADO.
# O ideal em producao e um por AZ (alta disponibilidade). Para este desafio,
# `single_nat_gateway = true` economiza ~US$66/mes.
#
# O Elastic IP e necessario porque o NAT precisa de um IP publico fixo para
# fazer a traducao de endereco.
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count = var.single_nat_gateway ? 1 : local.az_count

  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-eip-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : local.az_count

  allocation_id = aws_eip.nat[count.index].id

  # O NAT fica numa subnet PUBLICA. Erro classico: colocar na privada,
  # e ai nada tem saida para a internet.
  subnet_id = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# ROUTE TABLE PUBLICA - uma so, compartilhada por todas as subnets publicas
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-rt-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# ROUTE TABLES PRIVADAS - uma por AZ (se houver NAT por AZ), senao uma so
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  count = var.single_nat_gateway ? 1 : local.az_count

  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-rt-private-${count.index}"
  })
}

resource "aws_route" "private_nat" {
  count = var.single_nat_gateway ? 1 : local.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count = local.az_count

  subnet_id = aws_subnet.private[count.index].id

  # Se so existe um NAT, todas as subnets privadas apontam para a mesma
  # route table (indice 0). Senao, cada uma aponta para a sua.
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index].id
}
