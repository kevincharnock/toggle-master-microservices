# ============================================================================
# BACKEND REMOTO - requisito explicito do desafio:
# "O terraform.tfstate nao pode ficar local."
#
# ORDEM DE EXECUCAO:
#   1. rode terraform/bootstrap primeiro (cria o bucket)
#   2. troque BUCKET_AQUI abaixo pelo output do bootstrap
#   3. terraform init  (aqui)
#
# `use_lockfile = true` e o lock NATIVO do S3 (Terraform 1.11+). Ele substitui
# a antiga tabela DynamoDB de lock. O lock impede que duas pessoas (ou voce e o
# GitHub Actions) rodem apply ao mesmo tempo e corrompam o state.
# ============================================================================

terraform {
  backend "s3" {
    bucket       = "BUCKET_AQUI"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
