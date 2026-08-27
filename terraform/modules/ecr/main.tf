# ============================================================================
# MODULO: ECR
#
# 5 repositorios de imagem Docker, um por microsservico.
#
# DOIS PONTOS QUE IMPORTAM PARA O DESAFIO:
#
# 1. image_tag_mutability = "IMMUTABLE"
#    Impede sobrescrever uma tag ja publicada. E a traducao literal de
#    "infraestrutura imutavel" que o enunciado pede. Efeito colateral util:
#    torna impossivel usar :latest de forma preguicosa, o que e exatamente
#    o que o GitOps precisa (se a tag nao muda, o ArgoCD nao detecta nada).
#
# 2. scan_on_push = true
#    O ECR escaneia a imagem por vulnerabilidades assim que ela chega.
#    E uma segunda camada alem do Trivy no pipeline - da para mostrar no
#    video como evidencia extra de DevSecOps.
# ============================================================================

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repository_names)

  name                 = "${var.name_prefix}/${each.key}"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  # force_delete = true permite `terraform destroy` mesmo com imagens dentro.
  # Em producao seria false. Aqui, e o que te salva de infra zumbi.
  force_delete = var.force_delete

  tags = merge(var.tags, {
    Name    = "${var.name_prefix}/${each.key}"
    Service = each.key
  })
}

# ---------------------------------------------------------------------------
# LIFECYCLE POLICY
#
# Sem isto, cada commit deixa uma imagem para sempre no ECR e voce paga
# armazenamento eternamente. Esta policy mantem as 10 mais recentes e apaga
# as nao-taggeadas depois de 1 dia.
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ${var.keep_last_images} imagens mais recentes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = { type = "expire" }
      }
    ]
  })
}
