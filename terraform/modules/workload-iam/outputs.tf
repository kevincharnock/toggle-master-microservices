output "evaluation_role_arn" {
  description = "Anotar na ServiceAccount evaluation-service (eks.amazonaws.com/role-arn)"
  value       = aws_iam_role.this["evaluation"].arn
}

output "analytics_role_arn" {
  description = "Anotar na ServiceAccount analytics-service (eks.amazonaws.com/role-arn)"
  value       = aws_iam_role.this["analytics"].arn
}
