resource "aws_ecr_repository" "app" {
  count = var.create ? 1 : 0
  name  = var.name
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}
