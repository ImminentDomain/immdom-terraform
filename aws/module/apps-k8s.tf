################################################################################
# Service ECR Repo
################################################################################
module "ecr_repository" {
  source       = "./submodules/ecr-repository"
  for_each     = local.services
  create       = each.value.deploy_eks
  name         = each.key
  scan_on_push = each.value.ecr_scan_images
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
  create_role                   = each.value.app_role
  role_name                     = "${each.key}-role"
  provider_url                  = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  role_policy_arns              = [aws_iam_policy.app_policy[each.key].arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:default:${each.key}"]
}

################################################################################
# Service EKS Service Definitions
################################################################################
module "k8s_service" {
  source   = "./submodules/k8s-service"
  for_each = local.services
  create   = each.value.deploy_eks

  name           = each.key
  container_port = each.value.container_port
  db_host        = module.db[each.key]["this_db_instance_address"]
  db_name        = module.db[each.key]["this_db_instance_name"]
  db_user        = module.db[each.key]["this_db_instance_username"]
  db_pass        = module.db[each.key]["this_db_instance_password"]
  db_port        = module.db[each.key]["this_db_instance_port"]
  s3_bucket_name = module.s3[each.key]["this_s3_bucket_id"]
  s3_bucket_arn  = module.s3[each.key]["this_s3_bucket_arn"]
  account_id     = data.aws_caller_identity.current.account_id
  replicas       = each.value.replicas
  ecr_repository = module.ecr_repository[each.key].repository_url
}

################################################################################
# Service CI/CD IAM User
################################################################################
module "cicd_user" {
  source   = "./submodules/cicd-user"
  for_each = local.services
  create   = each.value.cicd_user

  name               = each.key
  ecr_repository     = module.ecr_repository[each.key].arn
  ecr_repository_url = module.ecr_repository[each.key].repository_url
  eks_cluster_name   = module.eks.cluster_id
  eks_cluster_arn    = module.eks.cluster_arn
  tags               = local.tags
  aws_region         = var.aws_region
}
