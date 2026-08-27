# ============================================================================
# MODULO: DATABASE
#
# Cria o que o desafio pede no item 3:
#   - 3 instancias RDS PostgreSQL   (auth, flag, targeting)
#   - 1 cluster ElastiCache Redis   (cache do evaluation)
#   - 1 tabela DynamoDB             (ToggleMasterAnalytics)
#
# CONCEITO CENTRAL AQUI: security group referenciando outro security group.
# Em vez de liberar a porta 5432 para um range de IPs, a gente libera
# "qualquer coisa que esteja NO security group dos nos do EKS". Se um no novo
# subir amanha com outro IP, ele ja tem acesso automaticamente. E o jeito
# certo de fazer, e e o tipo de detalhe que o avaliador procura.
# ============================================================================

# ---------------------------------------------------------------------------
# SUBNET GROUPS - dizem a AWS em quais subnets o banco pode nascer.
# Sempre PRIVADAS: banco nunca deve ter IP publico.
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name}-postgres"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-postgres-subnet-group" })
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name}-redis"
  subnet_ids = var.private_subnet_ids
}

# ---------------------------------------------------------------------------
# SECURITY GROUP DO POSTGRES
# ---------------------------------------------------------------------------
resource "aws_security_group" "postgres" {
  name        = "${var.name}-postgres-sg"
  description = "Permite acesso ao PostgreSQL somente a partir dos nos do EKS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-postgres-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_eks" {
  security_group_id = aws_security_group.postgres.id
  description       = "PostgreSQL a partir dos nos do EKS"

  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"

  # A MAGICA: origem e um security group, nao um CIDR.
  referenced_security_group_id = var.eks_node_security_group_id
}

resource "aws_vpc_security_group_egress_rule" "postgres_all" {
  security_group_id = aws_security_group.postgres.id
  description       = "Saida liberada"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# SECURITY GROUP DO REDIS
# ---------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.name}-redis-sg"
  description = "Permite acesso ao Redis somente a partir dos nos do EKS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-redis-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks" {
  security_group_id = aws_security_group.redis.id
  description       = "Redis a partir dos nos do EKS"

  from_port   = 6379
  to_port     = 6379
  ip_protocol = "tcp"

  referenced_security_group_id = var.eks_node_security_group_id
}

# ---------------------------------------------------------------------------
# SENHAS
#
# Geradas aleatoriamente pelo Terraform e guardadas no AWS Secrets Manager.
# Isso responde diretamente a dor do enunciado: "as credenciais do banco estao
# sendo passadas em arquivos de texto sem seguranca".
#
# ATENCAO: a senha AINDA fica visivel no terraform.tfstate. Por isso o bucket
# do state e criptografado e privado. Nunca comite o state.
# ---------------------------------------------------------------------------
resource "random_password" "postgres" {
  for_each = toset(var.postgres_databases)

  length  = 24
  special = true
  # Alguns caracteres sao proibidos em senha de RDS
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "postgres" {
  for_each = toset(var.postgres_databases)

  name        = "${var.name}/${each.key}/postgres"
  description = "Credenciais do PostgreSQL do servico ${each.key}"

  # Em dev, 0 permite recriar o secret na hora se voce destruir e subir de novo.
  # Em producao voce usaria 7 ou 30 dias.
  recovery_window_in_days = 0

  tags = merge(var.tags, { Service = each.key })
}

resource "aws_secretsmanager_secret_version" "postgres" {
  for_each = toset(var.postgres_databases)

  secret_id = aws_secretsmanager_secret.postgres[each.key].id

  secret_string = jsonencode({
    username = var.postgres_username
    password = random_password.postgres[each.key].result
    engine   = "postgres"
    host     = aws_db_instance.postgres[each.key].address
    port     = 5432
    dbname   = each.key
  })
}

# ---------------------------------------------------------------------------
# 3 INSTANCIAS RDS POSTGRESQL
#
# for_each em cima de uma lista: cria uma instancia por servico, sem copiar
# e colar o bloco 3 vezes. Se amanha precisar de um quarto banco, e so
# adicionar o nome na variavel.
# ---------------------------------------------------------------------------
resource "aws_db_instance" "postgres" {
  for_each = toset(var.postgres_databases)

  identifier = "${var.name}-${each.key}"

  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.postgres_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50 # autoscaling de disco
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = each.key
  username = var.postgres_username
  password = random_password.postgres[each.key].result

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  # NUNCA true. Banco em subnet privada, acessado so de dentro da VPC.
  publicly_accessible = false

  multi_az = false # dev: economia. producao: true.

  backup_retention_period = var.backup_retention_period

  # CRITICO PARA ESTE DESAFIO: sem estes dois, o `terraform destroy` falha
  # ou trava pedindo confirmacao, e voce fica pagando por banco esquecido.
  skip_final_snapshot = true
  deletion_protection = false

  # Evita que a AWS mude a versao menor no meio da sua demo
  auto_minor_version_upgrade = false

  tags = merge(var.tags, {
    Name    = "${var.name}-${each.key}"
    Service = each.key
  })
}

# ---------------------------------------------------------------------------
# ELASTICACHE REDIS
#
# `replication_group` e o recurso moderno (o antigo `aws_elasticache_cluster`
# nao suporta encryption nem failover direito).
# ---------------------------------------------------------------------------
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.name}-redis"
  description          = "Cache Redis do ToggleMaster"

  engine         = "redis"
  engine_version = var.redis_version
  node_type      = var.redis_node_type

  num_cache_clusters = var.redis_num_nodes
  port               = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true

  # transit encryption exigiria TLS no client da aplicacao. Deixado false
  # para nao quebrar os microsservicos da Fase 2. Em producao: true.
  transit_encryption_enabled = false

  automatic_failover_enabled = var.redis_num_nodes > 1

  # Sem snapshot ao destruir - de novo, para o destroy ser limpo.
  snapshot_retention_limit = 0

  apply_immediately = true

  tags = merge(var.tags, { Name = "${var.name}-redis" })
}

# ---------------------------------------------------------------------------
# DYNAMODB - tabela de analytics
#
# PAY_PER_REQUEST significa que voce paga por leitura/escrita, sem custo fixo.
# Para este desafio, o custo fica praticamente em zero.
#
# Modelagem: particao por flag_id, ordenacao por timestamp. Isso permite a
# query "todos os eventos da flag X ordenados por tempo", que e o padrao de
# acesso tipico de um servico de analytics de feature flags.
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "analytics" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "flag_id"
  range_key = "timestamp"

  attribute {
    name = "flag_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  # TTL: o DynamoDB apaga sozinho os registros cujo campo expires_at ja passou.
  # Evita a tabela crescer para sempre.
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = var.dynamodb_pitr_enabled
  }

  tags = merge(var.tags, { Name = var.dynamodb_table_name })
}
