output "role_arn" {
  description = "COPIE ISTO para o workflow do GitHub Actions (role-to-assume)"
  value       = aws_iam_role.github_actions.arn
}
