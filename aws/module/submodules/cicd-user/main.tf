resource "aws_iam_user" "cicd" {
  count = var.create ? 1 : 0
  name  = "srv_${var.name}_cicd"
}

resource "aws_iam_access_key" "cicd_keys" {
  count = var.create ? 1 : 0
  user  = aws_iam_user.cicd[count.index].name
}

data "aws_iam_policy_document" "cicd_policy" {
  count = var.create ? 1 : 0

  statement {
    sid = "ecr"

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]

    resources = [
      var.ecr_repository
    ]
  }

  statement {
    sid = "ecrlogin"

    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "eks"

    actions = [
      "eks:ListCluster",
      "eks:DescribeCluster"
    ]

    resources = [
      var.eks_cluster_arn
    ]
  }
}

resource "aws_iam_user_policy" "cicd_user_policy" {
  count = var.create ? 1 : 0

  name   = "${var.name}_cicd"
  user   = aws_iam_user.cicd[count.index].name
  policy = data.aws_iam_policy_document.cicd_policy[count.index].json
}

# Add CI/CD User to Secrets Manager
resource "aws_secretsmanager_secret" "cicd_user" {
  count = var.create ? 1 : 0

  name = var.name
  tags = var.tags
}

# All the things needed for Github Actions Deploys and ECR Builds
resource "aws_secretsmanager_secret_version" "cicd_user" {
  count = var.create ? 1 : 0

  secret_id = aws_secretsmanager_secret.cicd_user[count.index].id
  secret_string = jsonencode({
    access_key     = aws_iam_access_key.cicd_keys[count.index].id
    secret_key     = aws_iam_access_key.cicd_keys[count.index].secret
    ecr_repo       = var.ecr_repository_url
    eks_cluster    = var.eks_cluster_name
    service_region = var.aws_region
  })
}
