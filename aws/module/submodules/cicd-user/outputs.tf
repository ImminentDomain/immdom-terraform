output "name" {
  value = element(concat(aws_iam_user.cicd.*.name, list("")), 0)
}

output "arn" {
  value = element(concat(aws_iam_user.cicd.*.arn, list("")), 0)
}
