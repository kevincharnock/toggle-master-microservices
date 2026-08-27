# ============================================================================
# MODULO: GITHUB OIDC
#
# POR QUE ISTO EXISTE:
# O jeito antigo de dar acesso AWS ao GitHub Actions era criar um usuario IAM,
# gerar uma access key e colar em GitHub Secrets. Problema: essa chave nunca
# expira. Se vazar, o atacante tem acesso permanente.
#
# Com OIDC, o GitHub emite um token JWT de curta duracao a cada execucao do
# workflow, e a AWS confia nesse token. ZERO credenciais estaticas no repo.
#
# Voce so consegue fazer isto porque esta em conta pessoal (no AWS Academy
# seria proibido criar roles). E um diferencial forte para o video e para o
# portfolio - vale mencionar no relatorio como decisao tecnica.
# ============================================================================

data "aws_caller_identity" "current" {}

# O provider OIDC: registra o GitHub como emissor de identidade confiavel.
# Cria-se UM por conta AWS.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = var.tags
}

locals {
  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn
}

# ---------------------------------------------------------------------------
# TRUST POLICY - quem pode assumir esta role
#
# A condicao `sub` e a parte critica de seguranca. Ela amarra a role a UM
# repositorio especifico. Sem ela, QUALQUER repositorio do GitHub no mundo
# poderia assumir sua role. Este e o erro de configuracao mais comum e mais
# perigoso de OIDC.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # ex: repo:kevincharnock/toggle-master-microservices:*
      values = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.name}-github-actions"
  description        = "Role assumida pelo GitHub Actions via OIDC para push no ECR"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

# ---------------------------------------------------------------------------
# PERMISSOES - principio do menor privilegio
#
# A role SO pode fazer push no ECR. Ela nao pode mexer no EKS, no RDS, em
# nada. Isso e proposital e coerente com GitOps: o CI nao faz deploy, entao
# nao precisa de acesso ao cluster.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecr_push" {
  # GetAuthorizationToken nao aceita restricao de recurso - e sempre "*"
  statement {
    sid       = "ECRAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
    ]
    resources = var.ecr_repository_arns
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.ecr_push.json
}
