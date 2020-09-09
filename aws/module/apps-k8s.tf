################################################################################
# Service ECR Repo
################################################################################
resource "aws_ecr_repository" "app" {
  for_each = local.services
  name     = each.key
  image_scanning_configuration {
    scan_on_push = each.value.ecr_scan_images
  }
}

################################################################################
# Service IAM Role
################################################################################
data "aws_iam_policy_document" "app_policy" {
  for_each = local.services

  statement {
    actions = [
      "s3:*"
    ]

    resources = [
      "arn:aws:s3:::${each.key}-${var.name}",
      "arn:aws:s3:::${each.key}-${var.name}/*"
    ]
  }

  statement {
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]

    resources = [
      "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${each.key}"
    ]
  }
}

resource "aws_iam_policy" "app_policy" {
  for_each = local.services

  name_prefix = "${each.key}-policy"
  policy      = data.aws_iam_policy_document.app_policy[each.key].json
}

module "app_role" {
  for_each                      = local.services
  source                        = "github.com/ahodges22/terraform-aws-iam//modules/iam-assumable-role-with-oidc"
  create_role                   = true
  role_name                     = "${each.key}-role"
  provider_url                  = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  role_policy_arns              = [aws_iam_policy.app_policy[each.key].arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:default:${each.key}"]
}

################################################################################
# Service EKS Service Definitions
################################################################################
resource "kubernetes_secret" "db" {
  for_each = local.services

  metadata {
    name = "${each.key}-db"

    labels = {
      app     = each.key
      managed = "terraform"
    }
  }

  data = {
    "db_host" = module.db[each.key]["this_db_instance_address"]
    "db_name" = module.db[each.key]["this_db_instance_name"]
    "db_user" = module.db[each.key]["this_db_instance_username"]
    "db_pass" = module.db[each.key]["this_db_instance_password"]
    "db_port" = module.db[each.key]["this_db_instance_port"]
  }
}

resource "kubernetes_config_map" "s3" {
  for_each = local.services

  metadata {
    name = "${each.key}-s3"

    labels = {
      app     = each.key
      managed = "terraform"
    }
  }

  data = {
    "s3_bucket_name" = module.s3[each.key]["this_s3_bucket_id"]
    "s3_bucket_arn"  = module.s3[each.key]["this_s3_bucket_arn"]
  }
}

resource "kubernetes_service_account" "app_sa" {
  for_each = local.services

  metadata {
    name = each.key

    labels = {
      app     = each.key
      managed = "terraform"
    }

    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${each.key}-role"
    }
  }

  secret {
    name = kubernetes_secret.db[each.key].metadata.0.name
  }

  automount_service_account_token = true
}

resource "kubernetes_deployment" "app" {
  for_each = local.services

  metadata {
    name = each.key

    labels = {
      app     = each.key
      managed = "terraform"
    }
  }

  # Don't wait because the initial deploy will have no images pushed to the ECR repo
  wait_for_rollout = false

  spec {
    replicas = each.value.replicas

    selector {
      match_labels = {
        app     = each.key
        managed = "terraform"
      }
    }

    template {
      metadata {
        labels = {
          app     = each.key
          managed = "terraform"
        }
      }

      spec {
        service_account_name            = kubernetes_service_account.app_sa[each.key].metadata.0.name
        automount_service_account_token = true

        container {
          image = aws_ecr_repository.app[each.key].repository_url
          name  = each.key

          port {
            container_port = each.value.container_port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.db[each.key].metadata.0.name
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.s3[each.key].metadata.0.name
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      spec.0.template.0.spec.0.container.0.image
    ]
  }
}

resource "kubernetes_service" "app" {
  for_each = local.services

  metadata {
    name = each.key

    labels = {
      app     = each.key
      managed = "terraform"
    }
  }

  spec {
    selector = {
      app = "${kubernetes_deployment.app[each.key].metadata.0.labels.app}"
    }

    port {
      port        = each.value.container_port
      target_port = each.value.container_port
    }

    type = "LoadBalancer"
  }
}

################################################################################
# Service CI/CD IAM User
################################################################################
resource "aws_iam_user" "cicd" {
  for_each = local.services

  name = "srv_${each.key}_cicd"
}

resource "aws_iam_access_key" "cicd_keys" {
  for_each = local.services

  user = aws_iam_user.cicd[each.key].name
}

data "aws_iam_policy_document" "cicd_policy" {
  for_each = local.services

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
      aws_ecr_repository.app[each.key].arn
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
      module.eks.cluster_arn
    ]
  }
}

resource "aws_iam_user_policy" "cicd_user_policy" {
  for_each = local.services

  name   = "${each.key}_cicd"
  user   = aws_iam_user.cicd[each.key].name
  policy = data.aws_iam_policy_document.cicd_policy[each.key].json
}

# Add CI/CD User to Secrets Manager
resource "aws_secretsmanager_secret" "cicd_user" {
  for_each = local.services

  name = each.key
  tags = local.tags
}

# All the things needed for Github Actions Deploys and ECR Builds
resource "aws_secretsmanager_secret_version" "cicd_user" {
  for_each = local.services

  secret_id = aws_secretsmanager_secret.cicd_user[each.key].id
  secret_string = jsonencode({
    access_key     = aws_iam_access_key.cicd_keys[each.key].id
    secret_key     = aws_iam_access_key.cicd_keys[each.key].secret
    ecr_repo       = aws_ecr_repository.app[each.key].repository_url
    eks_cluster    = module.eks.cluster_id
    service_region = var.aws_region
  })
}
