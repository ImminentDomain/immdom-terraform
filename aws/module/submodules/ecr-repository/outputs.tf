output "repository_url" {
  value = element(concat(aws_ecr_repository.app.*.repository_url, list("")), 0)
}

output "arn" {
  value = element(concat(aws_ecr_repository.app.*.arn, list("")), 0)
}
