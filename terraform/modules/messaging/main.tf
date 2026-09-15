# ============================================================================
# MODULO: MESSAGING
#
# 1 fila SQS (requisito 4 do desafio) + a Dead Letter Queue dela.
#
# CONCEITO: DLQ. Se uma mensagem falhar de ser processada N vezes seguidas
# (maxReceiveCount), a SQS move ela para a DLQ em vez de ficar tentando para
# sempre. Sem DLQ, uma mensagem "envenenada" trava sua fila indefinidamente.
# Nao e exigido pelo desafio, mas e boa pratica e vale ponto.
# ============================================================================

resource "aws_sqs_queue" "dlq" {
  name = "${var.queue_name}-dlq"

  message_retention_seconds = 1209600 # 14 dias, o maximo

  sqs_managed_sse_enabled = true

  tags = merge(var.tags, { Name = "${var.queue_name}-dlq" })
}

resource "aws_sqs_queue" "main" {
  name = var.queue_name

  # Quanto tempo a mensagem some da fila enquanto um consumidor a processa.
  # Regra pratica: ~6x o tempo medio de processamento.
  visibility_timeout_seconds = var.visibility_timeout_seconds

  message_retention_seconds = var.message_retention_seconds

  # Long polling: o consumidor espera ate 20s por mensagem em vez de
  # perguntar repetidamente. Reduz custo e latencia.
  receive_wait_time_seconds = 20

  sqs_managed_sse_enabled = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, { Name = var.queue_name })
}
