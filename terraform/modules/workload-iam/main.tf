# ============================================================================
# MODULO: WORKLOAD IAM (IRSA)
#
# IRSA = IAM Roles for Service Accounts. O pod recebe um token OIDC do cluster
# e o SDK da AWS troca esse token por credenciais temporarias da role
# (sts:AssumeRoleWithWebIdentity). Nada de access key estatica no cluster.
#
# A trust policy so aceita o token da ServiceAccount exata
# (system:serviceaccount:<namespace>:<nome>), entao outro pod nao assume a role.
#
# - evaluation-service: publica eventos na fila SQS
# - analytics-service: consome a fila e grava no DynamoDB
# ============================================================================

locals {
  # O ARN e arn:aws:iam::<conta>:oidc-provider/oidc.eks.<regiao>.amazonaws.com/id/<id>
  # A trust policy usa so a parte depois de "oidc-provider/".
  oidc_issuer = element(split("oidc-provider/", var.oidc_provider_arn), 1)

  service_accounts = {
    evaluation = "evaluation-service"
    analytics  = "analytics-service"
  }
}

data "aws_iam_policy_document" "trust" {
  for_each = local.service_accounts

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${each.value}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.service_accounts

  name               = "${var.name}-${each.key}-irsa"
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json
  tags               = var.tags
}

# ---- evaluation: so publica na fila ----
data "aws_iam_policy_document" "evaluation" {
  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [var.sqs_queue_arn]
  }
}

resource "aws_iam_role_policy" "evaluation" {
  name   = "sqs-send"
  role   = aws_iam_role.this["evaluation"].id
  policy = data.aws_iam_policy_document.evaluation.json
}

# ---- analytics: consome a fila e grava no DynamoDB ----
data "aws_iam_policy_document" "analytics" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]
    resources = [var.sqs_queue_arn]
  }

  statement {
    actions = [
      "dynamodb:PutItem",
      "dynamodb:DescribeTable",
    ]
    resources = [var.dynamodb_table_arn]
  }
}

resource "aws_iam_role_policy" "analytics" {
  name   = "sqs-consume-dynamodb-write"
  role   = aws_iam_role.this["analytics"].id
  policy = data.aws_iam_policy_document.analytics.json
}
