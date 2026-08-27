# ============================================================================
# BOOTSTRAP - Rode isto UMA VEZ, antes de tudo.
#
# Problema do ovo e da galinha: o Terraform de `environments/dev` guarda seu
# state num bucket S3. Mas quem cria esse bucket? Este projeto aqui, que usa
# state LOCAL (nao tem bloco `backend`).
#
# Uso:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#   -> anote o nome do bucket no output e coloque em ../environments/dev/backend.tf
# ============================================================================

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nome do projeto, usado como prefixo dos recursos"
  type        = string
  default     = "toggle-master"
}

# Nome de bucket S3 e GLOBAL (unico no mundo inteiro). O sufixo aleatorio
# evita colisao com o bucket de outra pessoa.
resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.project}-tfstate-${random_id.suffix.hex}"

  # Protecao contra `terraform destroy` acidental. Se voce REALMENTE quiser
  # apagar o bucket, remova este bloco antes.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Purpose   = "terraform-remote-state"
  }
}

# Versionamento: cada `apply` grava uma nova versao do state. Se voce corromper
# o state, da para voltar para a versao anterior. Nao e opcional na pratica.
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# O state contem dados sensiveis (senhas de RDS, por exemplo) em texto claro.
# Criptografia em repouso e obrigatoria.
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloqueia qualquer possibilidade de o bucket virar publico.
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket_name" {
  description = "Copie este valor para o bloco backend em environments/dev/backend.tf"
  value       = aws_s3_bucket.tfstate.id
}
