output "queue_url" {
  description = "URL da fila - e isto que a aplicacao usa no SDK"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "ARN da fila - necessario para policies IAM"
  value       = aws_sqs_queue.main.arn
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}
