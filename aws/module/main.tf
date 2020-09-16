################################################################################
# Required Terraform Block
################################################################################
terraform {
  required_version = ">= 0.13"
  backend "s3" {}
}

################################################################################
# Providers
################################################################################
provider "aws" {
  region = var.aws_region
}

################################################################################
# Local Generated Values
################################################################################
locals {
  # Adding a Terraform tag to a user provided map of tags.
  tags = merge(var.tags, map(
    "Terraform", "true",
  ))

  # Generating a list of AZs based on the provided desired number of AZs to use.
  azs = [
    for az in range(var.num_azs) :
    data.aws_availability_zones.available.names[az]
  ]

  # Splitting the provided in CIDR into two sections for public and private.
  split_cidr = cidrsubnets(var.cidr, 4, 4)

  # Generating a list of public subnets to use based off the provided CIDR.
  public_subnets = [
    for az in range(var.num_azs) :
    cidrsubnet(local.split_cidr[0], 4, az)
  ]

  # Generating a list of private subnets if private networking is enabled.
  # Also based off the provided CIDR.
  private_subnets = [
    for az in range(var.num_azs) :
    cidrsubnet(local.split_cidr[1], 4, az)
    if var.private_networking
  ]

  # Merges in default values for service definitions into a new map to use for looping.
  service_defaults = map(
    "service_db", false,
    "db_instance_type", "db.t3.micro",
    "enable_cloudwatch_db_logs", false,
    "add_db_secret", true,
    "s3_bucket", false,
    "s3_force_destroy", true,
    "ecr_scan_images", false,
    "container_port", 5000,
    "replicas", 2,
    "db_disk_size", 5,
    "deploy_eks", true,
    "cicd_user", true,
    "app_role", true
  )

  service_values = [
    for service in keys(var.services) :
    merge(local.service_defaults, var.services[service])
  ]

  services = zipmap(keys(var.services), local.service_values)
}

################################################################################
# Data Sources
################################################################################
# Grabbing all the AZs in the provided region.
data "aws_availability_zones" "available" {
  state = "available"
}

# Used to grab the current AWS account ID
data "aws_caller_identity" "current" {}

################################################################################
# Billing Cloudwatch Alert
################################################################################
module "billing_alert" {
  source = "git@github.com:ahodges22/terraform-aws-cost-billing-alarm.git"

  create                    = var.enable_billing_alert
  aws_env                   = var.name
  aws_account_id            = data.aws_caller_identity.current.account_id
  monthly_billing_threshold = var.billing_alert_threshold
  currency                  = "USD"
}

################################################################################
# VPC Networking
################################################################################
# Creating the VPC networking resources.
module "vpc" {
  # The AWS maintained VPC Terraform module.
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.48.0"

  name = var.name
  cidr = var.cidr

  # Using the generated lists above to determine AZs and subnets.
  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # If private networking is enabled, it sets up a NAT gateway per AZ.
  enable_nat_gateway     = var.private_networking ? true : false
  one_nat_gateway_per_az = var.private_networking ? true : false
  single_nat_gateway     = false

  # Misc settings for the VPC.
  enable_dns_hostnames         = true
  create_database_subnet_group = false

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"   = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }

  tags = local.tags
}

################################################################################
# EKS Cluster for Services
################################################################################
# Sets up the EKS cluster, using version 1.17 and a single worker group with autoscaling
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  create_eks      = var.eks_cluster
  cluster_name    = var.name
  cluster_version = "1.17"
  subnets         = var.private_networking ? module.vpc.private_subnets : module.vpc.public_subnets
  vpc_id          = module.vpc.vpc_id
  enable_irsa     = true

  map_users = [
    for user in keys(module.cicd_user) :
    {
      userarn  = module.cicd_user[user].arn
      username = module.cicd_user[user].name
      groups   = ["system:masters"]
    }
  ]

  worker_groups = [
    {
      instance_type = var.eks_node_type
      asg_max_size  = var.eks_max_nodes
      subnets       = var.private_networking ? module.vpc.private_subnets : module.vpc.public_subnets
      tags = [
        {
          "key"                 = "k8s.io/cluster-autoscaler/enabled"
          "propagate_at_launch" = "true"
          "value"               = "true"
        },
        {
          "key"                 = "k8s.io/cluster-autoscaler/${var.name}"
          "propagate_at_launch" = "true"
          "value"               = "owned"
        }
      ]
    }
  ]
}

# Sets up Kubernetes provider for use with service manifests
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.9"
}

# Setting up cluster autoscaler
module "cluster_autoscaler_role" {
  source                        = "github.com/ahodges22/terraform-aws-iam//modules/iam-assumable-role-with-oidc"
  create_role                   = true
  role_name                     = "${var.name}-cluster-autoscaler-role"
  provider_url                  = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  role_policy_arns              = [aws_iam_policy.cluster_autoscaler.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:cluster-autoscaler"]
}

resource "aws_iam_policy" "cluster_autoscaler" {
  name        = "${var.name}-cluster-autoscaler"
  description = "EKS cluster-autoscaler policy for cluster ${module.eks.cluster_id}"
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "clusterAutoscalerAll"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "clusterAutoscalerOwn"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${module.eks.cluster_id}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

module "kubernetes_cluster_autoscaler" {
  source  = "cookielab/cluster-autoscaler-aws/kubernetes"
  version = "0.9.0"

  aws_iam_role_for_policy              = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-cluster-autoscaler-role"
  aws_create_iam_policy                = false
  kubernetes_deployment_image_registry = "k8s.gcr.io/autoscaling/cluster-autoscaler"

  asg_tags = [
    "k8s.io/cluster-autoscaler/enabled",
    "k8s.io/cluster-autoscaler/${module.eks.cluster_id}",
  ]

  kubernetes_deployment_image_tag = "v1.17.3"
}
