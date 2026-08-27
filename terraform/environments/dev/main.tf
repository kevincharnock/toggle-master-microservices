# ============================================================================
# AMBIENTE: DEV
#
# Este arquivo e a MONTAGEM. Ele nao contem logica - so conecta os modulos,
# passando o output de um como input do outro. Repare como o Terraform
# descobre sozinho a ordem de criacao a partir dessas dependencias:
# network -> eks -> database (porque database precisa do SG dos nos).
# ============================================================================

locals {
  name         = "${var.project}-${var.environment}"
  cluster_name = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# ---------------------------------------------------------------------------
# 1. REDE - VPC, subnets publicas/privadas, IGW, NAT, route tables
# ---------------------------------------------------------------------------
module "network" {
  source = "../../modules/network"

  name         = local.name
  cluster_name = local.cluster_name

  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs

  # CUSTO: mantenha true. false triplica a conta do NAT (~US$99/mes).
  single_nat_gateway = true

  tags = local.tags
}

# ---------------------------------------------------------------------------
# 2. CLUSTER EKS - control plane + node groups nas subnets privadas
# ---------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  instance_types = var.node_instance_types
  desired_size   = var.node_desired_size
  min_size       = 1
  max_size       = 4

  tags = local.tags
}

# ---------------------------------------------------------------------------
# 3. BANCOS - 3x RDS PostgreSQL + Redis + DynamoDB
#
# Repare: `eks_node_security_group_id` vem do modulo eks. E isso que faz o
# banco aceitar conexao SO dos nos do cluster.
# ---------------------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  name               = local.name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  eks_node_security_group_id = module.eks.node_security_group_id

  postgres_databases      = var.postgres_databases
  postgres_instance_class = var.postgres_instance_class
  redis_node_type         = var.redis_node_type

  tags = local.tags
}

# ---------------------------------------------------------------------------
# 4. MENSAGERIA - fila SQS + DLQ
# ---------------------------------------------------------------------------
module "messaging" {
  source = "../../modules/messaging"

  queue_name = "${local.name}-events"
  tags       = local.tags
}

# ---------------------------------------------------------------------------
# 5. ECR - 5 repositorios de imagem, um por microsservico
# ---------------------------------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  name_prefix      = var.project
  repository_names = var.services

  tags = local.tags
}

# ---------------------------------------------------------------------------
# 6. OIDC - permite o GitHub Actions dar push no ECR sem access key
# ---------------------------------------------------------------------------
module "github_oidc" {
  source = "../../modules/github-oidc"

  name        = local.name
  github_org  = var.github_org
  github_repo = var.github_repo

  ecr_repository_arns = values(module.ecr.repository_arns)

  tags = local.tags
}
